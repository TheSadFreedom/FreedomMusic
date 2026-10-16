import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Aligned yellow «Слушать» + shuffle circle (Yandex-style).
class ListenActions extends StatelessWidget {
  const ListenActions({
    super.key,
    required this.onListen,
    required this.onShuffle,
    this.extra = const [],
    this.center = false,
  });

  final VoidCallback? onListen;
  final VoidCallback? onShuffle;
  final List<Widget> extra;
  final bool center;

  static const yellow = Color(0xFFFFDB4D);
  static const _h = 48.0;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      SizedBox(
        height: _h,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: yellow,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            shape: const StadiumBorder(),
            textStyle: GoogleFonts.figtree(
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          onPressed: onListen,
          icon: const Icon(Icons.play_arrow_rounded, size: 26),
          label: const Text('Слушать'),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: _h,
        height: _h,
        child: IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: yellow,
            foregroundColor: Colors.black,
            padding: EdgeInsets.zero,
          ),
          onPressed: onShuffle,
          tooltip: 'Случайный порядок',
          icon: const Icon(Icons.shuffle_rounded, size: 22),
        ),
      ),
      for (final w in extra) ...[
        const SizedBox(width: 10),
        SizedBox(width: _h, height: _h, child: w),
      ],
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          center ? MainAxisAlignment.center : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}
