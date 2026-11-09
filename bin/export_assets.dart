import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:topdecked_service/topdecked_service.dart';

/// Kopiert ein Datenpaket als Grundbestand in die App.
///
/// Aus dem lokalen Build-Ordner:
///   dart run bin/export_assets.dart --site site --to ../topdecked/assets
///
/// Aus den veröffentlichten Daten (GitHub Pages) – für Releases, damit App
/// und Updates garantiert denselben Zeitplan haben:
///   dart run bin/export_assets.dart --pages --to ../topdecked/assets
///
/// Ergebnis:
///   assets/data/cards.json.gz, sets.json, daily.json, version.txt
///   assets/sets/<code>.svg  (nur die Sets, die im Paket vorkommen)
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('site', defaultsTo: 'site', help: 'Lokaler Veröffentlichungsordner.')
    ..addFlag('pages', negatable: false, help: 'Stattdessen von GitHub Pages laden.')
    ..addOption('pages-url',
        defaultsTo: 'https://melaletics.github.io/topdecked_service/', help: 'Basis-URL der veröffentlichten Daten.')
    ..addOption('to', mandatory: true, help: 'assets-Ordner der App');
  final args = parser.parse(arguments);

  final Source source = args.flag('pages')
      ? PagesSource(Uri.parse(args.option('pages-url')!))
      : LocalSource(Directory(args.option('site')!));

  try {
    final manifest = jsonDecode(utf8.decode(await source.read('manifest.json'))) as Map<String, dynamic>;
    final version = manifest['version'] as String;
    final files = (manifest['files'] as Map).cast<String, dynamic>();

    // Erst alles laden und prüfen, dann schreiben – so bleibt bei einem
    // Fehler der alte Grundbestand vollständig erhalten.
    final downloaded = <String, List<int>>{};
    for (final entry in files.entries) {
      final info = (entry.value as Map).cast<String, dynamic>();
      final path = info['path'] as String;
      final bytes = await source.read(path);
      if (sha256.convert(bytes).toString() != info['sha256']) {
        throw StateError('Prüfsumme von $path stimmt nicht');
      }
      downloaded[path] = bytes;
    }

    final dataOut = Directory(p.join(args.option('to')!, 'data'))..createSync(recursive: true);
    final iconsOut = Directory(p.join(args.option('to')!, 'sets'))..createSync(recursive: true);
    downloaded.forEach((path, bytes) => File(p.join(dataOut.path, p.basename(path))).writeAsBytesSync(bytes));
    File(p.join(dataOut.path, 'version.txt')).writeAsStringSync(version);

    final setsPath = ((files['sets'] as Map)['path']) as String;
    final codes = [
      for (final s in jsonDecode(utf8.decode(downloaded[setsPath]!)) as List) (s as Map)['code'] as String,
    ];
    var copied = 0;
    final missing = <String>[];
    for (final code in codes) {
      final name = setIconFileName(code);
      try {
        File(p.join(iconsOut.path, name)).writeAsBytesSync(await source.read('sets/$name'));
        copied++;
      } on Object {
        missing.add(code);
      }
    }

    stdout.writeln('Version $version (${manifest['cardCount']} Karten) nach '
        '${p.normalize(args.option('to')!)} kopiert, $copied Set-Symbole.');
    if (missing.isNotEmpty) {
      stdout.writeln('Ohne Symbol (die App zeigt den Set-Code): ${missing.join(', ')}');
    }
  } on Object catch (e) {
    stderr.writeln('Fehler: $e');
    exitCode = 1;
  } finally {
    source.close();
  }
}

/// Woher das Paket kommt.
abstract class Source {
  Future<List<int>> read(String path);
  void close() {}
}

class LocalSource extends Source {
  LocalSource(this.dir);
  final Directory dir;

  @override
  Future<List<int>> read(String path) => File(p.join(dir.path, path)).readAsBytes();
}

class PagesSource extends Source {
  PagesSource(this.base) : _client = HttpClient()..userAgent = 'TopdeckedService/0.1';
  final Uri base;
  final HttpClient _client;

  @override
  Future<List<int>> read(String path) async {
    final uri = base.resolve(path);
    final response = await (await _client.getUrl(uri)).close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  void close() => _client.close(force: true);
}
