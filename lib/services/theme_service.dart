import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  static const String _themeKey = 'night_vision_enabled';

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.dark);

  /// Load persisted theme preference. Call once at app startup.
  Future<void> loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    // Default to true (Night Vision) if not set
    final isDark = prefs.getBool(_themeKey) ?? true;
    themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> toggleTheme(bool isDark) async {
    themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, isDark);
  }
}
