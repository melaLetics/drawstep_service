import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:topdecked_service/topdecked_service.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('topdecked_bulk_'));
  tearDown(() => dir.deleteSync(recursive: true));

  const cards = [
    {'object': 'card', 'name': 'Lightning Bolt'},
    {'object': 'card', 'name': 'Fire // Ice'},
  ];

  Future<List<String>> names(File f) async =>
      [await for (final c in readBulkCards(f)) c['name'] as String];

  test('liest gzip-komprimiertes JSONL (.jsonl.gz)', () async {
    final f = File(p.join(dir.path, 'cards.jsonl.gz'))
      ..writeAsBytesSync(gzip.encode(utf8.encode(cards.map(jsonEncode).join('\n'))));
    expect(await isGzipFile(f), isTrue);
    expect(await names(f), ['Lightning Bolt', 'Fire // Ice']);
  });

  test('liest JSON-Array mit einer Karte pro Zeile', () async {
    final f = File(p.join(dir.path, 'cards.json'))
      ..writeAsStringSync('[\n${cards.map(jsonEncode).join(',\n')}\n]\n');
    expect(await isGzipFile(f), isFalse);
    expect(await names(f), ['Lightning Bolt', 'Fire // Ice']);
  });

  test('liest einzeiliges JSON-Array', () async {
    final f = File(p.join(dir.path, 'one.json'))..writeAsStringSync(jsonEncode(cards));
    expect(await names(f), ['Lightning Bolt', 'Fire // Ice']);
  });
}
