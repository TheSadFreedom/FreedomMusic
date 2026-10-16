import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// audioplayers on Windows feeds the path into Media Foundation as a URL.
/// Non-ASCII names and characters like `#` / `?` break `CreateObjectFromURL`
/// (and can crash the event channel with invalid UTF-8 in error details).
///
/// We expose an ASCII-only hardlink under [aliasDir] when needed.
class PlayPathResolver {
  PlayPathResolver(this.aliasDir);

  final String aliasDir;

  static bool needsAlias(String path) {
    for (final c in path.codeUnits) {
      if (c > 127) return true;
      // Reserved / unsafe in MF URL resolution
      if (c == 0x23 || // #
          c == 0x3F || // ?
          c == 0x25 || // %
          c == 0x26 || // &
          c == 0x7E) {
        // ~  (also appears in 8.3 short names)
        return true;
      }
    }
    return false;
  }

  Future<String> resolve(String path) async {
    if (!Platform.isWindows || !needsAlias(path)) return path;

    final src = File(path);
    if (!await src.exists()) return path;

    await Directory(aliasDir).create(recursive: true);
    final ext = p.extension(path).toLowerCase();
    final safeExt = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(ext) ? ext : '.mp3';
    final hash = sha1.convert(utf8.encode(p.normalize(path))).toString();
    final alias = p.join(aliasDir, '$hash$safeExt');
    final aliasFile = File(alias);

    if (await aliasFile.exists()) {
      try {
        if (await aliasFile.length() == await src.length()) {
          return alias;
        }
      } catch (_) {}
      try {
        await aliasFile.delete();
      } catch (_) {}
    }

    if (_createHardLink(alias, path)) {
      return alias;
    }

    // Cross-volume / non-NTFS fallback — copy once.
    try {
      await src.copy(alias);
      return alias;
    } catch (e) {
      debugPrint('play alias failed for $path: $e');
      return path;
    }
  }
}

typedef _CreateHardLinkWNative = Int32 Function(
  Pointer<Utf16> newLink,
  Pointer<Utf16> existing,
  Pointer<Void> security,
);

typedef _CreateHardLinkWDart = int Function(
  Pointer<Utf16> newLink,
  Pointer<Utf16> existing,
  Pointer<Void> security,
);

bool _createHardLink(String newPath, String existingPath) {
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final create = kernel32.lookupFunction<_CreateHardLinkWNative,
        _CreateHardLinkWDart>('CreateHardLinkW');
    final neu = newPath.toNativeUtf16();
    final old = existingPath.toNativeUtf16();
    try {
      final ok = create(neu, old, nullptr);
      return ok != 0;
    } finally {
      malloc.free(neu);
      malloc.free(old);
    }
  } catch (e) {
    debugPrint('CreateHardLinkW failed: $e');
    return false;
  }
}
