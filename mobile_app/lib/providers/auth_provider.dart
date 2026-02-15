import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

/// Authentication state provider
class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  bool _isInitializing = true; // Only true during initial auth check
  String? _error;
  bool _isAuthenticated = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing; // New getter
  String? get error => _error;
  bool get isAuthenticated => _isAuthenticated;

  AuthProvider() {
    // Register token expiration callback
    ApiService.setTokenExpiredCallback(() {
      print('>>> AuthProvider: Token expired callback triggered');
      _handleTokenExpiration();
    });
    _checkAuth();
  }

  void _handleTokenExpiration() {
    logout();
    _error = 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
    notifyListeners();
  }

  /// Check if user is already authenticated (only called on app startup)
  Future<void> _checkAuth() async {
    _isInitializing = true;
    notifyListeners();

    try {
      final isAuth = await AuthService.isAuthenticated();
      if (isAuth) {
        _user = await StorageService.getUser();
        _isAuthenticated = true;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Login
  Future<bool> login(String usernameOrEmail, String password, {bool rememberMe = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    bool verificationRequired = false;
    
    try {
      _user = await AuthService.login(usernameOrEmail, password);
      _isAuthenticated = true;
      await StorageService.setRememberMe(rememberMe);
      return true;
    } on DeviceVerificationRequired {
      // DON'T notify listeners - let LoginScreen handle navigation first
      // If we notify, AuthWrapper will rebuild and destroy our navigation
      verificationRequired = true;
      _isLoading = false;
      rethrow;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      // Only notify if it's NOT a verification case
      if (!verificationRequired) {
        notifyListeners();
      }
    }
  }

  /// Register
  Future<bool> register({
    required String username,
    required String email,
    required String password,
    String? gender,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await AuthService.register(
        username: username,
        email: email,
        password: password,
        gender: gender,
      );
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Verify device
  Future<bool> verifyDevice(int userId, String code) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await AuthService.verifyDevice(userId, code);
      _isAuthenticated = true;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Resend verification code
  Future<bool> resendCode(int userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await AuthService.resendVerificationCode(userId);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Forgot password
  Future<bool> forgotPassword(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await AuthService.forgotPassword(email);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reset password
  Future<bool> resetPassword(String token, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await AuthService.resetPassword(token, newPassword);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Change password
  Future<bool> changePassword(String currentPassword, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await AuthService.changePassword(currentPassword, newPassword);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update profile
  Future<bool> updateProfile({String? username, String? gender, String? phoneNumber}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _user = await AuthService.updateProfile(
        username: username,
        gender: gender,
        phoneNumber: phoneNumber,
      );
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Logout
  Future<void> logout() async {
    await AuthService.logout();
    _user = null;
    _isAuthenticated = false;
    notifyListeners();
  }

  /// Delete account
  Future<bool> deleteAccount(String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await AuthService.deleteAccount(password);
      await logout(); // Logout and clear data
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
