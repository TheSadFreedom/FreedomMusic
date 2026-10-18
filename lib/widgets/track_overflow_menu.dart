import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/track.dart';
import '../screens/metadata_editor_screen.dart';
import '../theme/app_theme.dart';
import '../utils/playlist_actions.dart';
import '../utils/trash_actions.dart';

class TrackMenuAction {
  const TrackMenuAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final bool destructive;
}

/// Metadata, playlist, and trash actions used by every track row.
List<TrackMenuAction> standardTrackActions(
  BuildContext context,
  Track track, {
  bool metadata = true,
  bool playlist = true,
  bool copyTitle = false,
  bool trash = true,
  VoidCallback? onMetadata,
}) {
  return [
    if (metadata)
      TrackMenuAction(
        icon: Icons.edit_outlined,
        label: 'Метаданные',
        onSelected: onMetadata ?? () => openMetadataEditor(context, track),
      ),
    if (playlist)
      TrackMenuAction(
        icon: Icons.queue_music_rounded,
        label: 'В плейлист',
        onSelected: () => addTrackToPlaylist(context, track),
      ),
    if (copyTitle)
      TrackMenuAction(
        icon: Icons.copy_rounded,
        label: 'Копировать название',
        onSelected: () => Clipboard.setData(
          ClipboardData(text: '${track.displayArtist} - ${track.displayTitle}'),
        ),
      ),
    if (trash)
      TrackMenuAction(
        icon: Icons.delete_outline_rounded,
        label: 'В корзину',
        destructive: true,
        onSelected: () => moveTrackToTrash(context, track),
      ),
  ];
}

/// Opens [actions] on a right-click over [child].
class TrackContextMenu extends StatefulWidget {
  const TrackContextMenu({
    super.key,
    required this.actions,
    required this.child,
  });

  final List<TrackMenuAction> actions;
  final Widget child;

  @override
  State<TrackContextMenu> createState() => _TrackContextMenuState();
}

class _TrackContextMenuState extends State<TrackContextMenu> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    final actions = widget.actions;
    return MenuAnchor(
      controller: _menu,
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xFF1E1E1E)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(18),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.55)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
      ),
      menuChildren: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final action in actions)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: InkWell(
                    mouseCursor: SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(10),
                    hoverColor: action.destructive
                        ? const Color(0xFFFF8A80).withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.06),
                    onTap: () {
                      _menu.close();
                      action.onSelected();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            action.icon,
                            size: 18,
                            color: action.destructive
                                ? const Color(0xFFFF8A80)
                                : AppTheme.paper,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            action.label,
                            style: GoogleFonts.figtree(
                              color: action.destructive
                                  ? const Color(0xFFFF8A80)
                                  : AppTheme.paper,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
            ),
          ),
        ),
      ],
      builder: (context, controller, child) {
        return GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onSecondaryTapDown: (details) {
            controller.open(position: details.localPosition);
          },
          child: widget.child,
        );
      },
    );
  }
}
