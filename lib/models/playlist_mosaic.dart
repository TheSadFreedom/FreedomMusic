import 'dart:math';

/// Up to four distinct track covers, in a stable random order.
List<String> pickPlaylistMosaic(Iterable<String?> covers, {required int seed}) {
  final unique = <String>[];
  final seen = <String>{};
  for (final path in covers) {
    if (path == null || path.isEmpty || !seen.add(path)) continue;
    unique.add(path);
  }
  if (unique.length > 1) unique.shuffle(Random(seed));
  if (unique.length <= 4) return unique;
  return unique.sublist(0, 4);
}
