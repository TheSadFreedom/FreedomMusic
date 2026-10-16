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
