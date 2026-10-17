import 'package:flutter_test/flutter_test.dart';
import 'package:freedom_music/models/artist_release.dart';
import 'package:freedom_music/models/track.dart';

Track _track({
  required String key,
  required String title,
  required String artist,
  required String album,
  String? albumArtist,
  int? number,
}) {
  return Track(
    trackKey: key,
    title: title,
    artist: artist,
    album: album,
    genre: 'Unknown',
    albumArtist: albumArtist,
    trackNumber: number,
  );
}

void main() {
  test('guest album is listed in full and not as the artist album', () {
    final guest = _track(
      key: 'g',
      title: 'Монстр',
      artist: '[AMATORY], ATL',
      album: 'Огонь',
      albumArtist: '[AMATORY]',
      number: 1,
    );
    final other = _track(
      key: 'o',
      title: 'Сжигая мосты',
      artist: '[AMATORY]',
      album: 'Огонь',
      albumArtist: '[AMATORY]',
      number: 2,
    );
    final own = _track(
      key: 'a',
      title: 'Solo',
      artist: 'ATL',
      album: 'Свой',
      albumArtist: 'ATL',
      number: 1,
    );
    final ownRest = _track(
      key: 'b',
      title: 'Solo 2',
      artist: 'ATL',
      album: 'Свой',
      albumArtist: 'ATL',
      number: 2,
    );

    final groups = groupArtistReleases(
      artistTracks: [guest, own],
      libraryTracks: [guest, other, own, ownRest],
      isThisArtist: (name) => name.toLowerCase() == 'atl',
      cardName: (name) => name,
    );

    expect(groups.albums.map((r) => r.title), ['Свой']);
    expect(groups.albums.single.tracks.map((t) => t.trackKey), ['a', 'b']);
    expect(groups.appearances.map((r) => r.title), ['Огонь']);
    expect(groups.appearances.single.credit, '[AMATORY]');
    expect(groups.appearances.single.tracks.map((t) => t.trackKey), ['g', 'o']);
    expect(groups.singles, isEmpty);
  });

  test('everyone in the album artist tag owns the release', () {
    final tracks = [
      _track(
        key: '1',
        title: 'Меньше пить',
        artist: 'aikko, katanacss, INSPACE',
        album: 'Подвох',
        albumArtist: 'aikko, katanacss, INSPACE',
        number: 1,
      ),
      _track(
        key: '8',
        title: 'Девчонка',
        artist: 'aikko, katanacss, INSPACE, playingtheangel',
        album: 'Подвох',
        albumArtist: 'aikko, katanacss, INSPACE',
        number: 8,
      ),
      _track(
        key: '9',
        title: 'Не работает',
        artist: 'aikko, katanacss, INSPACE',
        album: 'Подвох',
        albumArtist: 'Aikko',
        number: 9,
      ),
    ];

    ArtistReleaseGroups groupsFor(String name) {
      return groupArtistReleases(
        artistTracks: tracks.where((t) => t.artists.any(
          (artist) => artist.toLowerCase() == name,
        )).toList(),
        libraryTracks: tracks,
        isThisArtist: (artist) => artist.toLowerCase() == name,
        cardName: (artist) => artist,
      );
    }

    final aikko = groupsFor('aikko');
    expect(aikko.albums.single.title, 'Подвох');
    expect(aikko.albums.single.tracks, hasLength(3));
    expect(aikko.appearances, isEmpty);

    final guest = groupsFor('playingtheangel');
    expect(guest.albums, isEmpty);
    expect(guest.singles, isEmpty);
    expect(guest.appearances.single.credit, 'aikko, katanacss, INSPACE');
    expect(guest.appearances.single.tracks.map((t) => t.trackKey), ['1', '8', '9']);

    final partner = groupsFor('katanacss');
    expect(partner.appearances, isEmpty);
    expect(partner.albums.single.tracks, hasLength(3));
  });

  test('without an album artist, guests still see the full release', () {
    final tracks = [
      _track(key: '1', title: 'A', artist: 'aikko', album: 'бэкрумс', number: 1),
      _track(
        key: '2',
        title: 'B',
        artist: 'aikko, гость',
        album: 'бэкрумс',
        number: 2,
      ),
      _track(key: '3', title: 'C', artist: 'aikko', album: 'бэкрумс', number: 3),
    ];
    final guest = groupArtistReleases(
      artistTracks: [tracks[1]],
      libraryTracks: tracks,
      isThisArtist: (name) => name.toLowerCase() == 'гость',
      cardName: (name) => name,
    );
    expect(guest.albums, isEmpty);
    expect(guest.appearances.single.tracks, hasLength(3));
    expect(guest.appearances.single.credit, 'aikko');
  });

  test('album card lists every album artist, including a shorter tag', () {
    final release = ArtistRelease(
      title: 'Подвох',
      kind: ReleaseKind.album,
      tracks: [
        _track(
          key: '1',
          title: 'A',
          artist: 'aikko',
          album: 'Подвох',
          albumArtist: 'aikko, katanacss, INSPACE',
          number: 1,
        ),
        _track(
          key: '9',
          title: 'B',
          artist: 'Aikko',
          album: 'Подвох',
          albumArtist: 'Aikko',
          number: 9,
        ),
      ],
    );
    expect(
      releaseAlbumArtists(release),
      ['aikko', 'katanacss', 'INSPACE'],
    );
  });
}
