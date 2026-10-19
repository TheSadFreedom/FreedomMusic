import 'package:flutter_test/flutter_test.dart';

import 'package:freedom_music/data/track_key.dart';

void main() {
  test('same artist+title produces same track key', () {
    final a = buildTrackKey(
      artist: 'Artist',
      title: 'Song',
    );
    final b = buildTrackKey(
      artist: ' artist ',
      title: 'SONG',
    );
    expect(a, equals(b));
  });

  test('album and duration do not affect track key', () {
    final a = buildTrackKey(
      artist: 'Artist',
      title: 'Song',
    );
    final b = buildTrackKey(
      artist: 'Artist',
      title: 'Song',
    );
    expect(a, equals(b));
  });

  test('different title produces different track key', () {
    final a = buildTrackKey(
      artist: 'Artist',
      title: 'Song',
    );
    final b = buildTrackKey(
      artist: 'Artist',
      title: 'Other Song',
    );
    expect(a, isNot(equals(b)));
  });

  test('comma-separated artists split correctly', () {
    expect(
      splitArtists('Artist A, Artist B, Artist C'),
      ['Artist A', 'Artist B', 'Artist C'],
    );
    expect(splitArtists('  Solo  '), ['Solo']);
    expect(splitArtists(''), ['Unknown']);
  });

  test('note splits a track from the same artist and title', () {
    final plain = buildTrackKey(artist: 'Artist', title: 'Song');
    final live = buildTrackKey(
      artist: 'Artist',
      title: 'Song',
      note: 'Live',
    );
    final blank = buildTrackKey(
      artist: 'Artist',
      title: 'Song',
      note: '  ',
    );
    final again = buildTrackKey(
      artist: ' artist ',
      title: 'SONG',
      note: ' live ',
    );
    expect(live, isNot(equals(plain)));
    expect(blank, equals(plain));
    expect(again, equals(live));
  });

  test('artist order does not change track key', () {
    final a = buildTrackKey(
      artist: 'A, B',
      title: 'Song',
    );
    final b = buildTrackKey(
      artist: 'B, A',
      title: 'Song',
    );
    expect(a, equals(b));
  });
}
