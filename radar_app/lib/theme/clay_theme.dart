import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Claymorphism palette for the whole app, in a light and a dark variant.
/// Surfaces "pop" through two soft shadows (one lighter than the surface,
/// one darker), so each variant has its own pair of shadow colors.
///
/// The colors are getters that follow [ClayColors.dark]; flipping the theme
/// goes through [ThemeController], which rebuilds the app.
class ClayColors {
  static bool dark = false;

  static Color get background => dark ? const Color(0xFF272B36) : const Color(0xFFE6E7EE);
  static Color get surface => background;
  static Color get primary => dark ? const Color(0xFF8C85FF) : const Color(0xFF6C63FF);
  static Color get danger => const Color(0xFFFF6B6B);
  static Color get success => const Color(0xFF4ECCA3);
  static Color get warning => const Color(0xFFFFB84C);
  static Color get textPrimary => dark ? const Color(0xFFE8E9F1) : const Color(0xFF3A3A4A);
  static Color get textSecondary => dark ? const Color(0xFF9A9CB5) : const Color(0xFF8A8AA3);

  static Color get shadowLight => dark ? const Color(0xFF353A48) : const Color(0xFFFFFFFF);
  static Color get shadowDark => dark ? const Color(0xFF14161C) : const Color(0xFFA3A6B5);
}

/// Holds the light/dark choice, remembers it between launches, and tells
/// the app to rebuild when it changes.
class ThemeController extends ValueNotifier<bool> {
  ThemeController._() : super(false);
  static final ThemeController instance = ThemeController._();

  static const _key = 'dark_mode';

  /// Loads the saved choice; on first launch follows the phone's setting.
  Future<void> load() async {
    bool isDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    try {
      final prefs = await SharedPreferences.getInstance();
      isDark = prefs.getBool(_key) ?? isDark;
    } catch (_) {}
    ClayColors.dark = isDark;
    value = isDark;
  }

  Future<void> toggle() async {
    final next = !value;
    ClayColors.dark = next;
    value = next;
    _rebuildEverything();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, next);
    } catch (_) {}
  }
}

/// Most widgets read [ClayColors] directly rather than through Theme.of,
/// so a theme change alone wouldn't repaint them. Mark every element in the
/// tree dirty instead: open screens and the Bluetooth connection are kept.
void _rebuildEverything() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return;
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }
  root.visitChildren(visit);
}

/// Small icon button that flips light/dark; drop it into any AppBar.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.value;
    return IconButton(
      tooltip: isDark ? 'Light mode' : 'Dark mode',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: ThemeController.instance.toggle,
    );
  }
}

ThemeData buildClayTheme() {
  final brightness = ClayColors.dark ? Brightness.dark : Brightness.light;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: ClayColors.background,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: ClayColors.primary,
      primary: ClayColors.primary,
      surface: ClayColors.surface,
      brightness: brightness,
    ),
    textTheme: TextTheme(
      headlineSmall: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: ClayColors.textPrimary),
      bodyMedium: TextStyle(color: ClayColors.textPrimary),
      bodySmall: TextStyle(color: ClayColors.textSecondary),
      titleMedium: TextStyle(color: ClayColors.textPrimary),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: ClayColors.background,
      foregroundColor: ClayColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ClayColors.background,
      indicatorColor: ClayColors.primary.withOpacity(0.18),
    ),
    dialogTheme: DialogThemeData(backgroundColor: ClayColors.background),
  );
}
