import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// One cover when every image is the same.
/// Four cells when there are two or more different images; missing slots
/// repeat the ones that exist.
List<String> pickPlaylistMosaic(
  Iterable<String?> covers, {
  required int seed,
  String? Function(String path)? identity,
}) {
  final paths = <String>[];
  final seenPath = <String>{};
  for (final path in covers) {
    if (path == null || path.isEmpty || !seenPath.add(path)) continue;
    paths.add(path);
  }
  if (paths.isEmpty) return const [];
  if (paths.length > 1) paths.shuffle(Random(seed));

  final chosen = <String>[];
  final seenId = <String>{};
  for (final path in paths) {
    final id = identity == null ? path : identity(path);
    if (id == null || id.isEmpty || !seenId.add(id)) continue;
    chosen.add(path);
    if (chosen.length == 4) break;
  }
  if (chosen.length <= 1) return chosen;
  return [for (var i = 0; i < 4; i++) chosen[i % chosen.length]];
}

/// Stable across app launches. [String.hashCode] is not.
int stableSeed(String text) {
  var hash = 0;
  for (final unit in text.codeUnits) {
    hash = 0x1fffffff & (hash * 31 + unit);
  }
  return hash;
}

final _fingerprints = <String, String>{};

/// Same bytes count as one cover, even when each track has its own file.
String? coverFingerprint(String path) {
  final known = _fingerprints[path];
  if (known != null) return known;
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final length = file.lengthSync();
    if (length <= 0) return null;
    final raf = file.openSync();
    try {
      final head = raf.readSync(length < 4096 ? length : 4096);
      final id = sha1.convert([
        ...length.toString().codeUnits,
        0,
        ...head,
      ]).toString();
      _fingerprints[path] = id;
      return id;
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return null;
  }
}

void forgetCoverFingerprint(String path) {
  _fingerprints.remove(path);
}

/// Fingerprint already computed for [path], without reading the file.
String? cachedCoverFingerprint(String path) => _fingerprints[path];
