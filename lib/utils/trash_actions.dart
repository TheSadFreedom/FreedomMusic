import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';

Future<bool> confirmMoveToTrash(BuildContext context, Track track) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.inkLift,
      title: Text(
        'В корзину?',
        style: GoogleFonts.syne(
          color: AppTheme.paper,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        '«${track.displayTitle}» исчезнет из библиотеки, чарта, артистов '
        'и альбомов. Файл останется на диске — его можно восстановить '
        'из плейлиста «Корзина».',
        style: GoogleFonts.figtree(
          color: AppTheme.paperMuted,
          height: 1.45,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Отмена',
            style: GoogleFonts.figtree(color: AppTheme.paperMuted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'В корзину',
            style: GoogleFonts.figtree(
              color: const Color(0xFFFFDB4D),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
  return result == true;
}

Future<bool> confirmDeleteForever(BuildContext context, Track track) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.inkLift,
      title: Text(
        'Удалить файл навсегда?',
        style: GoogleFonts.syne(
          color: AppTheme.paper,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        '«${track.displayTitle}» будет удалён с диска вместе с файлом. '
        'Это действие нельзя отменить.',
        style: GoogleFonts.figtree(
          color: AppTheme.paperMuted,
          height: 1.45,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Отмена',
            style: GoogleFonts.figtree(color: AppTheme.paperMuted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Удалить файл',
            style: GoogleFonts.figtree(
              color: Colors.redAccent.shade100,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
  return result == true;
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
