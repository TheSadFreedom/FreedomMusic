/// Strip LRC timestamps like [00:12.00] for readable display.
String formatLyrics(String? raw) {
  if (raw == null) return '';
  final cleaned = raw
      .replaceAll(RegExp(r'\[\d{1,2}:\d{2}([.:]\d{1,3})?\]'), '')
      .replaceAll(RegExp(r'\r\n|\r'), '\n')
      .trim();
  // Collapse 3+ blank lines.
  return cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
}

bool hasLyrics(String? raw) => formatLyrics(raw).isNotEmpty;

/// One lyric row. [times] is empty for plain text.
class LyricLine {
  const LyricLine(this.text, [this.times = const []]);

  final String text;
  final List<Duration> times;

  bool get synced => times.isNotEmpty;
}

final _stamp = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
final _offsetTag = RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);
final _metaTag = RegExp(r'^\[[a-zA-Z]+:.*\]$');

Duration? _stampDuration(RegExpMatch match) {
  final minutes = int.tryParse(match.group(1)!);
  final seconds = int.tryParse(match.group(2)!);
  if (minutes == null || seconds == null) return null;
  final frac = match.group(3);
  var millis = 0;
  if (frac != null) {
    if (frac.length == 1) {
      millis = int.parse(frac) * 100;
    } else if (frac.length == 2) {
      millis = int.parse(frac) * 10;
    } else {
      millis = int.parse(frac.substring(0, 3));
    }
  }
  return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
}

/// Lines in display order. Synced lines keep every timestamp so the
/// highlight can return to a repeated chorus.
List<LyricLine> parseLyricLines(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final offsetMs = int.tryParse(_offsetTag.firstMatch(raw)?.group(1) ?? '') ?? 0;
  final offset = Duration(milliseconds: offsetMs);
  final rows = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final lines = <LyricLine>[];
  var anyTime = false;

  for (final row in rows) {
    final trimmed = row.trim();
    if (trimmed.isEmpty || _metaTag.hasMatch(trimmed)) continue;
    final stamps = _stamp.allMatches(trimmed).toList();
    final text = trimmed.replaceAll(_stamp, '').trim();
    if (text.isEmpty) continue;
    if (stamps.isEmpty) {
      lines.add(LyricLine(text));
      continue;
    }
    final times = <Duration>[];
    for (final stamp in stamps) {
      final at = _stampDuration(stamp);
      if (at == null) continue;
      final shifted = at + offset;
      times.add(shifted.isNegative ? Duration.zero : shifted);
    }
    if (times.isEmpty) {
      lines.add(LyricLine(text));
      continue;
    }
    times.sort();
    anyTime = true;
    lines.add(LyricLine(text, times));
  }

  if (!anyTime) return lines;
  lines.sort((a, b) {
    final at = a.times.isEmpty ? Duration.zero : a.times.first;
    final bt = b.times.isEmpty ? Duration.zero : b.times.first;
    return at.compareTo(bt);
  });
  return lines;
}

/// Index of the line being sung, or -1 when the text has no timestamps.
int lyricIndexAt(List<LyricLine> lines, Duration position) {
  var index = -1;
  Duration? best;
  for (var i = 0; i < lines.length; i++) {
    for (final time in lines[i].times) {
      if (time <= position && (best == null || time.compareTo(best) >= 0)) {
        best = time;
        index = i;
      }
    }
  }
  return index;
}
