import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// Kopiert das aktuelle Datenpaket als Grundbestand in die App:
///
///   dart run bin/export_assets.dart --site site --to ../topdecked/assets
///
/// Ergebnis:
///   assets/data/cards.json.gz, sets.json, daily.json, version.txt
///   assets/sets/<code>.svg  (nur die Sets, die im Paket vorkommen)
void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('site', defaultsTo: 'site')
    ..addOption('to', mandatory: true, help: 'assets-Ordner der App');
  final args = parser.parse(arguments);

  final site = Directory(args.option('site')!);
  final manifestFile = File(p.join(site.path, 'manifest.json'));
  if (!manifestFile.existsSync()) {
    stderr.writeln('Kein manifest.json in ${site.path} – erst bin/build.dart ausführen.');
    exit(1);
  }
  final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final files = (manifest['files'] as Map).cast<String, dynamic>();

  final dataOut = Directory(p.join(args.option('to')!, 'data'))..createSync(recursive: true);
  final iconsOut = Directory(p.join(args.option('to')!, 'sets'))..createSync(recursive: true);

  for (final entry in files.values) {
    final source = File(p.join(site.path, (entry as Map)['path'] as String));
    source.copySync(p.join(dataOut.path, p.basename(source.path)));
  }
  File(p.join(dataOut.path, 'version.txt')).writeAsStringSync(manifest['version'] as String);

  final setsPath = p.join(site.path, (files['sets'] as Map)['path'] as String);
  final codes = [
    for (final s in jsonDecode(File(setsPath).readAsStringSync()) as List) (s as Map)['code'] as String,
  ];
  var copied = 0;
  for (final code in codes) {
    final icon = File(p.join(site.path, 'sets', '$code.svg'));
    if (icon.existsSync()) {
      icon.copySync(p.join(iconsOut.path, '$code.svg'));
      copied++;
    }
  }

  stdout.writeln('Version ${manifest['version']} nach ${p.normalize(args.option('to')!)} '
      'kopiert ($copied Set-Symbole).');
}
