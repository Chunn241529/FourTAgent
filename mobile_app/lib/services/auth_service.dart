import '../config/api_config.dart';
import '../models/user.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Authentication service
class AuthService {
  /// Login with username/email and password
  static Future<User> login(String usernameOrEmail, String password, {String? deviceId}) async {
    final response = await ApiService.post(ApiConfig.login, body: {
      'username_or_email': usernameOrEmail,
      'password': password,
      if (deviceId != null) 'device_id': deviceId,
    });

    final data = ApiService.parseResponse(response);
    
    // Check if device verification is required
    // Backend returns: {"message": "Device verification required", "user_id": X, "email": Y}
    // without a token when verification is needed
    final token = data['access_token'] ?? data['token'];
    final message = data['message']?.toString().toLowerCase() ?? '';
    
    if (token == null && message.contains('verification')) {
      throw DeviceVerificationRequired(
        data['user_id'] ?? 0, 
        data['message'] ?? 'Device verification required',
      );
    }
    
    if (token == null) {
      throw ApiException(data['message'] ?? 'Login failed', response.statusCode);
    }

    final user = User.fromJson(data, token);
    await StorageService.saveUser(user);
    return user;
  }

  /// Register new user
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String? gender,
  }) async {
    final response = await ApiService.post(ApiConfig.register, body: {
      'username': username,
      'email': email,
      'password': password,
      if (gender != null) 'gender': gender,
    });

    return ApiService.parseResponse(response);
  }

  /// Verify device with code
  static Future<User> verifyDevice(int userId, String code) async {
    final response = await ApiService.post(
      '${ApiConfig.verify}?user_id=$userId',
      body: {'code': code},
    );

    final data = ApiService.parseResponse(response);
    final token = data['access_token'] ?? data['token'];
    
    if (token == null) {
      throw ApiException('No token received after verification', response.statusCode);
    }

    final user = User.fromJson(data, token);
    await StorageService.saveUser(user);
    return user;
  }

  /// Request password reset
  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final response = await ApiService.post(ApiConfig.forgetPassword, body: {
      'email': email,
    });

    return ApiService.parseResponse(response);
  }

  /// Reset password with token
  static Future<Map<String, dynamic>> resetPassword(String token, String newPassword) async {
    final response = await ApiService.post(ApiConfig.resetPassword, body: {
      'reset_token': token,
      'new_password': newPassword,
    });

    return ApiService.parseResponse(response);
  }

  /// Validate stored token
  static Future<bool> validateToken() async {
    try {
      final response = await ApiService.get(ApiConfig.validateToken);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Logout
  static Future<void> logout() async {
    await StorageService.clearAll();
  }

  /// Change password for authenticated user
  static Future<void> changePassword(String currentPassword, String newPassword) async {
    final response = await ApiService.post(ApiConfig.changePassword, body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    
    if (response.statusCode != 200) {
      final data = ApiService.parseResponse(response);
      throw ApiException(data['detail'] ?? 'Change password failed', response.statusCode);
    }
  }

  /// Update profile (username, gender)
  static Future<User> updateProfile({String? username, String? gender}) async {
    final response = await ApiService.put(ApiConfig.profile, body: {
      if (username != null) 'username': username,
      if (gender != null) 'gender': gender,
    });

    ApiService.parseResponse(response); // returns {"message": "...", "user": {...}}
    
    // Need to get User from storage to keep id, email, token intact
    final currentUser = await StorageService.getUser();
    if (currentUser == null) throw ApiException('User not logged in', 401);

    final updatedUser = User(
      id: currentUser.id,
      email: currentUser.email,
      username: username ?? currentUser.username, // updated username
      gender: gender ?? currentUser.gender, // updated gender
      token: currentUser.token,
    );
    
    await StorageService.saveUser(updatedUser);
    return updatedUser;
  }

  /// Get verified devices
  static Future<Map<String, dynamic>> getDevices() async {
    final response = await ApiService.get(ApiConfig.devices);
    return ApiService.parseResponse(response);
  }

  /// Remove verified device
  static Future<void> removeDevice(String deviceId) async {
    final response = await ApiService.delete('${ApiConfig.devices}/$deviceId');
    if (response.statusCode != 200) {
      throw ApiException('Failed to remove device', response.statusCode);
    }
  }

  /// Check if user is logged in with valid token
  static Future<bool> isAuthenticated() async {
    final isLoggedIn = await StorageService.isLoggedIn();
    if (!isLoggedIn) return false;
    return await validateToken();
  }
}

class DeviceVerificationRequired implements Exception {
  final int userId;
  final String message;

  DeviceVerificationRequired(this.userId, this.message);

  @override
  String toString() => message;
}
