import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Listening-room palette: ink surface, moss accent, warm paper text.
abstract final class AppTheme {
  static const ink = Color(0xFF0C1210);
  static const inkLift = Color(0xFF15201C);
  static const moss = Color(0xFF3D8B6E);
  static const mossBright = Color(0xFF5CBA92);
  static const lime = Color(0xFFC8F071);
  static const paper = Color(0xFFF2EDE4);
  static const paperMuted = Color(0xFFA8A297);

  static ThemeData dark() {
    final base =
        ColorScheme.fromSeed(
          seedColor: moss,
          brightness: Brightness.dark,
          surface: ink,
          primary: mossBright,
          secondary: lime,
          tertiary: moss,
        ).copyWith(
          surface: ink,
          surfaceContainerHighest: inkLift,
          onSurface: paper,
          onSurfaceVariant: paperMuted,
          primary: mossBright,
          onPrimary: ink,
          secondary: lime,
          onSecondary: ink,
        );

    final display = GoogleFonts.syneTextTheme().apply(
      bodyColor: paper,
      displayColor: paper,
    );
    final body = GoogleFonts.figtreeTextTheme().apply(
      bodyColor: paper,
      displayColor: paper,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: base,
      scaffoldBackgroundColor: ink,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: body.copyWith(
        displayLarge: display.displayLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
          height: 0.95,
        ),
        displayMedium: display.displayMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
          height: 0.98,
        ),
        headlineLarge: display.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        headlineMedium: display.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        titleLarge: display.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: ink,
        foregroundColor: paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: display.titleLarge?.copyWith(
          color: paper,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: ink,
        indicatorColor: moss.withValues(alpha: 0.35),
        indicatorShape: const CircleBorder(),
        selectedIconTheme: const IconThemeData(color: lime),
        unselectedIconTheme: IconThemeData(color: paperMuted),
        selectedLabelTextStyle: body.labelMedium?.copyWith(color: lime),
        unselectedLabelTextStyle: body.labelMedium?.copyWith(color: paperMuted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: inkLift,
        indicatorColor: moss.withValues(alpha: 0.35),
        indicatorShape: const CircleBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return body.labelSmall?.copyWith(
            color: selected ? lime : paperMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
      ),
      // Desktop: hand cursor on interactive Material controls.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(mouseCursor: WidgetStateMouseCursor.clickable),
      ),
      listTileTheme: const ListTileThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
      ),
      switchTheme: const SwitchThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
      ),
      sliderTheme: const SliderThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(10),
        thumbVisibility: const WidgetStatePropertyAll(true),
        trackVisibility: const WidgetStatePropertyAll(false),
        interactive: true,
        radius: const Radius.circular(5),
        minThumbLength: 48,
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return paperMuted.withValues(alpha: 0.8);
          }
          if (states.contains(WidgetState.hovered)) {
            return paperMuted.withValues(alpha: 0.62);
          }
          return paperMuted.withValues(alpha: 0.34);
        }),
        trackColor: const WidgetStatePropertyAll(Color(0x00000000)),
        trackBorderColor: const WidgetStatePropertyAll(Color(0x00000000)),
      ),
    );
  }
}

/// Desktop scrollbars sit in their own gutter, so list controls stay clear of the thumb.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  static const gutter = 14.0;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    switch (axisDirectionToAxis(details.direction)) {
      case Axis.horizontal:
        return child;
      case Axis.vertical:
        return Scrollbar(
          controller: details.controller,
          child: Padding(
            padding: const EdgeInsets.only(right: gutter),
            child: child,
          ),
        );
    }
  }
}
