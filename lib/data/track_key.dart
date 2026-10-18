import 'package:crypto/crypto.dart';
import 'dart:convert';

String normalizeTag(String? value) {
  if (value == null) return '';
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Missing tag. The word Unknown is the same as an empty field.
bool isBlankMeta(String? value) {
  final text = value?.trim().toLowerCase() ?? '';
  return text.isEmpty || text == 'unknown';
}

/// Text for a metadata field. Unknown is blank.
String metaFieldText(String? value) => isBlankMeta(value) ? '' : value!.trim();

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

/// Names that are actually filled in. Unknown is dropped.
String? storedPeople(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final names = splitArtists(raw).where((name) => !isBlankMeta(name)).toList();
  if (names.isEmpty) return null;
  return names.join(', ');
}

/// Artist tag for storage. No real names means Unknown.
String storedArtists(String? raw) => storedPeople(raw) ?? 'Unknown';

final _trailingCredit = RegExp(
  r'\s*(?:[-–—]\s*)?(?:[\(\[]\s*)?(?:produced|featuring|prod\.?|feat\.?|ft\.?)(?!\w)(?:\s+by\b)?\s+\S[^()\[\]]*(?:[\)\]])?\s*$',
  caseSensitive: false,
);

/// Drop a credit stuck on the end of a title or album.
/// «Song feat. Shakewell» and «Song (prod. by Name)» become «Song».
String stripTrailingCredit(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return text;
  while (true) {
    final next = text.replaceFirst(_trailingCredit, '').trim();
    if (next.isEmpty || next == text) return text;
    text = next;
  }
}

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
