/// API Configuration for FourT Chat App
class ApiConfig {
  // Change this to your backend URL
  // For web: http://localhost:8000
  // For Android emulator: http://10.0.2.2:8000
  // For physical device: use your local IP or ngrok URL
  static const String baseUrl = 'http://localhost:8000';
  
  // Auth endpoints (prefix: /auth)
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String verify = '/auth/verify';
  static const String forgetPassword = '/auth/forgetpw';
  static const String resetPassword = '/auth/reset-password';
  static const String validateToken = '/auth/validate-token';
  static const String devices = '/auth/devices';
  static const String changePassword = '/auth/change-password';
  static const String profile = '/auth/profile';
  static const String resendCode = '/auth/resend-code';
  static const String deleteAccount = '/auth/delete-account';
  
  // Conversations endpoints
  static const String conversations = '/conversations';
  
  // Messages endpoints
  static const String messages = '/messages';
  
  // Chat endpoint
  static const String chat = '/send';
  
  // Feedback endpoint
  static const String feedback = '/feedback';
}
