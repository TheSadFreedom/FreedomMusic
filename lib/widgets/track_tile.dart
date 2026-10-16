import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/track.dart';
import '../navigation/library_navigation.dart';
import '../screens/metadata_editor_screen.dart';
import '../theme/app_theme.dart';
import '../utils/duration_format.dart';
import '../utils/playlist_actions.dart';
import '../utils/trash_actions.dart';
import 'track_cover_play.dart';
import 'track_overflow_menu.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    this.trailing,
    this.subtitle,
    this.onTap,
    this.onLongPress,
    this.enableMetadataEdit = true,
    this.enableTrash = true,
    this.showDuration = true,
  });

  final Track track;
  final Widget? trailing;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enableMetadataEdit;
  final bool enableTrash;
  final bool showDuration;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: onTap != null || enableMetadataEdit || enableTrash
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onTap: onTap,
        onLongPress: onLongPress ??
            (enableMetadataEdit
                ? () => openMetadataEditor(context, track)
                : null),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              TrackCoverPlay(
                path: track.coverPath,
                onPlay: onTap ?? () {},
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => openAlbumForTrack(context, track),
                        child: Text(
                          track.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.figtree(
                            color: AppTheme.paper,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.figtree(
                          color: AppTheme.paperMuted,
                          fontSize: 13,
                        ),
                      )
                    else
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => openArtistFromTrack(context, track),
                          child: Text(
                            track.displayArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.figtree(
                              color: AppTheme.paperMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (enableMetadataEdit || enableTrash)
                TrackOverflowMenu(
                  actions: [
                    if (enableMetadataEdit)
                      TrackMenuAction(
                        icon: Icons.edit_outlined,
                        label: 'Метаданные',
                        onSelected: () => openMetadataEditor(context, track),
                      ),
                    TrackMenuAction(
                      icon: Icons.queue_music_rounded,
                      label: 'В плейлист',
                      onSelected: () => addTrackToPlaylist(context, track),
                    ),
                    if (enableTrash)
                      TrackMenuAction(
                        icon: Icons.delete_outline_rounded,
                        label: 'В корзину',
                        destructive: true,
                        onSelected: () => moveTrackToTrash(context, track),
                      ),
                  ],
                ),
              if (showDuration) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    formatTrackDuration(track.durationMs),
                    textAlign: TextAlign.right,
                    style: GoogleFonts.figtree(
                      color: AppTheme.paperMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
