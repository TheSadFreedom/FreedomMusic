import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/library_service.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 148.0;
        if (paths.length == 1) return _image(context, paths.first, side);
        final cell = side / 2;
        final cells = [for (var i = 0; i < 4; i++) paths[i % paths.length]];
        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  _cell(context, cells[0], cell),
                  _cell(context, cells[1], cell),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  _cell(context, cells[2], cell),
                  _cell(context, cells[3], cell),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _cell(BuildContext context, String? path, double logicalSize) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: path == null
            ? const ColoredBox(color: AppTheme.inkLift)
            : _image(context, path, logicalSize),
      ),
    );
  }

  Widget _image(BuildContext context, String path, double logicalSize) {
    return fileCover(
      context,
      path,
      logicalSize: logicalSize,
      errorBuilder: (context, error, stackTrace) =>
          const ColoredBox(color: AppTheme.inkLift),
    );
  }
}
