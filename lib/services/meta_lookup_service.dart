import 'dart:convert';
import 'dart:io';

import '../data/track_key.dart';
import 'genius_service.dart';

/// Looks up album / year / genre / track numbers online (iTunes, then Deezer).
class OnlineMetaHit {
  const OnlineMetaHit({
    this.album,
    this.albumArtist,
    this.year,
    this.genre,
    this.trackNumber,
    this.trackTotal,
    this.discNumber,
    this.producer,
    this.lyrics,
    this.source = '',
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
  final String source;
}

class MetaLookupService {
  MetaLookupService({GeniusService? genius}) : _genius = genius ?? GeniusService();

  final GeniusService _genius;

  static const _ua = 'FreedomMusic/1.0 (local; metadata autofill)';

  HttpClient? _client;

  HttpClient get _http {
    return _client ??= HttpClient()..userAgent = _ua;
  }

  void close() {
    _client?.close(force: true);
    _client = null;
  }

  /// True while album, album artist, year, track number, or track total
  /// is still missing. Producer is filled when found, but its absence
  /// does not keep the track in «Без метаданных».
  static bool needsFill({
    required String album,
    String? albumArtist,
    int? year,
    int? trackNumber,
    int? trackTotal,
  }) {
    return _albumMissing(album) ||
        albumArtistMissing(albumArtist) ||
        _yearMissing(year) ||
        trackNumber == null ||
        trackNumber < 1 ||
        trackTotal == null ||
        trackTotal < 1;
  }

  /// Names of the fields [needsFill] still treats as empty.
  static List<String> missingFieldNames({
    required String album,
    String? albumArtist,
    int? year,
    int? trackNumber,
    int? trackTotal,
  }) {
    return [
      if (_albumMissing(album)) 'альбом',
      if (albumArtistMissing(albumArtist)) 'артист альбома',
      if (_yearMissing(year)) 'год',
      if (trackNumber == null || trackNumber < 1) 'номер',
      if (trackTotal == null || trackTotal < 1) 'число треков',
    ];
  }

  static bool albumArtistMissing(String? albumArtist) {
    final a = albumArtist?.trim().toLowerCase() ?? '';
    return a.isEmpty || a == 'unknown';
  }

  static bool _albumMissing(String album) {
    final a = album.trim().toLowerCase();
    return a.isEmpty ||
        a == 'unknown' ||
        a == 'мне нравится' ||
        a == 'мне нужен ui';
  }

  static bool _yearMissing(int? year) => year == null || year < 1000;

  static String cleanAlbum(String name) {
    var s = name.trim();
    s = s.replaceAll(
      RegExp(r'\s*[-–—]\s*(single|ep|maxi[\s-]?single|album)\s*$',
          caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(r'\s*\((single|ep)\)\s*$', caseSensitive: false),
      '',
    );
    return s.trim().replaceAll(RegExp(r'^[\s\-–—]+|[\s\-–—]+$'), '');
  }

  Future<OnlineMetaHit?> lookup({
    required String artist,
    required String title,
  }) async {
    final a = artist.trim();
    final t = title.trim();
    if (a.isEmpty || t.isEmpty || a.toLowerCase() == 'unknown') return null;

    final genius = await _fromGenius(a, t);
    if (genius != null) return genius;
    final itunes = await _itunes(a, t);
    if (itunes != null) return itunes;
    return _deezer(a, t);
  }

  Future<OnlineMetaHit?> _fromGenius(String artist, String title) async {
    final hit = await _genius.lookup(artist: artist, title: title);
    if (hit == null) return null;
    final lyrics = hit.lyrics?.trim();
    final album = hit.album?.trim();
    if (album == null || album.isEmpty) {
      // No album block on the song page: this is a single.
      return OnlineMetaHit(
        album: title.trim(),
        albumArtist: artist.trim(),
        year: hit.year,
        genre: hit.genre,
        trackNumber: 1,
        trackTotal: 1,
        discNumber: 1,
        producer: hit.producer,
        lyrics: lyrics,
        source: 'genius',
      );
    }
    if (!hit.hasMeta && (lyrics == null || lyrics.isEmpty)) return null;
    return OnlineMetaHit(
      album: hit.album,
      albumArtist: hit.albumArtist,
      year: hit.year,
      genre: hit.genre,
      trackNumber: hit.trackNumber,
      trackTotal: hit.trackTotal,
      discNumber: hit.discNumber,
      producer: hit.producer,
      lyrics: hit.lyrics,
      source: 'genius',
    );
  }

  String _primaryArtist(String artist) {
    final parts = splitArtists(artist);
    return parts.isEmpty ? artist.trim() : parts.first;
  }

  String _norm(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _titleClose(String a, String b) {
    final na = _norm(a);
    final nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    if (na.length >= 8 && (na.contains(nb) || nb.contains(na))) return true;
    return false;
  }

  bool _artistClose(String wanted, String found) {
    final nw = _norm(_primaryArtist(wanted));
    final nf = _norm(found);
    if (nw.isEmpty || nf.isEmpty) return false;
    if (nw == nf || nw.contains(nf) || nf.contains(nw)) return true;
    final wa = nw.replaceAll(RegExp(r'\W'), '');
    final fa = nf.replaceAll(RegExp(r'\W'), '');
    return wa.length >= 4 && (wa.contains(fa) || fa.contains(wa));
  }

  Future<Map<String, dynamic>?> _getJson(
    Uri uri, {
    Duration delay = const Duration(milliseconds: 350),
  }) async {
    await Future<void>.delayed(delay);
    try {
      final req = await _http.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
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

  Future<OnlineMetaHit?> _itunes(String artist, String title) async {
    final term = '${_primaryArtist(artist)} $title';
    for (final country in ['ru', 'us']) {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': term,
        'media': 'music',
        'entity': 'song',
        'limit': '12',
        'country': country,
      });
      final data = await _getJson(uri);
      final results = data?['results'];
      if (results is! List || results.isEmpty) continue;

      for (final raw in results) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final trackName = '${map['trackName'] ?? ''}';
        final artistName = '${map['artistName'] ?? ''}';
        if (!_titleClose(title, trackName)) continue;
        if (!_artistClose(artist, artistName)) continue;

        final album = cleanAlbum('${map['collectionName'] ?? ''}');
        final date = '${map['releaseDate'] ?? ''}';
        final yearMatch = RegExp(r'(19|20)\d{2}').firstMatch(date);
        final year = yearMatch != null ? int.tryParse(yearMatch.group(0)!) : null;
        final genre = '${map['primaryGenreName'] ?? ''}'.trim();
        final trackNumber = _asPositiveInt(map['trackNumber']);
        final trackTotal = _asPositiveInt(map['trackCount']);
        final discNumber = _asPositiveInt(map['discNumber']);
        if (album.isEmpty &&
            year == null &&
            genre.isEmpty &&
            trackNumber == null) {
          continue;
        }
        return OnlineMetaHit(
          album: album.isEmpty ? null : album,
          albumArtist: _cleanName('${map['collectionArtistName'] ?? ''}'),
          year: year,
          genre: genre.isEmpty ? null : genre,
          trackNumber: trackNumber,
          trackTotal: trackTotal,
          discNumber: discNumber,
          source: 'itunes',
        );
      }
    }
    return null;
  }

  static String? _cleanName(String raw) {
    final name = raw.trim();
    if (name.isEmpty || name.toLowerCase() == 'unknown') return null;
    return name;
  }

  int? _asPositiveInt(Object? v) {
    if (v is int) return v > 0 ? v : null;
    if (v is num) {
      final i = v.toInt();
      return i > 0 ? i : null;
    }
    if (v is String) {
      final i = int.tryParse(v.trim());
      if (i != null && i > 0) return i;
    }
    return null;
  }

  Future<OnlineMetaHit?> _deezer(String artist, String title) async {
    final q = 'artist:"${_primaryArtist(artist)}" track:"$title"';
    final searchUri = Uri.https('api.deezer.com', '/search', {
      'q': q,
      'limit': '10',
    });
    var data = await _getJson(searchUri);
    var list = data?['data'];
    if (list is! List || list.isEmpty) {
      final q2 = '${_primaryArtist(artist)} $title';
      data = await _getJson(
        Uri.https('api.deezer.com', '/search', {'q': q2, 'limit': '10'}),
      );
      list = data?['data'];
    }
    if (list is! List || list.isEmpty) return null;

    for (final raw in list) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final trackTitle = '${map['title'] ?? ''}';
      final art = map['artist'];
      final artName = art is Map ? '${art['name'] ?? ''}' : '';
      if (!_titleClose(title, trackTitle)) continue;
      if (!_artistClose(artist, artName)) continue;

      var album = '';
      final alb = map['album'];
      if (alb is Map) album = cleanAlbum('${alb['title'] ?? ''}');

      String? albumArtist;
      int? year;
      String? genre;
      int? trackNumber = _asPositiveInt(map['track_position']);
      int? trackTotal = _asPositiveInt(map['track_total'] ?? map['nb_tracks']);
      int? discNumber = _asPositiveInt(map['disk_number']);
      final id = map['id'];
      if (id != null) {
        final detail = await _getJson(Uri.https('api.deezer.com', '/track/$id'));
        if (detail != null) {
          final rd = '${detail['release_date'] ?? ''}';
          final ym = RegExp(r'(19|20)\d{2}').firstMatch(rd);
          if (ym != null) year = int.tryParse(ym.group(0)!);
          trackNumber ??= _asPositiveInt(detail['track_position']);
          discNumber ??= _asPositiveInt(detail['disk_number']);
          final dalb = detail['album'];
          final albId = dalb is Map ? dalb['id'] : null;
          if (albId != null) {
            final albumJson =
                await _getJson(Uri.https('api.deezer.com', '/album/$albId'));
            if (albumJson != null) {
              if (album.isEmpty) {
                album = cleanAlbum('${albumJson['title'] ?? ''}');
              }
              if (year == null) {
                final ard = '${albumJson['release_date'] ?? ''}';
                final aym = RegExp(r'(19|20)\d{2}').firstMatch(ard);
                if (aym != null) year = int.tryParse(aym.group(0)!);
              }
              trackTotal ??= _asPositiveInt(albumJson['nb_tracks']);
              final albumArt = albumJson['artist'];
              if (albumArt is Map) {
                albumArtist ??= _cleanName('${albumArt['name'] ?? ''}');
              }
              final genres = albumJson['genres'];
              if (genres is Map && genres['data'] is List) {
                final gList = genres['data'] as List;
                if (gList.isNotEmpty && gList.first is Map) {
                  genre = '${(gList.first as Map)['name'] ?? ''}'.trim();
                  if (genre.isEmpty) genre = null;
                }
              }
            }
          }
        }
      }

      if (album.isEmpty &&
          year == null &&
          genre == null &&
          trackNumber == null) {
        continue;
      }
      return OnlineMetaHit(
        album: album.isEmpty ? null : album,
        albumArtist: albumArtist,
        year: year,
        genre: genre,
        trackNumber: trackNumber,
        trackTotal: trackTotal,
        discNumber: discNumber,
        source: 'deezer',
      );
    }
    return null;
  }
}
