import 'artist_release.dart';
import 'playlist.dart';
import 'track.dart';

class SearchPerson {
  const SearchPerson({required this.name, required this.trackCount});

  final String name;
  final int trackCount;
}

class SearchAlbum {
  const SearchAlbum({required this.release, required this.artist});

  final ArtistRelease release;
  final String artist;
}

class CatalogSearch {
  const CatalogSearch({
    required this.tracks,
    required this.artists,
    required this.producers,
    required this.albums,
    required this.playlists,
  });

  static const empty = CatalogSearch(
    tracks: [],
    artists: [],
    producers: [],
    albums: [],
    playlists: [],
  );

  final List<Track> tracks;
  final List<SearchPerson> artists;
  final List<SearchPerson> producers;
  final List<SearchAlbum> albums;
  final List<Playlist> playlists;

  bool get isEmpty =>
      tracks.isEmpty &&
      artists.isEmpty &&
      producers.isEmpty &&
      albums.isEmpty &&
      playlists.isEmpty;
}
