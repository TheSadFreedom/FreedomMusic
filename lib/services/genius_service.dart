import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/track_key.dart';

/// Public Genius pages. No API token: search JSON, then the song HTML state.
class GeniusHit {
  const GeniusHit({
    this.album,
    this.albumArtist,
    this.year,
    this.genre,
    this.trackNumber,
    this.trackTotal,
    this.discNumber,
    this.producer,
    this.lyrics,
  });

  final String? album;
  final String? albumArtist;
  final int? year;
  final String? genre;
  final int? trackNumber;
  final int? trackTotal;
  final int? discNumber;
  final String? producer;
  final String? lyrics;

  bool get hasMeta =>
      (album != null && album!.isNotEmpty) ||
      (albumArtist != null && albumArtist!.isNotEmpty) ||
      year != null ||
      (genre != null && genre!.isNotEmpty) ||
      trackNumber != null ||
      (producer != null && producer!.isNotEmpty);
}

class GeniusService {
  GeniusService();

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  static final Map<String, GeniusHit?> _cache = {};

  Future<GeniusHit?> lookup({
    required String artist,
    required String title,
  }) async {
    final key = '${_norm(artist)}|${_norm(title)}';
    if (_cache.containsKey(key)) return _cache[key];
    final hit = await _fetch(artist, title);
    _cache[key] = hit;
    return hit;
  }

  Future<String?> lyrics({
    required String artist,
    required String title,
  }) async {
    final hit = await lookup(artist: artist, title: title);
    final text = hit?.lyrics?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  Future<GeniusHit?> _fetch(String artist, String title) async {
    final query = '${_primary(artist)} $title'.trim();
    if (query.isEmpty) return null;
    final search = await _get(
      Uri.https('genius.com', '/api/search/multi', {'q': query}),
      json: true,
    );
    if (search == null) return null;
    final url = _pickSongUrl(search, artist, title);
    if (url == null) return null;
    final html = await _get(Uri.parse(url), json: false);
    if (html == null) return null;
    return _parseSongPage(html);
  }

  String? _pickSongUrl(String body, String artist, String title) {
    try {
      final data = jsonDecode(body);
      if (data is! Map) return null;
      final response = data['response'];
      if (response is! Map) return null;
      final sections = response['sections'];
      if (sections is! List) return null;
      for (final section in sections) {
        if (section is! Map) continue;
        final type = section['type'];
        if (type != 'song' && type != 'top_hit') continue;
        final hits = section['hits'];
        if (hits is! List) continue;
        for (final hit in hits) {
          if (hit is! Map || hit['type'] != 'song') continue;
          final result = hit['result'];
          if (result is! Map) continue;
          final foundTitle = '${result['title'] ?? ''}';
          final artistMap = result['primary_artist'];
          final foundArtist =
              artistMap is Map ? '${artistMap['name'] ?? ''}' : '';
          if (!_titleClose(title, foundTitle)) continue;
          if (!_artistClose(artist, foundArtist)) continue;
          final url = '${result['url'] ?? ''}'.trim();
          if (url.startsWith('https://genius.com/')) return url;
        }
      }
    } catch (e) {
      debugPrint('Genius search parse: $e');
    }
    return null;
  }

  GeniusHit? _parseSongPage(String html) {
    final state = _preloadedState(html);
    if (state == null) return null;
    final songPage = state['songPage'];
    if (songPage is! Map) return null;
    final songId = songPage['song'];
    if (songId == null) return null;
    final entities = state['entities'];
    if (entities is! Map) return null;
    final songs = entities['songs'];
    if (songs is! Map) return null;
    final song = songs['$songId'];
    if (song is! Map) return null;

    final artists = entities['artists'];
    final albums = entities['albums'];
    final appearances = entities['albumAppearances'];
    final tags = entities['tags'];

    String? albumName;
    String? albumArtist;
    int? trackTotal;
    final albumId = song['album'];
    if (albums is Map && albumId != null) {
      final album = albums['$albumId'];
      if (album is Map) {
        final name = _withoutTranslation('${album['name'] ?? ''}');
        if (name.isNotEmpty) albumName = name;
        final tracklist = album['tracklist'];
        if (tracklist is List && tracklist.isNotEmpty) {
          trackTotal = tracklist.length;
        }
        albumArtist = _albumArtistName(album, artists);
      }
    }

    int? trackNumber;
    int? discNumber;
    if (appearances is Map) {
      final appearance = appearances['$songId'];
      if (appearance is Map) {
        trackNumber = _positive(appearance['discTrackNumber']) ??
            _positive(appearance['number']);
        discNumber = _positive(appearance['discNumber']);
      }
    }

    int? year;
    final parts = song['releaseDateComponents'];
    if (parts is Map) year = _positive(parts['year']);
    year ??= _yearFrom('${song['releaseDate'] ?? ''}');

    String? producer;
    final producerIds = song['producerArtists'];
    if (producerIds is List && artists is Map) {
      final names = <String>[];
      for (final id in producerIds) {
        final artist = artists['$id'];
        if (artist is! Map) continue;
        final name = _withoutTranslation('${artist['name'] ?? ''}');
        if (name.isNotEmpty) names.add(name);
      }
      if (names.isNotEmpty) producer = names.join(', ');
    }

    String? genre;
    final tagId = song['primaryTag'];
    if (tags is Map && tagId != null) {
      final tag = tags['$tagId'];
      if (tag is Map) {
        final name = _withoutTranslation('${tag['name'] ?? ''}');
        if (name.isNotEmpty) genre = name;
      }
    }

    final lyricsData = songPage['lyricsData'];
    String? lyrics;
    if (lyricsData is Map) {
      final body = lyricsData['body'];
      if (body is Map) {
        lyrics = _lyricsFromHtml('${body['html'] ?? ''}');
      }
    }

    if (albumName == null &&
        albumArtist == null &&
        year == null &&
        genre == null &&
        trackNumber == null &&
        producer == null &&
        lyrics == null) {
      return null;
    }
    return GeniusHit(
      album: albumName,
      albumArtist: albumArtist,
      year: year,
      genre: genre,
      trackNumber: trackNumber,
      trackTotal: trackTotal,
      discNumber: discNumber,
      producer: producer,
      lyrics: lyrics,
    );
  }

  String? _albumArtistName(Map album, Object? artists) {
    final ids = <dynamic>[];
    final primary = album['primaryArtists'];
    if (primary is List && primary.isNotEmpty) {
      ids.addAll(primary);
    } else if (album['artist'] != null) {
      ids.add(album['artist']);
    }
    final names = <String>[];
    if (artists is Map) {
      for (final id in ids) {
        final artist = artists['$id'];
        if (artist is! Map) continue;
        final name = _withoutTranslation('${artist['name'] ?? ''}');
        if (name.isNotEmpty) names.add(name);
      }
    }
    if (names.isNotEmpty) return names.join(', ');
    final fallback = _withoutTranslation('${album['primaryArtistNames'] ?? ''}');
    return fallback.isEmpty ? null : fallback;
  }

  Map<String, dynamic>? _preloadedState(String html) {
    const marker = "__PRELOADED_STATE__ = JSON.parse('";
    final start = html.indexOf(marker);
    if (start < 0) return null;
    final raw = StringBuffer();
    for (var i = start + marker.length; i < html.length; i++) {
      final char = html[i];
      if (char == '\\' && i + 1 < html.length) {
        raw.write(char);
        raw.write(html[i + 1]);
        i++;
        continue;
      }
      if (char == "'") break;
      raw.write(char);
    }
    try {
      final decoded = jsonDecode(_unescapeJs(raw.toString()));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      debugPrint('Genius page parse: $e');
    }
    return null;
  }

  String _unescapeJs(String value) {
    final out = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char != '\\' || i + 1 >= value.length) {
        out.write(char);
        continue;
      }
      final next = value[++i];
      switch (next) {
        case 'n':
          out.write('\n');
        case 'r':
          out.write('\r');
        case 't':
          out.write('\t');
        case '"' || "'" || '\\' || '/':
          out.write(next);
        case 'u':
          if (i + 4 < value.length) {
            final hex = value.substring(i + 1, i + 5);
            final code = int.tryParse(hex, radix: 16);
            if (code != null) {
              out.writeCharCode(code);
              i += 4;
              break;
            }
          }
          out.write(next);
        default:
          out.write(next);
      }
    }
    return out.toString();
  }

  String? _lyricsFromHtml(String html) {
    if (html.trim().isEmpty) return null;
    var text = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('\u2026', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = text.split('\n').map((line) => line.trim()).toList();
    if (lines.isNotEmpty &&
        lines.first.toLowerCase().startsWith('[текст песни')) {
      lines.removeAt(0);
    }
    final cleaned = lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<String?> _get(Uri uri, {required bool json}) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.set(
        HttpHeaders.acceptHeader,
        json ? 'application/json' : 'text/html',
      );
      req.headers.set(HttpHeaders.refererHeader, 'https://genius.com/');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      return await res.transform(utf8.decoder).join();
    } catch (e) {
      debugPrint('Genius ${uri.path}: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Genius appends a Latin translation: «так неинтересно (so not interesting)».
  static String _withoutTranslation(String value) {
    final cleaned = value.replaceAllMapped(RegExp(r'\s*\(([^)]*)\)'), (match) {
      final inner = (match.group(1) ?? '').trim();
      if (!_isParenTranslation(value, inner)) return match.group(0)!;
      return '';
    });
    return cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  static bool _isParenTranslation(String whole, String inner) {
    if (inner.isEmpty || _hasCyrillic(inner) || !_hasLatin(inner)) return false;
    if (_isQualifier(inner)) return false;
    final without = whole.replaceFirst('($inner)', '');
    return _hasCyrillic(without);
  }

  static bool _isQualifier(String inner) {
    final text = inner.toLowerCase().trim();
    if (RegExp(r'^(feat\.?|ft\.?|featuring|prod\.?|produced by|with)\b')
        .hasMatch(text)) {
      return true;
    }
    const words = {
      'remix',
      'rmx',
      'live',
      'acoustic',
      'deluxe',
      'remaster',
      'remastered',
      'instrumental',
      'demo',
      'bonus',
      'edit',
      'version',
      'mix',
      'original',
      'cover',
      'single',
      'ep',
      'explicit',
      'clean',
      'intro',
      'outro',
      'interlude',
      'skit',
      'extended',
      'radio',
      'club',
      'dub',
      'vip',
      'bootleg',
      'reprise',
      'session',
      'edition',
      'mono',
      'stereo',
      'slowed',
      'reverb',
      'sped',
      'nightcore',
      'chopped',
      'screwed',
      'karaoke',
      'ost',
    };
    final parts = text
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .split(' ')
        .where((word) => word.isNotEmpty && !RegExp(r'^\d+$').hasMatch(word));
    if (parts.isEmpty) return false;
    return parts.every(words.contains);
  }

  static bool _hasCyrillic(String value) =>
      RegExp(r'[А-Яа-яЁё]').hasMatch(value);

  static bool _hasLatin(String value) => RegExp(r'[A-Za-z]').hasMatch(value);

  String _primary(String artist) {
    final parts = splitArtists(artist);
    return parts.isEmpty ? artist.trim() : parts.first;
  }

  String _norm(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _titleClose(String wanted, String found) {
    final a = _norm(wanted);
    final b = _norm(found);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    if (a.length >= 4 && (b.contains(a) || a.contains(b))) return true;
    final paren = RegExp(r'\(([^)]+)\)').allMatches(found);
    for (final match in paren) {
      final inner = _norm(match.group(1) ?? '');
      if (inner.isNotEmpty && (inner == a || inner.contains(a) || a.contains(inner))) {
        return true;
      }
    }
    return false;
  }

  bool _artistClose(String wanted, String found) {
    final a = _norm(_primary(wanted));
    final b = _norm(found);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b || a.contains(b) || b.contains(a)) return true;
    final compactA = a.replaceAll(RegExp(r'\W'), '');
    final compactB = b.replaceAll(RegExp(r'\W'), '');
    return compactA.length >= 4 &&
        (compactA.contains(compactB) || compactB.contains(compactA));
  }

  int? _positive(Object? value) {
    if (value is int) return value > 0 ? value : null;
    if (value is num) {
      final n = value.toInt();
      return n > 0 ? n : null;
    }
    return null;
  }

  int? _yearFrom(String raw) {
    final match = RegExp(r'(19|20)\d{2}').firstMatch(raw);
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }
}
