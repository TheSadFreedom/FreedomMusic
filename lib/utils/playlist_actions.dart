import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';

/// Pick a user playlist (or create one) and add [track] to it.
Future<void> addTrackToPlaylist(BuildContext context, Track track) async {
  final library = context.read<LibraryService>();
  final lists = library.playlists.where((p) => !p.isSystem).toList();

  final choice = await showModalBottomSheet<Object>(
    context: context,
    backgroundColor: AppTheme.inkLift,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'В плейлист',
              style: GoogleFonts.syne(
                color: AppTheme.paper,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_rounded, color: Color(0xFFFFDB4D)),
            title: Text(
              'Новый плейлист',
              style: GoogleFonts.figtree(
                color: AppTheme.paper,
                fontWeight: FontWeight.w700,
              ),
            ),
            onTap: () => Navigator.pop(ctx, 'new'),
          ),
          if (lists.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Своих плейлистов пока нет',
                style: GoogleFonts.figtree(color: AppTheme.paperMuted),
              ),
            ),
          for (final pl in lists)
            ListTile(
              leading: const Icon(
                Icons.queue_music_rounded,
                color: AppTheme.paperMuted,
              ),
              title: Text(
                pl.name,
                style: GoogleFonts.figtree(
                  color: AppTheme.paper,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${pl.trackCount} треков',
                style: GoogleFonts.figtree(
                  color: AppTheme.paperMuted,
                  fontSize: 12,
                ),
              ),
              onTap: () => Navigator.pop(ctx, pl.id),
            ),
        ],
      ),
    ),
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

Future<String?> _askPlaylistName(BuildContext context) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.inkLift,
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
        decoration: InputDecoration(
          hintText: 'Название',
          hintStyle: GoogleFonts.figtree(color: AppTheme.paperMuted),
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
              color: const Color(0xFFFFDB4D),
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
