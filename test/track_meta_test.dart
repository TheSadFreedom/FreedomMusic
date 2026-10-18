import 'package:flutter_test/flutter_test.dart';
import 'package:freedom_music/data/track_meta.dart';
import 'package:freedom_music/models/track.dart';

Track _track({
  String title = 'Song',
  String artist = 'Artist',
  String album = 'Album',
  String genre = 'Hip-Hop',
  String? albumArtist = 'Artist',
  String? producer = 'Producer',
  String? lyrics = 'Текст песни',
  int? year = 2024,
  int? trackNumber = 1,
  int? trackTotal = 1,
  int? discNumber = 1,
  String? coverPath = 'cover.jpg',
}) {
  return Track(
    trackKey: 'key',
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    albumArtist: albumArtist,
    producer: producer,
    lyrics: lyrics,
    year: year,
    trackNumber: trackNumber,
    trackTotal: trackTotal,
    discNumber: discNumber,
    coverPath: coverPath,
  );
}

void main() {
  test('a complete track is ready', () {
    final gaps = trackMetaGaps(_track());
    expect(gaps.ready, isTrue);
    expect(gaps.core, isFalse);
    expect(gaps.producer, isFalse);
    expect(gaps.genre, isFalse);
    expect(gaps.lyrics, isFalse);
  });

  test('missing core fields stay out of the ready list', () {
    expect(trackMetaGaps(_track(coverPath: null)).core, isTrue);
    expect(trackMetaGaps(_track(title: 'Unknown')).core, isTrue);
    expect(trackMetaGaps(_track(artist: '')).core, isTrue);
    expect(trackMetaGaps(_track(album: 'Unknown')).core, isTrue);
    expect(trackMetaGaps(_track(albumArtist: null)).core, isTrue);
    expect(trackMetaGaps(_track(year: null)).core, isTrue);
    expect(trackMetaGaps(_track(trackNumber: null)).core, isTrue);
    expect(trackMetaGaps(_track(trackTotal: null)).core, isTrue);
    expect(trackMetaGaps(_track(discNumber: null)).core, isTrue);
    expect(trackMetaGaps(_track(coverPath: '')).ready, isFalse);
  });

  test('producer, genre, and lyrics have their own lists', () {
    final producer = trackMetaGaps(_track(producer: null));
    expect(producer.producer, isTrue);
    expect(producer.core, isFalse);
    expect(producer.ready, isFalse);

    final genre = trackMetaGaps(_track(genre: 'Unknown'));
    expect(genre.genre, isTrue);
    expect(genre.core, isFalse);
    expect(genre.ready, isTrue);

    final lyrics = trackMetaGaps(_track(lyrics: '   '));
    expect(lyrics.lyrics, isTrue);
    expect(lyrics.ready, isFalse);
  });

  test('several gaps can be open at once', () {
    final gaps = trackMetaGaps(
      _track(album: '', producer: '', genre: '', lyrics: null),
    );
    expect(gaps.core, isTrue);
    expect(gaps.producer, isTrue);
    expect(gaps.genre, isTrue);
    expect(gaps.lyrics, isTrue);
    expect(gaps.ready, isFalse);
  });
}
