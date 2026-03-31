import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

/// Service for secure storage of tokens and user data
class StorageService {
  static const _storage = FlutterSecureStorage();
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _userDataKey = 'user_data';
  static const String _rememberMeKey = 'remember_me';

  /// Save authentication token
  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  /// Get stored token
  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  /// Save user ID
  static Future<void> saveUserId(int userId) async {
    await _storage.write(key: _userIdKey, value: userId.toString());
  }

  /// Get stored user ID
  static Future<int?> getUserId() async {
    final idStr = await _storage.read(key: _userIdKey);
    return idStr != null ? int.tryParse(idStr) : null;
  }

  /// Save user data
  static Future<void> saveUser(User user) async {
    await _storage.write(key: _userDataKey, value: jsonEncode(user.toJson()));
    await saveToken(user.token);
    await saveUserId(user.id);
  }

  /// Get stored user
  static Future<User?> getUser() async {
    final userData = await _storage.read(key: _userDataKey);
    if (userData == null) return null;
    
    final token = await getToken();
    if (token == null) return null;
    
    final json = jsonDecode(userData);
    return User.fromJson(json, token);
  }

  /// Save remember me preference
  static Future<void> setRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, value);
  }

  /// Get remember me preference
  static Future<bool> getRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberMeKey) ?? false;
  }

  /// Clear all stored data (logout)
  static Future<void> clearAll() async {
    await _storage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
