import 'package:test/test.dart';
import 'package:drawstep_service/drawstep_service.dart';

Map<String, dynamic> de({
  String oracleId = 'o1',
  String? printedName = 'Blitzschlag',
  String released = '2000-01-01',
  String layout = 'normal',
  String lang = 'de',
  bool digital = false,
  List<Map<String, dynamic>>? faces,
}) =>
    {
      'object': 'card',
      'oracle_id': oracleId,
      'lang': lang,
      'layout': layout,
      'released_at': released,
      'digital': digital,
      if (printedName != null) 'printed_name': printedName,
      if (faces != null) 'card_faces': faces,
    };

GameCard game(String oracleId, String name) => GameCard(
      oracleId: oracleId,
      name: name,
      manaValue: 1,
      types: const ['Instant'],
      subtypes: const [],
      colors: const ['R'],
      rarity: 'common',
      setCode: 'lea',
      released: '1993-08-05',
      scryfallId: 'sf',
    );

void main() {
  group('printedGameName', () {
    test('einfache Karte', () {
      expect(printedGameName(de()), 'Blitzschlag');
    });

    test('Split-Karte mit beiden Hälften', () {
      expect(
        printedGameName(de(layout: 'split', printedName: null, faces: [
          {'printed_name': 'Feuer'},
          {'printed_name': 'Eis'},
        ])),
        'Feuer // Eis',
      );
    });

    test('doppelseitige Karte: nur die Vorderseite', () {
      expect(
        printedGameName(de(layout: 'transform', printedName: null, faces: [
          {'printed_name': 'Delver der Geheimnisse'},
          {'printed_name': 'Insektoider Schrecken'},
        ])),
        'Delver der Geheimnisse',
      );
      expect(printedGameName(de(layout: 'transform', printedName: 'Vorne // Hinten')), 'Vorne');
    });

    test('ohne gedruckten Namen', () {
      expect(printedGameName(de(printedName: null)), isNull);
    });
  });

  group('LocalizedNameCollector', () {
    test('nimmt nur deutsche Papier-Drucke und den neuesten Namen', () {
      final c = LocalizedNameCollector()
        ..add(de(printedName: 'Blitzstrahl', released: '1994-01-01'))
        ..add(de(printedName: 'Blitzschlag', released: '2010-07-16'))
        ..add(de(printedName: 'Digital', released: '2020-01-01', digital: true))
        ..add(de(printedName: 'Foudre', released: '2021-01-01', lang: 'fr'));
      expect(c.nameFor('o1'), 'Blitzschlag');
    });

    test('Vorfilter erkennt deutsche Zeilen', () {
      final c = LocalizedNameCollector();
      expect(c.mightMatch('{"object":"card","lang":"de","name":"x"}'), isTrue);
      expect(c.mightMatch('{"object":"card","lang":"en","name":"x"}'), isFalse);
    });

    test('ergänzt nur abweichende deutsche Namen', () {
      final c = LocalizedNameCollector()
        ..add(de(oracleId: 'bolt', printedName: 'Blitzschlag'))
        ..add(de(oracleId: 'ring', printedName: 'Sol Ring'));
      final cards = c.apply([game('bolt', 'Lightning Bolt'), game('ring', 'Sol Ring'), game('x', 'Unbekannt')]);
      expect([for (final g in cards) g.nameDe], ['Blitzschlag', null, null]);
      expect(cards.first.toJson()['nd'], 'Blitzschlag');
      expect(cards[1].toJson().containsKey('nd'), isFalse);
    });
  });
}
