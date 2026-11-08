import 'package:test/test.dart';
import 'package:topdecked_service/topdecked_service.dart';

/// Minimale Scryfall-Druckversion für Tests.
Map<String, dynamic> printing({
  String oracleId = 'o1',
  String name = 'Lightning Bolt',
  String set = 'lea',
  String setType = 'core',
  String released = '1993-08-05',
  String typeLine = 'Instant',
  String layout = 'normal',
  num cmc = 1,
  List<String> colors = const ['R'],
  String rarity = 'common',
  bool digital = false,
  bool promo = false,
  bool oversized = false,
  List<Map<String, dynamic>>? faces,
  String id = 'id-1',
}) =>
    {
      'object': 'card',
      'id': id,
      'oracle_id': oracleId,
      'name': name,
      'set': set,
      'set_type': setType,
      'released_at': released,
      'type_line': typeLine,
      'layout': layout,
      'cmc': cmc,
      'color_identity': colors,
      'rarity': rarity,
      'digital': digital,
      'promo': promo,
      'oversized': oversized,
      if (faces != null) 'card_faces': faces,
    };

void main() {
  group('parseTypeLine', () {
    test('trennt Typen und Untertypen am Gedankenstrich', () {
      final t = parseTypeLine('Legendary Creature — Elf Druid');
      expect(t.types, ['Legendary', 'Creature']);
      expect(t.subtypes, ['Elf', 'Druid']);
    });

    test('ohne Untertypen', () {
      final t = parseTypeLine('Instant');
      expect(t.types, ['Instant']);
      expect(t.subtypes, isEmpty);
    });

    test('Untertypen aus mehreren Wörtern bleiben zusammen', () {
      final t = parseTypeLine('Legendary Creature — Time Lord Doctor');
      expect(t.subtypes, ['Time Lord', 'Doctor']);
    });
  });

  group('gameName und frontTypeLine', () {
    test('doppelseitige Karte: Name und Typ der Vorderseite', () {
      final p = printing(
        name: 'Delver of Secrets // Insectile Aberration',
        layout: 'transform',
        typeLine: 'Creature — Human Wizard // Creature — Human Insect',
        faces: [
          {'name': 'Delver of Secrets', 'type_line': 'Creature — Human Wizard'},
          {'name': 'Insectile Aberration', 'type_line': 'Creature — Human Insect'},
        ],
      );
      expect(gameName(p), 'Delver of Secrets');
      expect(parseTypeLine(frontTypeLine(p)).subtypes, ['Human', 'Wizard']);
    });

    test('Split-Karte behält den vollen Namen', () {
      final p = printing(
        name: 'Fire // Ice',
        layout: 'split',
        typeLine: 'Instant // Instant',
        faces: [
          {'name': 'Fire', 'type_line': 'Instant'},
          {'name': 'Ice', 'type_line': 'Instant'},
        ],
      );
      expect(gameName(p), 'Fire // Ice');
      expect(parseTypeLine(frontTypeLine(p)).types, ['Instant']);
    });
  });

  group('isEligiblePrinting', () {
    test('normale Papierkarte zählt', () {
      expect(isEligiblePrinting(printing()), isTrue);
    });

    test('Arena-Druckversion zählt nicht', () {
      expect(isEligiblePrinting(printing(digital: true)), isFalse);
    });

    test('Archenemy-Scheme zählt nicht', () {
      expect(
        isEligiblePrinting(printing(layout: 'scheme', typeLine: 'Ongoing Scheme')),
        isFalse,
      );
    });

    test('Plane und Phenomenon zählen nicht', () {
      expect(isEligiblePrinting(printing(layout: 'planar', typeLine: 'Plane — Dominaria')), isFalse);
      expect(isEligiblePrinting(printing(layout: 'planar', typeLine: 'Phenomenon')), isFalse);
    });

    test('Un-Set zählt nicht', () {
      expect(isEligiblePrinting(printing(setType: 'funny')), isFalse);
    });

    test('Conspiracy-Karten bleiben', () {
      expect(isEligiblePrinting(printing(typeLine: 'Conspiracy', set: 'cns', setType: 'draft_innovation')), isTrue);
    });

    test('Token-, Sticker- und Rollen-Karten zählen nicht', () {
      expect(isEligiblePrinting(printing(typeLine: 'Token Enchantment — Aura Role')), isFalse);
      expect(isEligiblePrinting(printing(typeLine: 'Stickers')), isFalse);
    });

    test('Token und Übergrößen zählen nicht', () {
      expect(isEligiblePrinting(printing(layout: 'token', typeLine: 'Token Creature — Goblin')), isFalse);
      expect(isEligiblePrinting(printing(oversized: true)), isFalse);
    });
  });

  group('FirstPrintingCollector', () {
    test('nimmt die früheste Papier-Druckversion', () {
      final c = FirstPrintingCollector()
        ..add(printing(set: 'm10', released: '2009-07-17', id: 'b'))
        ..add(printing(set: 'lea', released: '1993-08-05', id: 'a'))
        ..add(printing(set: 'pmei', released: '1990-01-01', digital: true, id: 'x'));
      final cards = c.build();
      expect(cards, hasLength(1));
      expect(cards.single.setCode, 'lea');
      expect(cards.single.scryfallId, 'a');
    });

    test('Promo-Sets zählen nie als Erstdruck', () {
      final early = FirstPrintingCollector()
        ..add(printing(set: 'pmei', setType: 'promo', released: '2019-01-01', promo: true))
        ..add(printing(set: 'war', setType: 'expansion', released: '2019-05-03'));
      expect(early.build().single.setCode, 'war');
    });

    test('Karten, die es nur als Promo gibt (z. B. Convention-Karten), fliegen raus', () {
      final c = FirstPrintingCollector()
        ..add(printing(oracleId: 'maro', name: 'Convention Maro', set: 'pf24', setType: 'promo', released: '2024-01-01'))
        ..add(printing(oracleId: 'ok', name: 'Shock'));
      expect(c.build().map((card) => card.oracleId), ['ok']);
    });

    test('Vorschau-Promo zählt nicht, solange das Set noch nicht erschienen ist', () {
      final c = FirstPrintingCollector(releasedUntil: '2026-11-08')
        ..add(printing(oracleId: 'borg', name: 'Borg Queen', set: 'purl', setType: 'promo', released: '2026-10-01'))
        ..add(printing(oracleId: 'borg', name: 'Borg Queen', set: 'trk', setType: 'expansion', released: '2026-11-13'));
      expect(c.build(), isEmpty);
    });

    test('Karten mit Ursprung im Un-Set fliegen komplett raus', () {
      final c = FirstPrintingCollector()
        ..add(printing(oracleId: 'un', set: 'unf', setType: 'funny', released: '2022-10-07'))
        ..add(printing(oracleId: 'un', set: 'sld', setType: 'box', released: '2023-01-01'))
        ..add(printing(oracleId: 'ok', name: 'Shock'));
      expect(c.build().map((card) => card.oracleId), ['ok']);
    });

    test('ignoriert noch nicht erschienene Druckversionen', () {
      final c = FirstPrintingCollector(releasedUntil: '2026-11-07')
        ..add(printing(oracleId: 'neu', name: 'Spoiler', released: '2027-04-09'))
        ..add(printing(oracleId: 'alt', name: 'Old', released: '2026-11-07'));
      expect(c.build().map((card) => card.oracleId), ['alt']);
    });

    test('sortiert nach Name ohne Groß-/Kleinschreibung', () {
      final c = FirstPrintingCollector()
        ..add(printing(oracleId: 'b', name: 'zap'))
        ..add(printing(oracleId: 'a', name: 'Anger'));
      expect(c.build().map((card) => card.name), ['Anger', 'zap']);
    });
  });

  group('manaCost', () {
    test('normale Karte', () {
      expect(manaCost({...printing(), 'mana_cost': '{1}{B}{B}'}), '{1}{B}{B}');
    });

    test('doppelseitige Karte: Vorderseite', () {
      final p = printing(layout: 'transform', faces: [
        {'name': 'Front', 'mana_cost': '{U}', 'type_line': 'Creature'},
        {'name': 'Back', 'mana_cost': '', 'type_line': 'Creature'},
      ]);
      expect(manaCost({...p, 'mana_cost': null}), '{U}');
    });

    test('Split-Karte: beide Hälften', () {
      final p = printing(layout: 'split', faces: [
        {'name': 'Fire', 'mana_cost': '{1}{R}', 'type_line': 'Instant'},
        {'name': 'Ice', 'mana_cost': '{1}{U}', 'type_line': 'Instant'},
      ]);
      expect(manaCost(p), '{1}{R} // {1}{U}');
    });

    test('Land ohne Kosten', () {
      expect(manaCost({...printing(typeLine: 'Land'), 'mana_cost': ''}), '');
    });

    test('landet im JSON als mc', () {
      expect(toGameCard({...printing(), 'mana_cost': '{R}'}).toJson()['mc'], '{R}');
    });
  });

  test('GameCard.toJson schreibt ganze Manawerte als int', () {
    final card = toGameCard(printing(cmc: 3.0));
    expect(card.toJson()['mv'], 3);
    expect(toGameCard(printing(cmc: 0.5)).toJson()['mv'], 0.5);
  });
}
