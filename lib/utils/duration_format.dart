String formatTrackDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '—';
  final totalSec = durationMs ~/ 1000;
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
