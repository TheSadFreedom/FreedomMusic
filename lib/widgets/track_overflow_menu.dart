import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

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

/// Anchored dropdown for a track's ⋮ button.
class TrackOverflowMenu extends StatefulWidget {
  const TrackOverflowMenu({
    super.key,
    required this.actions,
    this.icon = Icons.more_vert,
    this.dense = false,
  });

  final List<TrackMenuAction> actions;
  final IconData icon;
  final bool dense;

  @override
  State<TrackOverflowMenu> createState() => _TrackOverflowMenuState();
}

class _TrackOverflowMenuState extends State<TrackOverflowMenu> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    final icon = widget.icon;
    final dense = widget.dense;
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 6),
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
        final open = controller.isOpen;
        void toggle() {
          if (open) {
            controller.close();
          } else {
            controller.open();
          }
        }

        final glyph = Icon(
          icon,
          size: dense ? 18 : 20,
          color: open ? AppTheme.paper : AppTheme.paperMuted,
        );
        if (dense) {
          return InkWell(
            onTap: toggle,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: glyph,
            ),
          );
        }
        return IconButton(
          visualDensity: VisualDensity.compact,
          style: const ButtonStyle(
            foregroundColor: WidgetStatePropertyAll(AppTheme.paper),
            backgroundColor: WidgetStatePropertyAll(Colors.transparent),
            mouseCursor: WidgetStatePropertyAll(SystemMouseCursors.click),
          ),
          onPressed: toggle,
          icon: glyph,
        );
      },
    );
  }
}
