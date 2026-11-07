import 'dart:math';

/// Der interne Zeitplan: Starttag und eine Reihenfolge aller Karten
/// (`oracle_id`s). Eintrag `n` ist die Lösung von Tag `n` (Tag 0 = Start).
///
/// Der Plan enthält jede Karte genau einmal, es gibt also keine
/// Wiederholungen, solange Karten übrig sind.
class Plan {
  Plan(this.start, this.ids);

  factory Plan.fromJson(Map<String, dynamic> json) =>
      Plan(parseDate(json['start'] as String), (json['ids'] as List).cast<String>());

  final DateTime start;
  final List<String> ids;

  Map<String, Object> toJson() => {'start': formatDate(start), 'ids': ids};
}

/// `yyyy-mm-dd` → Mitternacht UTC.
DateTime parseDate(String s) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
  if (match == null) throw FormatException('Datum muss yyyy-mm-dd sein', s);
  return DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

String formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Tagesindex nach Kalenderdatum – unabhängig von Uhrzeit und Sommerzeit.
int dayIndex(DateTime start, DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).difference(start).inDays;

/// Erzeugt einen neuen Plan oder schreibt den bisherigen fort.
///
/// * Ohne [previous]: alle Karten zufällig gemischt ab [start].
/// * Mit [previous]: Alle Tage bis `heute + freezeDays` bleiben exakt gleich.
///   Danach werden nicht mehr vorhandene Karten entfernt und neue Karten an
///   zufälligen Stellen eingefügt. Gibt es keine neuen oder entfernten
///   Karten, ist das Ergebnis identisch mit [previous].
///
/// Wirft einen [StateError], wenn eine Karte im gesperrten Bereich nicht
/// mehr in [allIds] vorkommt – das muss ein Mensch entscheiden.
Plan updatePlan({
  required Plan? previous,
  required List<String> allIds,
  required DateTime start,
  required DateTime today,
  required Random random,
  int freezeDays = 30,
}) {
  final sortedIds = [...allIds]..sort();

  if (previous == null) {
    return Plan(start, sortedIds..shuffle(random));
  }

  final available = sortedIds.toSet();
  final frozenLength = min(
    max(0, dayIndex(previous.start, today) + freezeDays + 1),
    previous.ids.length,
  );
  final frozen = previous.ids.sublist(0, frozenLength);

  final missing = frozen.where((id) => !available.contains(id)).toList();
  if (missing.isNotEmpty) {
    throw StateError(
      'Karten im gesperrten Zeitraum fehlen in den neuen Daten: '
      '${missing.take(5).join(', ')}${missing.length > 5 ? ' …' : ''}',
    );
  }

  final future =
      previous.ids.sublist(frozenLength).where(available.contains).toList();
  final known = previous.ids.toSet();
  for (final id in sortedIds.where((id) => !known.contains(id))) {
    future.insert(random.nextInt(future.length + 1), id);
  }

  return Plan(previous.start, [...frozen, ...future]);
}

/// Deterministischer Seed aus einem Text (z. B. der Datenversion), damit
/// ein Lauf mit gleichen Eingaben das gleiche Ergebnis liefert.
int seedFrom(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
