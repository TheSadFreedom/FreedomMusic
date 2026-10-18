class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.updatedAt,
    this.description,
    this.coverPath,
    this.trackCount = 0,
    this.systemKind,
  });

  static const kindTrash = 'trash';
  static const kindNew = 'new';
  static const kindIncomplete = 'incomplete';
  static const kindNoProducer = 'no_producer';
  static const kindMissingGenre = 'missing_genre';
  static const kindMissingLyrics = 'missing_lyrics';
  static const kindMetadataReady = 'metadata_ready';

  static const missingMetadataName = 'Нехватает метаданных';
  static const missingProducerName = 'Нехватает Prod.';
  static const missingGenreName = 'Нехватает жанра';
  static const missingLyricsName = 'Нехватает текста';
  static const metadataReadyName = 'Метаданные готовы';

  static const missingMetadataDescription =
      'Нет обложки, названия, артиста, альбома, артиста альбома, года, номера, числа треков или диска.';
  static const missingProducerDescription = 'Нет продюсера.';
  static const missingGenreDescription = 'Нет жанра.';
  static const missingLyricsDescription = 'Нет текста.';
  static const metadataReadyDescription =
      'Обложка, название, артист, альбом, артист альбома, продюсер, год, номер, число треков, диск и текст заполнены. Жанр не обязателен.';

  /// How long a freshly scanned track stays in «Новинки».
  static const newTrackDays = 7;

  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? description;
  final String? coverPath;
  final int trackCount;
  /// Non-null for built-in playlists (e.g. [kindTrash], [kindNew]).
  final String? systemKind;

  bool get isTrash => systemKind == kindTrash;
  bool get isNew => systemKind == kindNew;
  bool get isIncomplete => systemKind == kindIncomplete;
  bool get isNoProducer => systemKind == kindNoProducer;
  bool get isMissingGenre => systemKind == kindMissingGenre;
  bool get isMissingLyrics => systemKind == kindMissingLyrics;
  bool get isMetadataReady => systemKind == kindMetadataReady;
  bool get isMetaCatalog =>
      isIncomplete ||
      isNoProducer ||
      isMissingGenre ||
      isMissingLyrics ||
      isMetadataReady;
  bool get isSystem => systemKind != null;

  DateTime get lastTouched => updatedAt ?? createdAt;

  Playlist copyWith({
    String? name,
    DateTime? updatedAt,
    String? description,
    String? coverPath,
    int? trackCount,
    String? systemKind,
    bool clearDescription = false,
    bool clearCover = false,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      description: clearDescription ? null : (description ?? this.description),
      coverPath: clearCover ? null : (coverPath ?? this.coverPath),
      trackCount: trackCount ?? this.trackCount,
      systemKind: systemKind ?? this.systemKind,
    );
  }
}
