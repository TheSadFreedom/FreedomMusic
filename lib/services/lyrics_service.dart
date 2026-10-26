import 'dart:convert';
import 'dart:io';

import '../models/track.dart';
import '../utils/lyrics_format.dart';
import 'genius_service.dart';

/// Fetch lyrics from [LRCLIB](https://lrclib.net), then Genius.
class LyricsService {
  LyricsService({GeniusService? genius}) : _genius = genius ?? GeniusService();

  final GeniusService _genius;

  static const _ua =
      'FreedomMusic/1.0 (https://github.com/TheSadFreedom/FreedomMusic)';

  HttpClient? _client;

  HttpClient get _http => _client ??= HttpClient()..userAgent = _ua;

  void close() {
    _client?.close(force: true);
    _client = null;
  }

  /// Returns synced LRC text when available, otherwise plain lyrics.
  Future<String?> fetchForTrack(Track track) async {
    final title = track.displayTitle.trim();
    final artist = track.displayArtist.trim();
    if (title.isEmpty ||
        title.toLowerCase() == 'unknown' ||
        artist.isEmpty ||
        artist.toLowerCase() == 'unknown') {
      return null;
    }

    final album = track.displayAlbum;
    final albumName =
        album.toLowerCase() == 'unknown' ? null : album.trim();
    final durationSec = track.durationMs == null
        ? null
        : (track.durationMs! / 1000).round().clamp(1, 3600);
    final note = track.displayNote;

    if (note != null) {
      final withNote = await _fetchOnce(
        artist: artist,
        title: title,
        note: note,
        albumName: albumName,
        durationSec: durationSec,
      );
      if (hasLyrics(withNote)) return withNote;
    }
    return _fetchOnce(
      artist: artist,
      title: title,
      albumName: albumName,
      durationSec: durationSec,
    );
  }

  /// [note] set: «Artist - Title Note». Otherwise: «Artist - Title».
  /// Order: LRCLIB get → LRCLIB search → Genius.
  Future<String?> _fetchOnce({
    required String artist,
    required String title,
    String? note,
    String? albumName,
    int? durationSec,
  }) async {
    final trackName = note == null ? title : '$title $note';
    final fromGet = await _getBySignature(
      trackName: trackName,
      artistName: artist,
      albumName: albumName,
      durationSec: durationSec,
      requiredNote: note,
    );
    if (fromGet != null) return fromGet;

    // Duration mismatches (±2s) often fail `/api/get` — fall back to search.
    final fromSearch = await _searchBest(
      trackName: trackName,
      artistName: artist,
      albumName: albumName,
      durationSec: durationSec,
      requiredNote: note,
    );
    if (hasLyrics(fromSearch)) return fromSearch;

    return _genius.lyrics(
      artist: artist,
      title: title,
      note: note,
      phrase: true,
    );
  }

  Future<String?> _getBySignature({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSec,
    String? requiredNote,
  }) async {
    final query = <String, String>{
      'track_name': trackName,
      'artist_name': artistName,
      if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
      if (durationSec != null) 'duration': '$durationSec',
    };
    final data = await _getJson(Uri.https('lrclib.net', '/api/get', query));
    if (data == null) return null;
    if (requiredNote != null &&
        !_hasNote('${data['trackName'] ?? data['name'] ?? ''}', requiredNote)) {
      return null;
    }
    return _lyricsFromRecord(data);
  }

  Future<String?> _searchBest({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSec,
    String? requiredNote,
  }) async {
    final data = await _getJsonList(
      Uri.https('lrclib.net', '/api/search', {
        'track_name': trackName,
        'artist_name': artistName,
        if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
      }),
    );
    if (data == null || data.isEmpty) return null;

    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      if (requiredNote != null) {
        final foundTitle = '${map['trackName'] ?? map['name'] ?? ''}';
        if (!_hasNote(foundTitle, requiredNote)) continue;
      }
      final score = _matchScore(
        map,
        trackName: trackName,
        artistName: artistName,
        albumName: albumName,
        durationSec: durationSec,
      );
      if (score > bestScore) {
        bestScore = score;
        best = map;
      }
    }
    if (best == null || bestScore < 2) return null;
    return _lyricsFromRecord(best);
  }

  int _matchScore(
    Map<String, dynamic> map, {
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSec,
  }) {
    var score = 0;
    final foundTitle = '${map['trackName'] ?? map['name'] ?? ''}';
    final foundArtist = '${map['artistName'] ?? ''}';
    final foundAlbum = '${map['albumName'] ?? ''}';
    if (_close(trackName, foundTitle)) score += 3;
    if (_close(artistName, foundArtist)) score += 3;
    if (albumName != null &&
        albumName.isNotEmpty &&
        _close(albumName, foundAlbum)) {
      score += 1;
    }
    final foundDur = map['duration'];
    if (durationSec != null && foundDur is num) {
      final diff = (foundDur.round() - durationSec).abs();
      if (diff <= 2) {
        score += 2;
      } else if (diff <= 5) {
        score += 1;
      } else if (diff > 15) {
        score -= 2;
      }
    }
    if (map['instrumental'] == true) score -= 1;
    return score;
  }

  String? _lyricsFromRecord(Map<String, dynamic> map) {
    if (map['instrumental'] == true) return null;
    final synced = '${map['syncedLyrics'] ?? ''}'.trim();
    if (hasLyrics(synced)) return synced;
    final plain = '${map['plainLyrics'] ?? ''}'.trim();
    if (hasLyrics(plain)) return plain;
    return null;
  }

  bool _hasNote(String found, String note) {
    final label = _norm(note);
    if (label.isEmpty) return true;
    return _norm(found).contains(label);
  }

  bool _close(String a, String b) {
    final na = _norm(a);
    final nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  String _norm(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final req = await _http.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) {
        await res.drain<void>();
        return null;
      }
      if (res.statusCode == 429 || res.statusCode == 503) {
        final retry = int.tryParse(res.headers.value('retry-after') ?? '') ?? 1;
        await res.drain<void>();
        await Future<void>.delayed(Duration(seconds: retry.clamp(1, 10)));
        return null;
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>?> _getJsonList(Uri uri) async {
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
      final decoded = jsonDecode(body);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
