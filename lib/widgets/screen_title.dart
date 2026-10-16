import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../utils/breakpoints.dart';

/// Large page title matching the Chart header style.
class ScreenTitle extends StatelessWidget {
  const ScreenTitle({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final phone = isPhone(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        phone ? 16 : 20,
        phone ? 12 : 16,
        phone ? 16 : 20,
        8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.syne(
                color: AppTheme.paper,
                fontSize: phone ? 26 : 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
