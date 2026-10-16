import 'package:crypto/crypto.dart';
import 'dart:convert';

String normalizeTag(String? value) {
  if (value == null) return '';
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Split "A, B feat. C" into individual artist names.
/// Separators: comma and feat./ft./featuring (case-insensitive).
List<String> splitArtists(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const ['Unknown'];
  final parts = raw
      .split(RegExp(
        r'\s*,\s*|\s+feat\.?\s+|\s+ft\.?\s+|\s+featuring\s+',
        caseSensitive: false,
      ))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  return parts.isEmpty ? const ['Unknown'] : parts;
}

/// Canonical artist string for storage / display: "A, B".
String formatArtists(String? raw) => splitArtists(raw).join(', ');

/// Names in the producer tag. Empty tag is nobody, not "Unknown".
List<String> producerNames(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return splitArtists(raw)
      .where((name) => name.toLowerCase() != 'unknown')
      .toList(growable: false);
}

/// Ordered unique artists for track identity (order-independent).
String normalizeArtistsForKey(String? raw) {
  final parts = splitArtists(raw).map(normalizeTag).toSet().toList()..sort();
  return parts.join(',');
}

/// Logical track identity from metadata (not file path).
/// Same artists + title => one track (album / duration do not matter).
/// Artist order in the tag does not matter ("A, B" == "B, A").
String buildTrackKey({
  required String artist,
  required String title,
}) {
  final payload = [
    normalizeArtistsForKey(artist),
    normalizeTag(title),
  ].join('|');
  return sha1.convert(utf8.encode(payload)).toString();
}

/// [aliasByNorm] maps `normalizeTag(oldName)` → preferred display name.
/// Does not rewrite files — only the logical artist string in the index.
String applyArtistAliases(String artistRaw, Map<String, String> aliasByNorm) {
  if (aliasByNorm.isEmpty) return formatArtists(artistRaw);
  final resolved = <String>[];
  final seen = <String>{};
  for (final part in splitArtists(artistRaw)) {
    final mapped = aliasByNorm[normalizeTag(part)] ?? part;
    if (seen.add(normalizeTag(mapped))) resolved.add(mapped);
  }
  return resolved.isEmpty ? 'Unknown' : resolved.join(', ');
}
