/// Eine Karte, wie die Drawstep-App sie kennt: Daten des Erstdrucks,
/// reduziert auf die Felder, die das Spiel vergleicht.
class GameCard {
  const GameCard({
    required this.oracleId,
    required this.name,
    required this.manaValue,
    this.manaCost = '',
    required this.types,
    required this.subtypes,
    required this.colors,
    required this.rarity,
    required this.setCode,
    required this.released,
    required this.scryfallId,
  });

  /// Stabile Scryfall-`oracle_id`, gleich über alle Druckversionen.
  final String oracleId;
  final String name;

  /// Manawert (`cmc`). Kann bei Sonderfällen ein Bruch sein.
  final double manaValue;

  /// Gedruckte Manakosten der Vorderseite, z. B. `{1}{B}{B}`; leer bei
  /// Karten ohne Kosten (Länder). Split-Karten: `{1}{R} // {1}{U}`.
  final String manaCost;

  /// Super- und Kartentypen, z. B. `[Legendary, Creature]`.
  final List<String> types;

  /// Untertypen, z. B. `[Elf, Druid]`.
  final List<String> subtypes;

  /// Farbidentität, z. B. `[G, W]`.
  final List<String> colors;
  final String rarity;

  /// Set-Code des Erstdrucks, z. B. `lea`.
  final String setCode;

  /// Erscheinungsdatum des Erstdrucks als `yyyy-mm-dd`.
  final String released;

  /// Scryfall-ID der Druckversion; daraus baut die App die Bild-URL.
  final String scryfallId;

  /// Kompaktes JSON mit kurzen Schlüsseln für das Datenpaket.
  Map<String, Object> toJson() => {
        'i': oracleId,
        'n': name,
        'mv': manaValue == manaValue.roundToDouble()
            ? manaValue.toInt()
            : manaValue,
        'mc': manaCost,
        't': types,
        'st': subtypes,
        'c': colors,
        'r': rarity,
        's': setCode,
        'd': released,
        'sf': scryfallId,
      };
}
