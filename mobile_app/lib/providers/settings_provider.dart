import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings state provider
class SettingsProvider extends ChangeNotifier {
  // Theme
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  // Language
  String _language = 'vi';
  String get language => _language;

  // Font size
  double _fontScale = 1.0;
  double get fontScale => _fontScale;

  // Sound
  bool _soundEnabled = true;
  bool get soundEnabled => _soundEnabled;

  // Notifications
  bool _pushNotifications = true;
  bool get pushNotifications => _pushNotifications;

  bool _emailNotifications = false;
  bool get emailNotifications => _emailNotifications;

  bool _soundNotifications = true;
  bool get soundNotifications => _soundNotifications;

  bool _vibration = true;
  bool get vibration => _vibration;

  // Data controls
  bool _improveModel = true;
  bool get improveModel => _improveModel;

  // Permissions
  bool _permissionFileAccess = false;
  bool get permissionFileAccess => _permissionFileAccess;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final themeModeIndex = prefs.getInt('themeMode') ?? 0;
    _themeMode = ThemeMode.values[themeModeIndex];
    
    _language = prefs.getString('language') ?? 'vi';
    _fontScale = prefs.getDouble('fontScale') ?? 1.0;
    _soundEnabled = prefs.getBool('soundEnabled') ?? true;
    _pushNotifications = prefs.getBool('pushNotifications') ?? true;
    _emailNotifications = prefs.getBool('emailNotifications') ?? false;
    _soundNotifications = prefs.getBool('soundNotifications') ?? true;
    _vibration = prefs.getBool('vibration') ?? true;
    _improveModel = prefs.getBool('improveModel') ?? true;
    _permissionFileAccess = prefs.getBool('permissionFileAccess') ?? false;
    
    notifyListeners();
  }

  Future<void> setPermissionFileAccess(bool enabled) async {
    _permissionFileAccess = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissionFileAccess', enabled);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    _language = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
    notifyListeners();
  }

  Future<void> setFontScale(double scale) async {
    _fontScale = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontScale', scale);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('soundEnabled', enabled);
    notifyListeners();
  }

  Future<void> setPushNotifications(bool enabled) async {
    _pushNotifications = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pushNotifications', enabled);
    notifyListeners();
  }

  Future<void> setEmailNotifications(bool enabled) async {
    _emailNotifications = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('emailNotifications', enabled);
    notifyListeners();
  }

  Future<void> setSoundNotifications(bool enabled) async {
    _soundNotifications = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('soundNotifications', enabled);
    notifyListeners();
  }

  Future<void> setVibration(bool enabled) async {
    _vibration = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibration', enabled);
    notifyListeners();
  }

  Future<void> setImproveModel(bool enabled) async {
    _improveModel = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('improveModel', enabled);
    notifyListeners();
  }
}
