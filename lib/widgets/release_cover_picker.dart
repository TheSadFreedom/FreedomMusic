import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/track_key.dart';
import '../models/artist_release.dart';
import '../models/track.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';
import 'track_overflow_menu.dart';

/// Right-click action. Hidden when the release has fewer than two covers.
TrackMenuAction? releaseCoverMenuAction(
  BuildContext context,
  ArtistRelease release,
) {
  final library = context.read<LibraryService>();
  if (releaseCoverChoices(library, release).length < 2) return null;
  return TrackMenuAction(
    icon: Icons.image_outlined,
    label: 'Обложка',
    onSelected: () => showReleaseCoverPicker(context, release),
  );
}

List<Track> releaseCoverChoices(LibraryService library, ArtistRelease release) {
  final choices = <Track>[];
  for (final track in release.tracks) {
    final live = library.trackByKey(track.trackKey) ?? track;
    if (_hasCover(live)) choices.add(live);
  }
  choices.sort(_byDiscAndNumber);
  return choices;
}

bool _hasCover(Track track) {
  final path = track.coverPath;
  return path != null && path.isNotEmpty && File(path).existsSync();
}

int _byDiscAndNumber(Track a, Track b) {
  final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
  if (disc != 0) return disc;
  final number = (a.trackNumber ?? 9999).compareTo(b.trackNumber ?? 9999);
  if (number != 0) return number;
  return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
}

Future<void> showReleaseCoverPicker(
  BuildContext context,
  ArtistRelease release,
) {
  final library = context.read<LibraryService>();
  final choices = releaseCoverChoices(library, release);
  if (choices.length < 2) return Future<void>.value();
  final stored = library.releaseCoverTrackKey(release);
  final selected = choices.any((track) => track.trackKey == stored)
      ? stored
      : choices.first.trackKey;

  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) {
      final height = MediaQuery.sizeOf(dialogContext).height * 0.72;
      return Dialog(
        backgroundColor: const Color(0xFF1A2220),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520, maxHeight: height),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Обложка',
                  style: GoogleFonts.syne(
                    color: AppTheme.paper,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Выберите обложку из треков релиза',
                  style: GoogleFonts.figtree(
                    color: AppTheme.paperMuted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 140,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: choices.length,
                    itemBuilder: (context, index) {
                      final track = choices[index];
                      return _CoverChoice(
                        track: track,
                        selected: track.trackKey == selected,
                        onTap: () async {
                          await library.setReleaseCover(release, track.trackKey);
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _CoverChoice extends StatelessWidget {
  const _CoverChoice({
    required this.track,
    required this.selected,
    required this.onTap,
  });

  final Track track;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final number = track.trackNumber;
    final title = (number != null && number > 0)
        ? '$number · ${metaFieldText(track.displayTitle)}'
        : metaFieldText(track.displayTitle);
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? AppTheme.lime
                      : Colors.white.withValues(alpha: 0.08),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(track.coverPath!),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.figtree(
              color: selected ? AppTheme.lime : AppTheme.paper,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
