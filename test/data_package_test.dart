import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:drawstep_service/drawstep_service.dart';

GameCard card(String id, String name, String set) => GameCard(
      oracleId: id,
      name: name,
      manaValue: 1,
      types: const ['Instant'],
      subtypes: const [],
      colors: const ['R'],
      rarity: 'common',
      setCode: set,
      released: '1993-08-05',
      scryfallId: 'sf-$id',
    );

void main() {
  final cards = [card('a', 'Anger', 'lea'), card('b', 'Bolt', 'm10')];
  final sets = {
    'lea': SetInfo(code: 'lea', name: 'Limited Edition Alpha', setType: 'core', released: '1993-08-05', iconUri: null),
    'm10': SetInfo(code: 'm10', name: 'Magic 2010', setType: 'core', released: '2009-07-17', iconUri: null),
  };
  final plan = Plan(DateTime.utc(2026, 11, 10), ['b', 'a']);

  test('daily.json enthält Indizes in die Kartenliste', () {
    final pkg = DataPackage(cards: cards, sets: sets, plan: plan);
    final daily = jsonDecode(pkg.dailyJson) as Map<String, dynamic>;
    expect(daily['start'], '2026-11-10');
    expect(daily['answers'], [1, 0]);
  });

  test('sets.json enthält nur genutzte Sets, nach Datum sortiert', () {
    final pkg = DataPackage(cards: cards, sets: sets, plan: plan);
    final list = jsonDecode(pkg.setsJson) as List;
    expect(list.map((s) => s['code']), ['lea', 'm10']);
  });

  test('contentHash ist bei gleichem Inhalt gleich', () {
    final a = DataPackage(cards: cards, sets: sets, plan: plan);
    final b = DataPackage(cards: cards, sets: sets, plan: plan);
    expect(a.contentHash, b.contentHash);
    final c = DataPackage(cards: cards, sets: sets, plan: Plan(plan.start, ['a', 'b']));
    expect(c.contentHash, isNot(a.contentHash));
  });

  test('unbekannte Karte im Plan ist ein Fehler', () {
    expect(
      () => DataPackage(cards: cards, sets: sets, plan: Plan(plan.start, ['x'])),
      throwsStateError,
    );
  });

  test('Site.publish schreibt Paket, Plan und Manifest mit Prüfsummen', () {
    final dir = Directory.systemTemp.createTempSync('drawstep_site_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final site = Site(dir);
    final pkg = DataPackage(cards: cards, sets: sets, plan: plan);

    final version = site.freeVersion('2026.11.07');
    final manifest = site.publish(package: pkg, plan: plan, version: version, minAppVersion: '1.0.0');

    expect(manifest['version'], '2026.11.07');
    final cardsEntry = (manifest['files'] as Map)['cards'] as Map;
    final bytes = File(p.join(dir.path, cardsEntry['path'] as String)).readAsBytesSync();
    expect(sha256.convert(bytes).toString(), cardsEntry['sha256']);
    expect(utf8.decode(gzip.decode(bytes)), pkg.cardsJson);

    expect(site.readPlan()!.ids, plan.ids);
    expect(site.readManifest()!['contentHash'], pkg.contentHash);
    expect(site.freeVersion('2026.11.07'), '2026.11.07.2');
  });

  test('setIconFileName weicht Windows-Gerätenamen aus', () {
    expect(setIconFileName('lea'), 'lea.svg');
    expect(setIconFileName('con'), 'con_.svg');
    expect(setIconFileName('COM1'), 'COM1_.svg');
  });

  test('Site.prune behält die neuesten Versionen', () {
    final dir = Directory.systemTemp.createTempSync('drawstep_prune_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final site = Site(dir);
    for (final v in ['2026.10.01', '2026.10.08', '2026.10.08.2', '2026.10.15']) {
      Directory(p.join(site.dataDir.path, v)).createSync(recursive: true);
    }
    expect(site.prune(keep: 2)..sort(), ['2026.10.01', '2026.10.08']);
  });
}
