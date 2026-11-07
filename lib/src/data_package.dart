import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'game_card.dart';
import 'schedule.dart';
import 'scryfall.dart';

/// Aktuelle Version des Datenformats. Ändert sich das Format so, dass alte
/// App-Versionen es nicht lesen können, wird sie erhöht.
const schemaVersion = 1;

/// Unter Windows reservierte Gerätenamen – solche Dateinamen sind dort
/// nicht möglich, auch nicht mit Endung (z. B. das Set Conflux, Code `con`).
const _windowsReserved = {
  'con', 'prn', 'aux', 'nul',
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// Dateiname des Set-Symbols: `<code>.svg`, bei reservierten Namen
/// `<code>_.svg`. Die App verwendet dieselbe Regel.
String setIconFileName(String code) =>
    _windowsReserved.contains(code.toLowerCase()) ? '${code}_.svg' : '$code.svg';

/// Vergleicht Versionen wie `2026.11.07` oder `2026.11.07.2` numerisch.
int compareVersions(String a, String b) {
  final pa = a.split('.');
  final pb = b.split('.');
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? int.tryParse(pa[i]) ?? 0 : 0;
    final y = i < pb.length ? int.tryParse(pb[i]) ?? 0 : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Inhalt eines Datenpakets als unkomprimiertes JSON.
class DataPackage {
  factory DataPackage({
    required List<GameCard> cards,
    required Map<String, SetInfo> sets,
    required Plan plan,
  }) {
    final cardsJson = jsonEncode([for (final c in cards) c.toJson()]);

    final usedCodes = {for (final c in cards) c.setCode};
    final setList = [
      for (final code in usedCodes)
        {
          'code': code,
          'name': sets[code]?.name ?? code.toUpperCase(),
          'date': sets[code]?.released,
        },
    ]..sort((a, b) {
        final byDate = (a['date'] ?? '').compareTo(b['date'] ?? '');
        return byDate != 0 ? byDate : a['code']!.compareTo(b['code']!);
      });

    final indexById = {
      for (var i = 0; i < cards.length; i++) cards[i].oracleId: i,
    };
    final answers = [
      for (final id in plan.ids)
        indexById[id] ??
            (throw StateError('Zeitplan verweist auf unbekannte Karte $id')),
    ];

    return DataPackage._(
      cardsJson: cardsJson,
      setsJson: jsonEncode(setList),
      dailyJson: jsonEncode({'start': formatDate(plan.start), 'answers': answers}),
      setCodes: usedCodes,
      cardCount: cards.length,
    );
  }

  DataPackage._({
    required this.cardsJson,
    required this.setsJson,
    required this.dailyJson,
    required this.setCodes,
    required this.cardCount,
  });

  final String cardsJson;
  final String setsJson;

  /// `{"start": "yyyy-mm-dd", "answers": [Index in cards.json, ...]}`
  final String dailyJson;
  final Set<String> setCodes;
  final int cardCount;

  /// Prüfsumme über den Inhalt – unabhängig von Version und Komprimierung.
  /// Gleicher Hash = keine Änderung, nichts zu veröffentlichen.
  String get contentHash => sha256
      .convert(utf8.encode('$schemaVersion\n$cardsJson\n$setsJson\n$dailyJson'))
      .toString();
}

/// Der Veröffentlichungsordner (lokal oder der `gh-pages`-Checkout):
///
/// ```
/// manifest.json          ← die App fragt nur diese Datei ab
/// plan.json              ← interner Zeitplan mit oracle_ids (nur für das Build-Skript)
/// data/<version>/...     ← cards.json.gz, sets.json, daily.json, version.txt
/// sets/<code>.svg        ← Set-Symbole
/// ```
class Site {
  Site(this.dir);

  final Directory dir;

  File get manifestFile => File(p.join(dir.path, 'manifest.json'));
  File get planFile => File(p.join(dir.path, 'plan.json'));
  Directory get dataDir => Directory(p.join(dir.path, 'data'));
  Directory get iconDir => Directory(p.join(dir.path, 'sets'));

  Map<String, dynamic>? readManifest() => manifestFile.existsSync()
      ? jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>
      : null;

  Plan? readPlan() => planFile.existsSync()
      ? Plan.fromJson(jsonDecode(planFile.readAsStringSync()) as Map<String, dynamic>)
      : null;

  /// [base], oder `base.2`, `base.3` …, falls es den Ordner schon gibt.
  String freeVersion(String base) {
    var version = base;
    var n = 2;
    while (Directory(p.join(dataDir.path, version)).existsSync()) {
      version = '$base.${n++}';
    }
    return version;
  }

  /// Schreibt Paket, Plan und zuletzt das Manifest. Gibt das Manifest zurück.
  Map<String, dynamic> publish({
    required DataPackage package,
    required Plan plan,
    required String version,
    required String minAppVersion,
  }) {
    final folder = 'data/$version';
    final target = Directory(p.join(dir.path, folder))..createSync(recursive: true);

    Map<String, Object> write(String name, List<int> bytes) {
      File(p.join(target.path, name)).writeAsBytesSync(bytes);
      return {
        'path': '$folder/$name',
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      };
    }

    final files = {
      'cards': write(
        'cards.json.gz',
        GZipCodec(level: 9).encode(utf8.encode(package.cardsJson)),
      ),
      'sets': write('sets.json', utf8.encode(package.setsJson)),
      'daily': write('daily.json', utf8.encode(package.dailyJson)),
    };
    File(p.join(target.path, 'version.txt')).writeAsStringSync(version);

    planFile.writeAsStringSync(jsonEncode(plan.toJson()));

    final manifest = <String, dynamic>{
      'schema': schemaVersion,
      'version': version,
      'minAppVersion': minAppVersion,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'contentHash': package.contentHash,
      'cardCount': package.cardCount,
      'files': files,
      'setIcons': 'sets/',
    };
    manifestFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
    return manifest;
  }

  /// Lädt Set-Symbole, die noch fehlen. Gibt die Anzahl neuer Symbole zurück.
  Future<int> downloadMissingIcons(
    Iterable<String> codes,
    Map<String, SetInfo> sets,
    ScryfallClient client, {
    Duration pause = const Duration(milliseconds: 50),
  }) async {
    iconDir.createSync(recursive: true);
    var added = 0;
    for (final code in codes) {
      final file = File(p.join(iconDir.path, setIconFileName(code)));
      final uri = sets[code]?.iconUri;
      if (file.existsSync() || uri == null) continue;
      try {
        file.writeAsBytesSync(await client.getBytes(uri));
        added++;
      } on Exception catch (e) {
        stderr.writeln('Set-Symbol $code nicht geladen: $e');
      }
      await Future<void>.delayed(pause);
    }
    return added;
  }

  /// Behält nur die [keep] neuesten Pakete (nach Versionsnummer).
  List<String> prune({int keep = 4}) {
    if (!dataDir.existsSync()) return const [];
    final folders = dataDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => compareVersions(p.basename(b.path), p.basename(a.path)));
    final removed = <String>[];
    for (final folder in folders.skip(keep)) {
      folder.deleteSync(recursive: true);
      removed.add(p.basename(folder.path));
    }
    return removed;
  }
}
