import 'game_card.dart';

/// Layouts, die keine normalen Spielkarten sind oder ausgeschlossen werden
/// (Archenemy-Schemes, Planechase-Planes und -Phenomenons, Tokens usw.).
const excludedLayouts = {
  'token',
  'double_faced_token',
  'emblem',
  'art_series',
  'vanguard',
  'scheme',
  'planar',
};

/// Set-Typen, deren Druckversionen nie zählen.
/// `funny` = Un-Sets (Unglued bis Unfinity) und Playtest-Karten.
const excludedSetTypes = {'funny', 'memorabilia', 'token', 'minigame'};

/// Kartentypen, die ausgeschlossen werden – zusätzlich zu den Layouts,
/// falls Scryfall eine solche Karte mit anderem Layout führt.
const excludedTypes = {
  'Scheme',
  'Plane',
  'Phenomenon',
  'Vanguard',
  'Dungeon',
  'Emblem',
  'Token',
  'Stickers',
  'Attraction',
  'Contraption',
};

/// Set-Typen, die nie als Erstdruck zählen. Gibt es eine Karte nur in
/// solchen Sets (z. B. Convention-Karten der MagicFest-Events oder
/// Vorschau-Promos, deren Set noch nicht erschienen ist), fliegt sie raus.
const secondarySetTypes = {'promo'};

/// Layouts, bei denen der volle Name mit `//` der übliche Kartenname ist.
/// Bei allen anderen mehrseitigen Karten zählt der Name der Vorderseite.
const fullNameLayouts = {'split', 'aftermath'};

/// Untertypen aus mehreren Wörtern, die nicht getrennt werden dürfen.
const multiWordSubtypes = ['Time Lord'];

/// Ergebnis von [parseTypeLine].
class TypeLine {
  const TypeLine(this.types, this.subtypes);
  final List<String> types;
  final List<String> subtypes;
}

/// Teilt eine Typzeile am Gedankenstrich:
/// `Legendary Creature — Elf Druid` → `[Legendary, Creature]`, `[Elf, Druid]`.
TypeLine parseTypeLine(String line) {
  final dash = line.indexOf('—');
  final left = (dash < 0 ? line : line.substring(0, dash)).trim();
  var right = dash < 0 ? '' : line.substring(dash + 1).trim();

  final placeholders = <String, String>{};
  for (var i = 0; i < multiWordSubtypes.length; i++) {
    final key = '\u0000$i';
    if (right.contains(multiWordSubtypes[i])) {
      right = right.replaceAll(multiWordSubtypes[i], key);
      placeholders[key] = multiWordSubtypes[i];
    }
  }

  List<String> words(String s) =>
      s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  return TypeLine(
    words(left),
    words(right).map((w) => placeholders[w] ?? w).toList(),
  );
}

/// Vorderseite einer mehrseitigen Karte, sonst die Karte selbst.
Map<String, dynamic> _frontFace(Map<String, dynamic> printing) {
  final faces = printing['card_faces'];
  if (faces is List && faces.isNotEmpty && faces.first is Map) {
    return (faces.first as Map).cast<String, dynamic>();
  }
  return printing;
}

/// Typzeile der Vorderseite.
String frontTypeLine(Map<String, dynamic> printing) {
  final line = printing['type_line'] as String? ?? '';
  if (line.contains('//')) {
    return _frontFace(printing)['type_line'] as String? ?? line;
  }
  return line;
}

/// Gedruckte Manakosten. Bei doppelseitigen Karten die der Vorderseite,
/// bei Split-Karten beide Hälften (`{1}{R} // {1}{U}`).
String manaCost(Map<String, dynamic> printing) {
  final top = printing['mana_cost'];
  if (top is String && top.isNotEmpty) return top;
  final faces = printing['card_faces'];
  if (faces is! List || faces.isEmpty) return top is String ? top : '';
  if (fullNameLayouts.contains(printing['layout'])) {
    return faces.map((f) => (f as Map)['mana_cost'] as String? ?? '').join(' // ');
  }
  return (faces.first as Map)['mana_cost'] as String? ?? '';
}

/// Name, unter dem die Karte geraten wird.
String gameName(Map<String, dynamic> printing) {
  final name = printing['name'] as String;
  if (!name.contains(' // ')) return name;
  if (fullNameLayouts.contains(printing['layout'])) return name;
  return _frontFace(printing)['name'] as String? ?? name.split(' // ').first;
}

/// Promo-Typen, deren Druckversionen nie zählen: Playtest-Karten (z. B. aus
/// Mystery Booster 2) liegen in normalen Sets, sind aber Spaßkarten.
const excludedPromoTypes = {'playtest'};

/// In keinem Format zugelassen (alle Formate `not_legal`) – das trifft
/// Un-artige Spaßkarten auch außerhalb der Un-Sets, z. B. Secret-Lair-Karten
/// mit Eichel-Stempel. Gebannte Karten sind `banned` und bleiben drin.
/// Fehlen die Angaben, gilt die Karte nicht als ausgeschlossen.
bool isNeverLegal(Map<String, dynamic> p) {
  final legalities = p['legalities'];
  if (legalities is! Map || legalities.isEmpty) return false;
  return legalities.values.every((v) => v == 'not_legal');
}

/// Zählt diese Druckversion überhaupt (Papier, keine Sonderkarte)?
bool isEligiblePrinting(Map<String, dynamic> p) {
  if (p['object'] != 'card') return false;
  if (p['oracle_id'] is! String) return false;
  if (p['digital'] == true) return false;
  if (p['oversized'] == true) return false;
  if (excludedLayouts.contains(p['layout'])) return false;
  if (excludedSetTypes.contains(p['set_type'])) return false;
  final promoTypes = p['promo_types'];
  if (promoTypes is List && promoTypes.any(excludedPromoTypes.contains)) return false;
  final types = parseTypeLine(frontTypeLine(p)).types;
  if (types.any(excludedTypes.contains)) return false;
  // Conspiracy-Karten sind nirgends zugelassen, sollen aber drinbleiben.
  if (isNeverLegal(p) && !types.contains('Conspiracy')) return false;
  return true;
}

/// Baut eine [GameCard] aus einer Druckversion.
GameCard toGameCard(Map<String, dynamic> p) {
  final typeLine = parseTypeLine(frontTypeLine(p));
  final colors = (p['color_identity'] as List? ?? const [])
      .cast<String>()
      .toList()
    ..sort();
  return GameCard(
    oracleId: p['oracle_id'] as String,
    name: gameName(p),
    manaValue: (p['cmc'] as num? ?? 0).toDouble(),
    manaCost: manaCost(p),
    types: typeLine.types,
    subtypes: typeLine.subtypes,
    colors: colors,
    rarity: p['rarity'] as String? ?? 'common',
    setCode: p['set'] as String,
    released: p['released_at'] as String,
    scryfallId: p['id'] as String,
  );
}

class _Candidate {
  _Candidate(this.card, this.secondary, this.promo);
  final GameCard card;
  final bool secondary;
  final bool promo;

  /// Kleiner = besserer Erstdruck: Haupt-Sets vor Promo-Sets,
  /// dann früheres Datum, dann Nicht-Promo vor Promo.
  int compareTo(_Candidate o) {
    if (secondary != o.secondary) return secondary ? 1 : -1;
    final byDate = card.released.compareTo(o.card.released);
    if (byDate != 0) return byDate;
    if (promo != o.promo) return promo ? 1 : -1;
    return card.setCode.compareTo(o.card.setCode);
  }
}

class _Origin {
  _Origin(this.released, this.setType);
  final String released;
  final String? setType;
}

/// Sammelt Druckversionen als Stream und behält pro `oracle_id` nur den
/// besten Erstdruck – so muss nie die ganze Bulk-Datei im Speicher liegen.
class FirstPrintingCollector {
  /// [releasedUntil] (`yyyy-mm-dd`): spätere Druckversionen – z. B.
  /// Vorschau-Karten noch nicht erschienener Sets – werden ignoriert.
  FirstPrintingCollector({this.releasedUntil});

  final String? releasedUntil;
  final _best = <String, _Candidate>{};
  final _origin = <String, _Origin>{};
  int seen = 0;
  int eligible = 0;

  void add(Map<String, dynamic> p) {
    seen++;
    final oracleId = p['oracle_id'];
    if (oracleId is! String || p['object'] != 'card') return;

    // Ursprung über alle Papier-Druckversionen merken, auch ausgeschlossene:
    // Karten, die zuerst in einem Un-Set erschienen, fliegen komplett raus.
    if (p['digital'] != true && p['released_at'] is String) {
      final released = p['released_at'] as String;
      final current = _origin[oracleId];
      if (current == null || released.compareTo(current.released) < 0) {
        _origin[oracleId] = _Origin(released, p['set_type'] as String?);
      }
    }

    if (!isEligiblePrinting(p)) return;
    final until = releasedUntil;
    if (until != null && (p['released_at'] as String).compareTo(until) > 0) {
      return;
    }
    eligible++;
    final candidate = _Candidate(
      toGameCard(p),
      secondarySetTypes.contains(p['set_type']),
      p['promo'] == true,
    );
    final current = _best[oracleId];
    if (current == null || candidate.compareTo(current) < 0) {
      _best[oracleId] = candidate;
    }
  }

  /// Alle Karten, sortiert nach Name (ohne Groß-/Kleinschreibung).
  List<GameCard> build() {
    final cards = <GameCard>[];
    _best.forEach((oracleId, candidate) {
      if (_origin[oracleId]?.setType == 'funny') return;
      if (candidate.secondary) return; // nur als Promo erschienen
      cards.add(candidate.card);
    });
    cards.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.oracleId.compareTo(b.oracleId);
    });
    return cards;
  }
}
