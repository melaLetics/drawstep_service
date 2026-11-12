import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:drawstep_service/drawstep_service.dart';

/// Baut ein neues Datenpaket aus den aktuellen Scryfall-Daten und legt es
/// im Veröffentlichungsordner (`--site`) ab – aber nur, wenn sich etwas
/// geändert hat.
///
///   dart run bin/build.dart --site site --start 2026-11-10
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('site', defaultsTo: 'site', help: 'Veröffentlichungsordner (z. B. gh-pages-Checkout).')
    ..addOption('start', help: 'Starttag yyyy-mm-dd. Nur beim ersten Lauf oder mit --reset-plan.')
    ..addFlag('reset-plan', negatable: false, help: 'Zeitplan komplett neu erzeugen (nur vor dem Release!).')
    ..addOption('freeze-days', defaultsTo: '30', help: 'So viele Tage ab heute bleiben im Zeitplan unverändert.')
    ..addOption('cache', defaultsTo: '.cache', help: 'Ordner für die Scryfall-Bulk-Datei.')
    ..addOption('version', help: 'Datenversion; Standard: heutiges Datum yyyy.mm.dd.')
    ..addOption('min-app-version', defaultsTo: '1.0.0')
    ..addOption('today', help: 'Heutiges Datum überschreiben (nur für Tests).')
    ..addOption('keep', defaultsTo: '4', help: 'So viele alte Pakete bleiben liegen.')
    ..addFlag('skip-icons', negatable: false, help: 'Keine Set-Symbole laden.')
    ..addFlag('skip-german', negatable: false, help: 'Keine deutschen Namen laden (spart den großen Download von all_cards).')
    ..addFlag('force', negatable: false, help: 'Auch ohne Änderung veröffentlichen.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    _fail('${e.message}\n\n${parser.usage}');
  }
  if (args.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  final now = DateTime.now().toUtc();
  final today = args.option('today') != null ? parseDate(args.option('today')!) : now;
  final freezeDays = int.parse(args.option('freeze-days')!);
  final site = Site(Directory(args.option('site')!)..createSync(recursive: true));
  final previousPlan = args.flag('reset-plan') ? null : site.readPlan();
  final previousManifest = site.readManifest();

  final startArg = args.option('start');
  final DateTime start;
  if (previousPlan != null) {
    start = previousPlan.start;
    if (startArg != null && startArg.isNotEmpty && parseDate(startArg) != start) {
      stderr.writeln('Hinweis: --start wird ignoriert, der Plan beginnt am '
          '${formatDate(start)}. Zum Ändern --reset-plan verwenden.');
    }
  } else if (startArg != null && startArg.isNotEmpty) {
    start = parseDate(startArg);
  } else {
    _fail('Es gibt noch keinen Zeitplan – bitte --start yyyy-mm-dd angeben.');
  }

  final client = ScryfallClient();
  try {
    stdout.writeln('Scryfall: suche Bulk-Datei "default_cards" …');
    final bulk = await client.defaultCardsInfo();
    stdout.writeln('  Stand ${bulk.updatedAt}, lade ${bulk.downloadUri}');
    final bulkFile = await client.downloadToCache(bulk.downloadUri, Directory(args.option('cache')!));

    stdout.writeln('Verarbeite Druckversionen …');
    final collector = FirstPrintingCollector(releasedUntil: formatDate(today));
    await for (final printing in readBulkCards(bulkFile)) {
      collector.add(printing);
    }
    var cards = collector.build();
    stdout.writeln('  ${collector.seen} Druckversionen, ${collector.eligible} zulässig, '
        '${cards.length} Karten');
    if (cards.length < 20000) {
      _fail('Nur ${cards.length} Karten – das sieht nach einem Fehler aus, breche ab.');
    }

    if (!args.flag('skip-german')) {
      stdout.writeln('Scryfall: suche Bulk-Datei "all_cards" für die deutschen Namen …');
      final all = await client.bulkInfo('all_cards');
      stdout.writeln('  Stand ${all.updatedAt}, lade ${all.downloadUri}');
      final allFile = await client.downloadToCache(all.downloadUri, Directory(args.option('cache')!));
      final names = LocalizedNameCollector(lang: 'de');
      await for (final printing in readBulkCards(allFile, lineFilter: names.mightMatch)) {
        names.add(printing);
      }
      cards = names.apply(cards);
      final withDe = cards.where((c) => c.nameDe != null).length;
      stdout.writeln('  ${names.length} deutsche Namen gefunden, $withDe Karten mit eigenem deutschen Namen');
      if (withDe < 5000) {
        _fail('Nur $withDe deutsche Namen – das sieht nach einem Fehler aus, breche ab.');
      }
    }

    stdout.writeln('Lade Set-Liste …');
    final sets = await client.sets();

    final baseVersion = args.option('version') ?? _dateVersion(now);
    final plan = updatePlan(
      previous: previousPlan,
      allIds: [for (final c in cards) c.oracleId],
      start: start,
      today: today,
      freezeDays: freezeDays,
      random: Random(seedFrom('${formatDate(start)}|$baseVersion')),
    );
    final package = DataPackage(cards: cards, sets: sets, plan: plan);

    final unchanged = previousManifest?['contentHash'] == package.contentHash;
    if (unchanged && !args.flag('force') && !args.flag('reset-plan')) {
      stdout.writeln('Keine Änderung gegenüber ${previousManifest?['version']} – nichts zu veröffentlichen.');
      _githubOutput({'changed': 'false'});
      return;
    }

    final version = site.freeVersion(baseVersion);
    if (!args.flag('skip-icons')) {
      stdout.writeln('Lade fehlende Set-Symbole …');
      final added = await site.downloadMissingIcons(package.setCodes, sets, client);
      stdout.writeln('  $added neu');
    }
    site.publish(
      package: package,
      plan: plan,
      version: version,
      minAppVersion: args.option('min-app-version')!,
    );
    final removed = site.prune(keep: int.parse(args.option('keep')!));

    final todayIndex = dayIndex(plan.start, today);
    stdout
      ..writeln('Veröffentlicht: Version $version in ${p.normalize(site.dir.path)}')
      ..writeln('  Starttag ${formatDate(plan.start)}, heute ist Tag $todayIndex, '
          'Plan reicht ${plan.ids.length} Tage')
      ..writeln(removed.isEmpty ? '' : '  Alte Pakete entfernt: ${removed.join(', ')}');
    _githubOutput({'changed': 'true', 'version': version});
  } finally {
    client.close();
  }
}

String _dateVersion(DateTime d) => '${d.year}.'
    '${d.month.toString().padLeft(2, '0')}.'
    '${d.day.toString().padLeft(2, '0')}';

/// Schreibt Ausgaben für GitHub Actions (`steps.<id>.outputs.<name>`).
void _githubOutput(Map<String, String> values) {
  final path = Platform.environment['GITHUB_OUTPUT'];
  if (path == null) return;
  File(path).writeAsStringSync(
    values.entries.map((e) => '${e.key}=${e.value}\n').join(),
    mode: FileMode.append,
  );
}

Never _fail(String message) {
  stderr.writeln('Fehler: $message');
  exit(1);
}
