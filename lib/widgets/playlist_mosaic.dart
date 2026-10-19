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

/// Two-by-two collage. Fewer than four covers leave the spare cells empty.
class PlaylistCoverMosaic extends StatelessWidget {
  const PlaylistCoverMosaic({super.key, required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const ColoredBox(color: AppTheme.inkLift);
    if (paths.length == 1) return _image(paths.first);
    if (paths.length == 2) {
      return Row(
        children: [
          _cell(paths[0]),
          _cell(paths[1]),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              _cell(paths[0]),
              _cell(paths[1]),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              _cell(paths[2]),
              _cell(paths.length > 3 ? paths[3] : null),
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
