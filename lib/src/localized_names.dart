import 'card_rules.dart';
import 'game_card.dart';

/// Gedruckter Name einer fremdsprachigen Druckversion, gebildet nach
/// derselben Regel wie [gameName]: Split- und Aftermath-Karten mit beiden
/// Hälften, sonst die Vorderseite.
String? printedGameName(Map<String, dynamic> p) {
  final faces = p['card_faces'];
  if (faces is List && faces.isNotEmpty) {
    final printed = [
      for (final f in faces) (f as Map)['printed_name'] as String?,
    ];
    if (fullNameLayouts.contains(p['layout'])) {
      if (printed.any((n) => n == null || n.isEmpty)) return p['printed_name'] as String?;
      return printed.join(' // ');
    }
    final front = printed.first;
    if (front != null && front.isNotEmpty) return front;
  }
  final top = p['printed_name'] as String?;
  if (top == null || top.isEmpty) return null;
  // Mehrseitige Karte ohne Namen je Seite: Vorderseite aus „A // B“.
  if (top.contains(' // ') && !fullNameLayouts.contains(p['layout'])) {
    return top.split(' // ').first;
  }
  return top;
}

/// Sammelt pro `oracle_id` den deutschen Namen aus der Bulk-Datei
/// `all_cards`. Gibt es mehrere deutsche Drucke, gewinnt der neueste –
/// Übersetzungen wurden über die Jahre gelegentlich angepasst.
class LocalizedNameCollector {
  LocalizedNameCollector({this.lang = 'de'});

  final String lang;
  final _best = <String, (String released, String name)>{};
  int seen = 0;

  /// Schneller Vorfilter für Zeilen der Bulk-Datei, bevor sie dekodiert werden.
  bool mightMatch(String line) => line.contains('"lang":"$lang"');

  void add(Map<String, dynamic> p) {
    seen++;
    if (p['lang'] != lang || p['object'] != 'card') return;
    if (p['digital'] == true) return;
    final oracleId = p['oracle_id'] ?? ((p['card_faces'] as List?)?.first as Map?)?['oracle_id'];
    if (oracleId is! String) return;
    final name = printedGameName(p);
    if (name == null) return;
    final released = p['released_at'] as String? ?? '';
    final current = _best[oracleId];
    if (current == null || released.compareTo(current.$1) > 0) {
      _best[oracleId] = (released, name.trim());
    }
  }

  int get length => _best.length;

  String? nameFor(String oracleId) => _best[oracleId]?.$2;

  /// Ergänzt die Karten um ihren deutschen Namen (nur wenn er sich vom
  /// englischen unterscheidet).
  List<GameCard> apply(List<GameCard> cards) => [
        for (final c in cards)
          switch (nameFor(c.oracleId)) {
            final n? when n != c.name => c.withNameDe(n),
            _ => c,
          },
      ];
}
