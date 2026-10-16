import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

const _kYellow = Color(0xFFFFDB4D);

/// Shared dark bottom sheet chrome: handle, title, padded list.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required String title,
  required List<Widget> Function(BuildContext sheetContext) buildChildren,
  bool scrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: scrollControlled,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.72;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Material(
            color: const Color(0xFF1A2220),
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.paper.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Text(
                      title,
                      style: GoogleFonts.syne(
                        color: AppTheme.paper,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      children: buildChildren(ctx),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.leadingColor,
    this.leadingIcon,
    this.leadingAccent = false,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Color? leadingColor;
  final IconData? leadingIcon;
  final bool leadingAccent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = leadingColor ?? (leadingAccent ? _kYellow : AppTheme.paperMuted);
    final lead = leading ??
        (leadingIcon == null
            ? null
            : _SheetIconWell(
                icon: leadingIcon!,
                color: iconColor,
                accent: leadingAccent || leadingColor == _kYellow,
              ));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (lead != null) ...[
                lead,
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.figtree(
                        color: AppTheme.paper,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.figtree(
                          color: AppTheme.paperMuted,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.paper.withValues(alpha: 0.22),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SheetArtistAvatar extends StatelessWidget {
  const SheetArtistAvatar({super.key, this.photoPath, this.size = 44});

  final String? photoPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget child = Icon(
      Icons.person_rounded,
      color: AppTheme.paperMuted.withValues(alpha: 0.85),
      size: size * 0.5,
    );
    final path = photoPath;
    if (path != null) {
      child = Image.file(
        File(path),
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, _, _) => Icon(
          Icons.person_rounded,
          color: AppTheme.paperMuted.withValues(alpha: 0.85),
          size: size * 0.5,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.inkLift,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.paper.withValues(alpha: 0.08),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _SheetIconWell extends StatelessWidget {
  const _SheetIconWell({
    required this.icon,
    required this.color,
    this.accent = false,
  });

  final IconData icon;
  final Color color;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accent
            ? _kYellow.withValues(alpha: 0.14)
            : AppTheme.paper.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}
