import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_sheet.dart';

const _kYellow = Color(0xFFFFDB4D);

/// Pick a user playlist (or create one) and add [track] to it.
Future<void> addTrackToPlaylist(BuildContext context, Track track) async {
  final library = context.read<LibraryService>();
  final lists = library.playlists.where((p) => !p.isSystem).toList();

  final choice = await showAppBottomSheet<Object>(
    context: context,
    title: 'В плейлист',
    scrollControlled: true,
    buildChildren: (sheetCtx) => [
      SheetRow(
        title: 'Новый плейлист',
        subtitle: 'Создать и добавить трек',
        leadingIcon: Icons.add_rounded,
        leadingAccent: true,
        onTap: () => Navigator.pop(sheetCtx, 'new'),
      ),
      if (lists.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            'Своих плейлистов пока нет',
            style: GoogleFonts.figtree(
              color: AppTheme.paperMuted,
              fontSize: 13,
            ),
          ),
        )
      else
        for (final pl in lists)
          SheetRow(
            title: pl.name,
            subtitle: _tracksLabel(pl.trackCount),
            leadingIcon: Icons.queue_music_rounded,
            onTap: () => Navigator.pop(sheetCtx, pl.id),
          ),
    ],
  );
  if (choice == null || !context.mounted) return;

  final int playlistId;
  final String playlistName;
  if (choice == 'new') {
    final name = await _askPlaylistName(context);
    if (name == null || !context.mounted) return;
    playlistId = await library.createPlaylist(name);
    playlistName = name;
  } else {
    playlistId = choice as int;
    playlistName = library.playlistById(playlistId)?.name ?? 'плейлист';
  }

  final added = await library.addToPlaylist(playlistId, track.trackKey);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        added
            ? '«${track.displayTitle}» добавлен в «$playlistName»'
            : 'Уже есть в «$playlistName»',
        style: GoogleFonts.figtree(fontWeight: FontWeight.w600),
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.inkLift,
    ),
  );
}

String _tracksLabel(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) return '$count трек';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$count трека';
  }
  return '$count треков';
}

Future<String?> _askPlaylistName(BuildContext context) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A2220),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Новый плейлист',
        style: GoogleFonts.syne(
          color: AppTheme.paper,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: GoogleFonts.figtree(color: AppTheme.paper),
        cursorColor: _kYellow,
        decoration: InputDecoration(
          hintText: 'Название',
          hintStyle: GoogleFonts.figtree(color: AppTheme.paperMuted),
          filled: true,
          fillColor: AppTheme.ink.withValues(alpha: 0.55),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            'Отмена',
            style: GoogleFonts.figtree(color: AppTheme.paperMuted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(
            'Создать',
            style: GoogleFonts.figtree(
              color: _kYellow,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
  controller.dispose();
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return trimmed;
}
