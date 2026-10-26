/// Ten-band graphic EQ like Yandex Music, plus a preamp «уровень».
class EqualizerState {
  const EqualizerState({
    required this.enabled,
    required this.level,
    required this.bands,
    required this.presetId,
  });

  static const bandCount = 10;
  static const frequencies = <int>[
    60,
    170,
    310,
    600,
    1000,
    3000,
    6000,
    12000,
    14000,
    16000,
  ];
  static const bandLabels = <String>[
    '60',
    '170',
    '310',
    '600',
    '1k',
    '3k',
    '6k',
    '12k',
    '14k',
    '16k',
  ];
  static const minDb = -12.0;
  static const maxDb = 12.0;

  final bool enabled;
  final double level;
  final List<double> bands;
  final String presetId;

  static EqualizerState flat({bool enabled = false}) => EqualizerState(
        enabled: enabled,
        level: 0,
        bands: List<double>.filled(bandCount, 0),
        presetId: EqualizerPresets.normal.id,
      );

  EqualizerState copyWith({
    bool? enabled,
    double? level,
    List<double>? bands,
    String? presetId,
  }) {
    return EqualizerState(
      enabled: enabled ?? this.enabled,
      level: level ?? this.level,
      bands: bands ?? List<double>.from(this.bands),
      presetId: presetId ?? this.presetId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EqualizerState) return false;
    if (enabled != other.enabled ||
        level != other.level ||
        presetId != other.presetId ||
        bands.length != other.bands.length) {
      return false;
    }
    for (var i = 0; i < bands.length; i++) {
      if (bands[i] != other.bands[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(enabled, level, presetId, Object.hashAll(bands));

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'level': level,
        'bands': bands,
        'presetId': presetId,
      };

  factory EqualizerState.fromJson(Map<String, Object?> json) {
    final rawBands = json['bands'];
    final bands = List<double>.filled(bandCount, 0);
    if (rawBands is List) {
      for (var i = 0; i < bandCount && i < rawBands.length; i++) {
        final v = rawBands[i];
        if (v is num) bands[i] = v.toDouble().clamp(minDb, maxDb);
      }
    }
    final level = (json['level'] is num)
        ? (json['level'] as num).toDouble().clamp(minDb, maxDb)
        : 0.0;
    final presetId = '${json['presetId'] ?? EqualizerPresets.normal.id}';
    return EqualizerState(
      enabled: json['enabled'] == true,
      level: level,
      bands: bands,
      presetId: presetId,
    );
  }

  /// mpv / FFmpeg audio filter chain, or empty when disabled.
  String toAudioFilter() {
    if (!enabled) return '';
    final parts = <String>[];
    if (level.abs() >= 0.05) {
      parts.add('volume=${level.toStringAsFixed(2)}dB');
    }
    for (var i = 0; i < bandCount; i++) {
      final g = bands[i];
      if (g.abs() < 0.05) continue;
      parts.add(
        'equalizer=f=${frequencies[i]}:g=${g.toStringAsFixed(2)}',
      );
    }
    return parts.join(',');
  }
}

class EqualizerPreset {
  const EqualizerPreset({required this.id, required this.name, required this.bands});

  final String id;
  final String name;
  final List<double> bands;
}

/// Built-in curves from Yandex Music screenshots.
abstract final class EqualizerPresets {
  static const customId = 'custom';
  static const customName = 'Своя настройка';

  static const normal = EqualizerPreset(
    id: 'normal',
    name: 'По умолчанию',
    bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  );

  static const all = <EqualizerPreset>[
    normal,
    EqualizerPreset(
      id: 'classical',
      name: 'Классическая музыка',
      bands: [0, 0, 0, 0, 0, 0, -3, -3, -3, -5],
    ),
    EqualizerPreset(
      id: 'club',
      name: 'Клубная музыка',
      bands: [0, 0, 4, 2, 2, 2, 1, 0, 0, 0],
    ),
    EqualizerPreset(
      id: 'dance',
      name: 'Танцевальная музыка',
      bands: [4, 3, 1, 0, 0, -2, -4, -4, 1, 1],
    ),
    EqualizerPreset(
      id: 'bass',
      name: 'Усиление НЧ',
      bands: [3, 4, 4, 2, 0, -2, -4, -5, -6, -6],
    ),
    EqualizerPreset(
      id: 'bass_treble',
      name: 'Усиление НЧ и ВЧ',
      bands: [3, 2, -1, -3, -2, 1, 4, 5, 6, 6],
    ),
    EqualizerPreset(
      id: 'treble',
      name: 'Усиление ВЧ',
      bands: [-3, -3, -3, -1, 1, 5, 8, 8, 8, 8],
    ),
    EqualizerPreset(
      id: 'laptop',
      name: 'Колонки ноутбука',
      bands: [2, 5, 2, -2, -1, 1, 2, 4, 5, 6],
    ),
    EqualizerPreset(
      id: 'hall',
      name: 'Большой зал',
      bands: [4, 4, 2, 2, -1, -3, -3, -3, -1, -1],
    ),
    EqualizerPreset(
      id: 'concert',
      name: 'Концерт',
      bands: [-3, -1, 2, 3, 4, 4, 3, 2, 2, 2],
    ),
    EqualizerPreset(
      id: 'party',
      name: 'Вечеринка',
      bands: [3, 3, -1, -1, -1, -1, -1, -1, 3, 3],
    ),
    EqualizerPreset(
      id: 'pop',
      name: 'Поп',
      bands: [-1, 2, 4, 5, 3, -1, -2, -2, -1, 0],
    ),
    EqualizerPreset(
      id: 'reggae',
      name: 'Регги',
      bands: [0, 0, 0, -3, 0, 3, 3, 0, 0, 0],
    ),
    EqualizerPreset(
      id: 'rock',
      name: 'Рок',
      bands: [4, 2, -2, -4, -2, 2, 4, 6, 6, 6],
    ),
    EqualizerPreset(
      id: 'ska',
      name: 'Ска',
      bands: [-1, -2, -2, -1, 1, 2, 3, 4, 5, 4],
    ),
    EqualizerPreset(
      id: 'soft',
      name: 'Мягкое звучание',
      bands: [1, 0, -1, -2, 0, 2, 4, 5, 6, 6],
    ),
    EqualizerPreset(
      id: 'soft_rock',
      name: 'Софт-рок',
      bands: [2, 3, 1, -1, -3, -4, -2, 0, 2, 5],
    ),
    EqualizerPreset(
      id: 'techno',
      name: 'Техно',
      bands: [4, 2, -2, -4, -3, -2, 4, 5, 5, 4],
    ),
  ];

  static EqualizerPreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  static String displayName(String presetId) {
    if (presetId == customId) return customName;
    return byId(presetId)?.name ?? customName;
  }

  static String matchPresetId(List<double> bands, double level) {
    if (level.abs() >= 0.05) return customId;
    for (final preset in all) {
      var same = true;
      for (var i = 0; i < EqualizerState.bandCount; i++) {
        if ((bands[i] - preset.bands[i]).abs() >= 0.05) {
          same = false;
          break;
        }
      }
      if (same) return preset.id;
    }
    return customId;
  }
}
