import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';

const _kYellow = Color(0xFFFFDB4D);

Future<bool> confirmMoveToTrash(BuildContext context, Track track) {
  return _confirmTrack(
    context,
    track: track,
    title: 'В корзину?',
    body:
        'Трек исчезнет из библиотеки, чарта, артистов и альбомов. '
        'Файл останется на диске — его можно вернуть из плейлиста «Корзина».',
    confirmLabel: 'В корзину',
    icon: Icons.delete_outline_rounded,
    accent: _kYellow,
    confirmColor: Colors.black,
  );
}

Future<bool> confirmDeleteForever(BuildContext context, Track track) {
  return _confirmTrack(
    context,
    track: track,
    title: 'Удалить навсегда?',
    body:
        'Файл будет удалён с диска. Восстановить трек уже не получится.',
    confirmLabel: 'Удалить файл',
    icon: Icons.delete_forever_rounded,
    accent: const Color(0xFFFF8A80),
    confirmColor: const Color(0xFF2A1214),
  );
}

Future<bool> _confirmTrack(
  BuildContext context, {
  required Track track,
  required String title,
  required String body,
  required String confirmLabel,
  required IconData icon,
  required Color accent,
  required Color confirmColor,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (ctx) => _TrackConfirmDialog(
      track: track,
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      icon: icon,
      accent: accent,
      confirmColor: confirmColor,
    ),
  );
  return result == true;
}

class _TrackConfirmDialog extends StatelessWidget {
  const _TrackConfirmDialog({
    required this.track,
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.icon,
    required this.accent,
    required this.confirmColor,
  });

  final Track track;
  final String title;
  final String body;
  final String confirmLabel;
  final IconData icon;
  final Color accent;
  final Color confirmColor;

  @override
  Widget build(BuildContext context) {
    final cover = track.coverPath;
    final hasCover = cover != null && File(cover).existsSync();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: hasCover
                            ? Image.file(File(cover), fit: BoxFit.cover)
                            : ColoredBox(
                                color: accent.withValues(alpha: 0.14),
                                child: Icon(icon, color: accent, size: 26),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.syne(
                              color: AppTheme.paper,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            track.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.figtree(
                              color: AppTheme.paper,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            track.displayArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.figtree(
                              color: AppTheme.paperMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  body,
                  style: GoogleFonts.figtree(
                    color: AppTheme.paperMuted,
                    height: 1.45,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _DialogButton(
                        label: 'Отмена',
                        background: Colors.white.withValues(alpha: 0.06),
                        foreground: AppTheme.paper,
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DialogButton(
                        label: confirmLabel,
                        background: accent,
                        foreground: confirmColor,
                        onPressed: () => Navigator.pop(context, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.figtree(
              color: foreground,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> moveTrackToTrash(BuildContext context, Track track) async {
  final ok = await confirmMoveToTrash(context, track);
  if (!ok || !context.mounted) return;
  final library = context.read<LibraryService>();
  final player = context.read<PlayerService>();
  await library.moveToTrash(track.trackKey);
  await player.removeTrackFromQueue(track.trackKey);
}

Future<void> restoreTrackFromTrash(BuildContext context, Track track) async {
  final library = context.read<LibraryService>();
  await library.restoreFromTrash(track.trackKey);
}

Future<void> deleteTrackForever(BuildContext context, Track track) async {
  final ok = await confirmDeleteForever(context, track);
  if (!ok || !context.mounted) return;
  final library = context.read<LibraryService>();
  final player = context.read<PlayerService>();
  await library.deleteTrackPermanently(track.trackKey);
  await player.removeTrackFromQueue(track.trackKey);
}
