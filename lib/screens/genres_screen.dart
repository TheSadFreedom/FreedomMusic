import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../widgets/track_tile.dart';

class GenreDetailScreen extends StatelessWidget {
  const GenreDetailScreen({
    super.key,
    required this.genre,
    required this.tracks,
  });

  final String genre;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerService>();
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    genre,
                    style: GoogleFonts.syne(
                      color: AppTheme.paper,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Случайный порядок',
                  onPressed: () => player.playTracks(tracks, shuffle: true),
                  icon: const Icon(Icons.shuffle),
                ),
                IconButton(
                  tooltip: 'Играть',
                  onPressed: () => player.playTracks(tracks),
                  icon: const Icon(Icons.play_arrow),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return TrackTile(
                  track: track,
                  onTap: () => player.playTracks(tracks, startIndex: index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
