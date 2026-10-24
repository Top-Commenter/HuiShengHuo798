import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyThemeMode = 'theme_mode';
  static const _keyShowScore = 'show_score_tab';

  ThemeMode _themeMode = ThemeMode.light;

  /// 是否显示底部“积分”标签页（积分模块可选）
  bool _showScore = true;

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  bool get showScore => _showScore;

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_keyThemeMode);
    if (v != null) _themeMode = v == 'dark' ? ThemeMode.dark : ThemeMode.light;
    _showScore = prefs.getBool(_keyShowScore) ?? true;
    notifyListeners();
  }

  Future<void> setShowScore(bool v) async {
    _showScore = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowScore, v);
  }

  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, isDark ? 'dark' : 'light');
  }
}
