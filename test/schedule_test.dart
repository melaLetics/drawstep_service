import 'dart:math';

import 'package:test/test.dart';
import 'package:drawstep_service/drawstep_service.dart';

void main() {
  final start = DateTime.utc(2026, 11, 10);
  List<String> ids(int n) => [for (var i = 0; i < n; i++) 'c${i.toString().padLeft(3, '0')}'];

  group('dayIndex', () {
    test('zählt Kalendertage ab dem Start', () {
      expect(dayIndex(start, DateTime.utc(2026, 11, 10)), 0);
      expect(dayIndex(start, DateTime.utc(2026, 11, 11, 23, 59)), 1);
      expect(dayIndex(start, DateTime.utc(2026, 11, 9)), -1);
    });

    test('über die Zeitumstellung hinweg', () {
      // 29.03.2027: Sommerzeit hat am 28.03. begonnen.
      expect(dayIndex(start, DateTime(2027, 3, 29, 0, 30)), 139);
    });
  });

  test('parseDate und formatDate passen zusammen', () {
    expect(formatDate(parseDate('2027-01-05')), '2027-01-05');
    expect(() => parseDate('5.1.2027'), throwsFormatException);
  });

  group('updatePlan', () {
    test('erster Plan enthält jede Karte genau einmal', () {
      final plan = updatePlan(
        previous: null,
        allIds: ids(100),
        start: start,
        today: start,
        random: Random(1),
      );
      expect(plan.ids.toSet(), ids(100).toSet());
      expect(plan.ids, hasLength(100));
    });

    test('ohne neue Karten bleibt der Plan identisch', () {
      final first = updatePlan(previous: null, allIds: ids(100), start: start, today: start, random: Random(1));
      final again = updatePlan(
        previous: first,
        allIds: ids(100),
        start: start,
        today: start.add(const Duration(days: 20)),
        random: Random(99),
      );
      expect(again.ids, first.ids);
    });

    test('neue Karten landen erst nach dem gesperrten Zeitraum', () {
      final first = updatePlan(previous: null, allIds: ids(100), start: start, today: start, random: Random(1));
      final today = start.add(const Duration(days: 10));
      final next = updatePlan(
        previous: first,
        allIds: [...ids(100), 'neu1', 'neu2'],
        start: start,
        today: today,
        freezeDays: 30,
        random: Random(2),
      );
      // Tag 0 bis Tag 40 (heute + 30) bleibt unverändert.
      expect(next.ids.sublist(0, 41), first.ids.sublist(0, 41));
      expect(next.ids, hasLength(102));
      expect(next.ids.indexOf('neu1'), greaterThan(40));
      expect(next.ids.indexOf('neu2'), greaterThan(40));
    });

    test('entfernte Karten verschwinden aus der Zukunft', () {
      final first = updatePlan(previous: null, allIds: ids(100), start: start, today: start, random: Random(1));
      final gone = first.ids.last;
      final next = updatePlan(
        previous: first,
        allIds: ids(100).where((id) => id != gone).toList(),
        start: start,
        today: start,
        random: Random(2),
      );
      expect(next.ids, isNot(contains(gone)));
      expect(next.ids, hasLength(99));
    });

    test('fehlende Karte im gesperrten Zeitraum ist ein Fehler', () {
      final first = updatePlan(previous: null, allIds: ids(100), start: start, today: start, random: Random(1));
      final gone = first.ids.first;
      expect(
        () => updatePlan(
          previous: first,
          allIds: ids(100).where((id) => id != gone).toList(),
          start: start,
          today: start,
          random: Random(2),
        ),
        throwsStateError,
      );
    });

    test('Starttag bleibt beim Fortschreiben erhalten', () {
      final first = updatePlan(previous: null, allIds: ids(10), start: start, today: start, random: Random(1));
      final next = updatePlan(
        previous: first,
        allIds: ids(10),
        start: DateTime.utc(2030, 1, 1),
        today: start,
        random: Random(2),
      );
      expect(next.start, start);
    });
  });

  test('seedFrom ist deterministisch', () {
    expect(seedFrom('2026-11-10|2026.11.07'), seedFrom('2026-11-10|2026.11.07'));
    expect(seedFrom('a'), isNot(seedFrom('b')));
  });

  test('compareVersions vergleicht numerisch', () {
    expect(compareVersions('2026.11.07.10', '2026.11.07.2'), greaterThan(0));
    expect(compareVersions('2026.11.07', '2026.11.07.2'), lessThan(0));
    expect(compareVersions('2027.01.01', '2026.12.31'), greaterThan(0));
  });
}
