import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../data/track_key.dart';

class ArtistPhotoProgress {
  const ArtistPhotoProgress({
    required this.done,
    required this.total,
    this.updated = 0,
    this.current,
  });

  final int done;
  final int total;
  final int updated;
  final String? current;

  double get ratio => total == 0 ? 0 : done / total;
}

/// Resolves artist portraits without API keys:
/// Yandex Music → Genius → Deezer.
class ArtistPhotoService {
  static const _ua = 'FreedomMusic/1.0 (local music player; artist photos)';
  static const _uaBrowser =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  HttpClient? _client;

  HttpClient get _http {
    return _client ??= HttpClient()..userAgent = _ua;
  }

  void close() {
    _client?.close(force: true);
    _client = null;
  }

  /// Download portrait bytes for [artistName], or null if not found.
  Future<Uint8List?> fetchPhotoBytes(String artistName) async {
    final name = artistName.trim();
    if (name.isEmpty || name.toLowerCase() == 'unknown') return null;

    final lookups = <Future<String?> Function(String)>[
      _yandexMusicImageUrl,
      _geniusImageUrl,
      _deezerImageUrl,
    ];
    for (final lookup in lookups) {
      final url = await lookup(name);
      if (url == null || url.isEmpty) continue;
      final bytes = await _download(url);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }
    return null;
  }

  /// Unofficial Yandex Music search — cover.uri uses `%%` size placeholder.
  Future<String?> _yandexMusicImageUrl(String artist) async {
    final data = await _getJson(
      Uri.https('api.music.yandex.net', '/search', {
        'text': artist,
        'type': 'artist',
        'page': '0',
        'nocorrect': 'false',
      }),
      delay: const Duration(milliseconds: 250),
      userAgent: _uaBrowser,
    );
    final result = data?['result'];
    if (result is! Map) return null;
    final artists = result['artists'];
    if (artists is! Map) return null;
    final list = artists['results'];
    if (list is! List || list.isEmpty) return null;

    for (final raw in list) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final found = '${map['name'] ?? ''}';
      if (!_artistClose(artist, found)) continue;
      final cover = map['cover'];
      if (cover is! Map) continue;
      var uri = '${cover['uri'] ?? ''}'.trim();
      if (uri.isEmpty) continue;
      if (uri.startsWith('//')) uri = 'https:$uri';
      if (!uri.startsWith('http')) uri = 'https://$uri';
      return uri.replaceAll('%%', '400x400');
    }
    return null;
  }

  Future<String?> _geniusImageUrl(String artist) async {
    final data = await _getJson(
      Uri.https('genius.com', '/api/search/multi', {
        'q': artist,
        'per_page': '5',
      }),
      delay: const Duration(milliseconds: 200),
    );
    final sections = data?['response'];
    if (sections is! Map) return null;
    final list = sections['sections'];
    if (list is! List) return null;

    String? fromArtistSection;
    String? fromSongPrimary;

    for (final raw in list) {
      if (raw is! Map) continue;
      final section = Map<String, dynamic>.from(raw);
      final type = '${section['type'] ?? ''}';
      final hits = section['hits'];
      if (hits is! List) continue;

      for (final hitRaw in hits) {
        if (hitRaw is! Map) continue;
        final hit = Map<String, dynamic>.from(hitRaw);
        final result = hit['result'];
        if (result is! Map) continue;
        final map = Map<String, dynamic>.from(result);

        if (type == 'artist' || type == 'top_hit') {
          final found = '${map['name'] ?? ''}';
          final image = '${map['image_url'] ?? ''}';
          if (image.isNotEmpty && _artistClose(artist, found)) {
            if (type == 'artist') return image;
            fromArtistSection ??= image;
          }
        }

        if (type == 'song' || type == 'top_hit') {
          final primary = map['primary_artist'];
          if (primary is Map) {
            final found = '${primary['name'] ?? ''}';
            final image = '${primary['image_url'] ?? ''}';
            if (image.isNotEmpty && _artistClose(artist, found)) {
              fromSongPrimary ??= image;
            }
          }
        }
      }
    }

    return fromArtistSection ?? fromSongPrimary;
  }

  Future<String?> _deezerImageUrl(String artist) async {
    final data = await _getJson(
      Uri.https('api.deezer.com', '/search/artist', {
        'q': artist,
        'limit': '8',
      }),
      delay: const Duration(milliseconds: 200),
    );
    final list = data?['data'];
    if (list is! List || list.isEmpty) return null;

    for (final raw in list) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final found = '${map['name'] ?? ''}';
      if (!_artistClose(artist, found)) continue;
      for (final key in [
        'picture_xl',
        'picture_big',
        'picture_medium',
        'picture',
      ]) {
        final url = '${map[key] ?? ''}';
        if (url.isNotEmpty && !url.contains('artist-default')) return url;
      }
    }
    return null;
  }

  Future<Uint8List?> _download(String url) async {
    try {
      final uri = Uri.parse(url);
      final req = await _http.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      final res = await req.close().timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
        if (builder.length > 8 << 20) {
          await res.drain<void>();
          return null;
        }
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getJson(
    Uri uri, {
    Duration delay = const Duration(milliseconds: 250),
    String? userAgent,
  }) async {
    await Future<void>.delayed(delay);
    try {
      final req = await _http.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, userAgent ?? _ua);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String _norm(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _artistClose(String wanted, String found) {
    final nw = _norm(splitArtists(wanted).isEmpty
        ? wanted
        : splitArtists(wanted).first);
    final nf = _norm(found);
    if (nw.isEmpty || nf.isEmpty) return false;
    if (nw == nf || nw.contains(nf) || nf.contains(nw)) return true;
    final wa = nw.replaceAll(RegExp(r'\W'), '');
    final fa = nf.replaceAll(RegExp(r'\W'), '');
    return wa.length >= 3 && (wa.contains(fa) || fa.contains(wa));
  }
}
