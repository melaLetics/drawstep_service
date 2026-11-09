import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:path/path.dart' as p;

/// Metadaten einer Scryfall-Bulk-Datei.
class BulkInfo {
  BulkInfo(this.downloadUri, this.updatedAt);
  final Uri downloadUri;
  final String updatedAt;
}

/// Set-Informationen aus `GET /sets`.
class SetInfo {
  SetInfo({
    required this.code,
    required this.name,
    required this.setType,
    required this.released,
    required this.iconUri,
  });

  final String code;
  final String name;
  final String setType;
  final String? released;
  final Uri? iconUri;
}

/// Kleiner Client für die Scryfall-API, der sich an deren Regeln hält:
/// eigener User-Agent, Accept-Header, Pause zwischen API-Aufrufen.
class ScryfallClient {
  ScryfallClient({this.apiDelay = const Duration(milliseconds: 100)})
      : _http = HttpClient()..userAgent = userAgent;

  static const userAgent =
      'DrawstepService/0.1 (+https://github.com/melaLetics/drawstep_service)';
  static final apiBase = Uri.parse('https://api.scryfall.com/');

  final HttpClient _http;
  final Duration apiDelay;
  DateTime _lastApiCall = DateTime.fromMillisecondsSinceEpoch(0);

  Future<HttpClientResponse> _get(Uri uri) async {
    if (uri.host == apiBase.host) {
      final wait = apiDelay - DateTime.now().difference(_lastApiCall);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      _lastApiCall = DateTime.now();
    }
    final request = await _http.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json;q=0.9,*/*;q=0.8');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return response;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _get(uri);
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Sucht die aktuelle Bulk-Datei `default_cards`.
  /// Bietet Scryfall eine JSONL-Variante an, wird diese bevorzugt.
  Future<BulkInfo> defaultCardsInfo() async {
    final json = await _getJson(apiBase.resolve('bulk-data'));
    final entries = (json['data'] as List).cast<Map<String, dynamic>>();
    final entry = entries.firstWhere(
      (e) => e['type'] == 'default_cards',
      orElse: () => throw StateError('Keine Bulk-Datei "default_cards" gefunden'),
    );
    final uri = (entry['jsonl_download_uri'] ?? entry['download_uri']) as String;
    return BulkInfo(Uri.parse(uri), entry['updated_at'] as String? ?? '');
  }

  /// Lädt eine Datei in den Cache-Ordner, falls sie dort noch nicht liegt.
  /// Der Dateiname enthält bei Scryfall einen Zeitstempel, damit ist der
  /// Cache automatisch pro Tagesstand.
  Future<File> downloadToCache(Uri uri, Directory cacheDir) async {
    await cacheDir.create(recursive: true);
    final target = File(p.join(cacheDir.path, uri.pathSegments.last));
    if (await target.exists() && await target.length() > 0) return target;

    final partial = File('${target.path}.part');
    final response = await _get(uri);
    final sink = partial.openWrite();
    await response.pipe(sink);
    await partial.rename(target.path);
    return target;
  }

  /// Alle Sets, inklusive Folgeseiten.
  Future<Map<String, SetInfo>> sets() async {
    final result = <String, SetInfo>{};
    Uri? next = apiBase.resolve('sets');
    while (next != null) {
      final json = await _getJson(next);
      for (final s in (json['data'] as List).cast<Map<String, dynamic>>()) {
        final icon = s['icon_svg_uri'] as String?;
        result[s['code'] as String] = SetInfo(
          code: s['code'] as String,
          name: s['name'] as String,
          setType: s['set_type'] as String? ?? '',
          released: s['released_at'] as String?,
          // Ohne Query-String (Cache-Buster von Scryfall).
          iconUri: icon == null ? null : Uri.parse(icon.split('?').first),
        );
      }
      next = json['has_more'] == true
          ? Uri.parse(json['next_page'] as String)
          : null;
    }
    return result;
  }

  /// Lädt eine einzelne Datei (z. B. ein Set-Symbol) als Bytes.
  Future<List<int>> getBytes(Uri uri) async {
    final response = await _get(uri);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void close() => _http.close(force: true);
}

/// Erkennt gzip an den ersten beiden Bytes (0x1f 0x8b) – unabhängig von der
/// Dateiendung, denn Scryfall liefert z. B. `.jsonl.gz`.
Future<bool> isGzipFile(File file) async {
  final raf = await file.open();
  try {
    final head = await raf.read(2);
    return head.length == 2 && head[0] == 0x1f && head[1] == 0x8b;
  } finally {
    await raf.close();
  }
}

/// Liest die Karten einer Bulk-Datei als Stream, ohne die ganze Datei
/// zu dekodieren. Scryfall schreibt jede Karte in eine eigene Zeile
/// (JSON-Array mit einer Karte pro Zeile oder JSONL); für den seltenen Fall
/// einer einzeiligen Datei gibt es einen Rückfall auf `jsonDecode`.
Stream<Map<String, dynamic>> readBulkCards(File file) async* {
  Stream<List<int>> bytes = file.openRead();
  if (await isGzipFile(file)) bytes = bytes.transform(gzip.decoder);
  final lines = bytes.transform(utf8.decoder).transform(const LineSplitter());
  await for (var line in lines) {
    line = line.trim();
    if (line.isEmpty || line == '[' || line == ']') continue;
    if (line.startsWith('[')) {
      // Ganze Datei in einer Zeile.
      for (final card in (jsonDecode(line) as List)) {
        yield (card as Map).cast<String, dynamic>();
      }
      continue;
    }
    if (line.endsWith(',')) line = line.substring(0, line.length - 1);
    yield jsonDecode(line) as Map<String, dynamic>;
  }
}
