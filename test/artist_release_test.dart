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
  int? trackTotal,
  String? coverPath,
}) {
  return Track(
    trackKey: key,
    title: title,
    artist: artist,
    album: album,
    genre: 'Unknown',
    albumArtist: albumArtist,
    trackNumber: number,
    trackTotal: trackTotal,
    coverPath: coverPath,
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
      trackTotal: 10,
    );
    final other = _track(
      key: 'o',
      title: 'Сжигая мосты',
      artist: '[AMATORY]',
      album: 'Огонь',
      albumArtist: '[AMATORY]',
      number: 2,
      trackTotal: 10,
    );
    final own = _track(
      key: 'a',
      title: 'Solo',
      artist: 'ATL',
      album: 'Свой',
      albumArtist: 'ATL',
      number: 1,
      trackTotal: 10,
    );
    final ownRest = _track(
      key: 'b',
      title: 'Solo 2',
      artist: 'ATL',
      album: 'Свой',
      albumArtist: 'ATL',
      number: 2,
      trackTotal: 10,
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
        trackTotal: 12,
      ),
      _track(
        key: '8',
        title: 'Девчонка',
        artist: 'aikko, katanacss, INSPACE, playingtheangel',
        album: 'Подвох',
        albumArtist: 'aikko, katanacss, INSPACE',
        number: 8,
        trackTotal: 12,
      ),
      _track(
        key: '9',
        title: 'Не работает',
        artist: 'aikko, katanacss, INSPACE',
        album: 'Подвох',
        albumArtist: 'Aikko',
        number: 9,
        trackTotal: 12,
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

  test('track total tag chooses single, EP, or album', () {
    expect(releaseKindFromTotal(1), ReleaseKind.single);
    expect(releaseKindFromTotal(3), ReleaseKind.single);
    expect(releaseKindFromTotal(4), ReleaseKind.ep);
    expect(releaseKindFromTotal(8), ReleaseKind.ep);
    expect(releaseKindFromTotal(9), ReleaseKind.album);
    expect(
      releaseKindForTracks([
        for (var i = 0; i < 10; i++)
          _track(
            key: 's$i',
            title: 'T$i',
            artist: 'a',
            album: 'Сингл',
            trackTotal: 2,
          ),
      ]),
      ReleaseKind.single,
    );
    expect(
      releaseKindForTracks([
        _track(
          key: 'e',
          title: 'T',
          artist: 'a',
          album: 'Мини',
          trackTotal: 5,
        ),
      ]),
      ReleaseKind.ep,
    );
  });

  test('chosen track cover is used when that track is in the release', () {
    final tracks = [
      _track(
        key: 'a',
        title: 'Первый',
        artist: 'A',
        album: 'Альбом',
        coverPath: 'a.jpg',
      ),
      _track(
        key: 'b',
        title: 'Второй',
        artist: 'A',
        album: 'Альбом',
        coverPath: 'b.jpg',
      ),
    ];
    expect(coverFromTracks(tracks), 'a.jpg');
    expect(coverFromTracks(tracks, preferredTrackKey: 'b'), 'b.jpg');
    expect(coverFromTracks(tracks, preferredTrackKey: 'gone'), 'a.jpg');
  });

  test('release cover key follows the album and its album artists', () {
    ArtistRelease release(String title, List<Track> tracks) {
      return ArtistRelease(
        title: title,
        tracks: tracks,
        kind: ReleaseKind.album,
      );
    }

    final first = _track(
      key: '1',
      title: 'Первый',
      artist: 'A',
      album: 'Огонь',
      albumArtist: 'B, A',
    );
    final second = _track(
      key: '2',
      title: 'Второй',
      artist: 'A',
      album: 'Огонь',
      albumArtist: 'A, B',
    );
    final other = _track(
      key: '3',
      title: 'Другой',
      artist: 'C',
      album: 'Огонь',
      albumArtist: 'C',
    );
    expect(
      releaseCoverKey(release('Огонь', [first, second])),
      releaseCoverKey(release('Огонь', [second, first])),
    );
    expect(
      releaseCoverKey(release('Огонь', [first])),
      isNot(releaseCoverKey(release('Огонь', [other]))),
    );
  });
}
