import 'package:flutter/material.dart';

import '../models/track.dart';
import '../navigation/library_navigation.dart';
import 'track_title_line.dart';

/// Title → album page, artist → artist page.
class TrackMetaLinks extends StatelessWidget {
  const TrackMetaLinks({
    super.key,
    required this.track,
    this.titleStyle,
    this.artistStyle,
    this.showArtist = true,
    this.maxTitleLines = 1,
    this.maxArtistLines = 1,
  });

  final Track track;
  final TextStyle? titleStyle;
  final TextStyle? artistStyle;
  final bool showArtist;
  final int maxTitleLines;
  final int maxArtistLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TrackTitleLine(
          title: track.displayTitle,
          note: track.displayNote,
          style: titleStyle,
          maxLines: maxTitleLines,
          onTap: () => openAlbumForTrack(context, track),
        ),
        if (showArtist) ...[
          const SizedBox(height: 2),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openArtistFromTrack(context, track),
              child: Text(
                track.displayArtist,
                maxLines: maxArtistLines,
                overflow: TextOverflow.ellipsis,
                style: artistStyle,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
