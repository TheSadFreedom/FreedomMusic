import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/library_service.dart';
import '../theme/app_theme.dart';

/// Track-cover collage for a user playlist that has no chosen cover.
class PlaylistMosaicLoader extends StatelessWidget {
  const PlaylistMosaicLoader({
    super.key,
    required this.playlistId,
    required this.fallback,
  });

  final int playlistId;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final paths = context.watch<LibraryService>().playlistMosaic(playlistId);
    if (paths.isEmpty) return fallback;
    return PlaylistCoverMosaic(paths: paths);
  }
}

/// One image, or a two-by-two grid. Two or three different covers are repeated
/// so the grid stays full.
class PlaylistCoverMosaic extends StatelessWidget {
  const PlaylistCoverMosaic({super.key, required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const ColoredBox(color: AppTheme.inkLift);
    if (paths.length == 1) return _image(paths.first);
    final cells = [for (var i = 0; i < 4; i++) paths[i % paths.length]];
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              _cell(cells[0]),
              _cell(cells[1]),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              _cell(cells[2]),
              _cell(cells[3]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(String? path) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: path == null
            ? const ColoredBox(color: AppTheme.inkLift)
            : _image(path),
      ),
    );
  }

  Widget _image(String path) {
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          const ColoredBox(color: AppTheme.inkLift),
    );
  }
}
