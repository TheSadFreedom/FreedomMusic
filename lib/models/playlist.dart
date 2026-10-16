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
