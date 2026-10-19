import 'package:flutter/widgets.dart';

/// Root [MaterialApp] navigator. The player bar lives above it.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// A context that can open routes and dialogs.
///
/// The full player is painted outside the navigator, so its own context
/// cannot push a page or show a sheet. Fall back to the root overlay.
BuildContext navigatorContext(BuildContext context) {
  if (Navigator.maybeOf(context) != null) return context;
  final root = appNavigatorKey.currentState?.overlay?.context;
  if (root != null && root.mounted) return root;
  return context;
}
