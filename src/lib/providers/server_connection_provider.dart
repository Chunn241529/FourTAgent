import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ServerConnectionProvider with ChangeNotifier {
  bool _isConnected = true;
  Timer? _pingTimer;

  bool get isConnected => _isConnected;

  void reportConnectionError() {
    if (_isConnected) {
      _isConnected = false;
      notifyListeners();
      _startPinging();
    }
  }

  void _startPinging() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        // Use a lightweight endpoint to check if server is back up
        // /health or /status. If it's 401, that's fine, server is up.
        // We bypass ApiService.get directly to avoid triggering more connection error callbacks
        // but we can just use a raw http call to be safe from interceptors.
        
        final uri = Uri.parse('${ApiConfig.baseUrl}/health'); 
        final response = await http.get(uri).timeout(const Duration(seconds: 2));
        
        if (response.statusCode >= 200 && response.statusCode < 505) {
          // If we reach here, server is up (even if 4xx or 500 error from logic, network is up)
          _isConnected = true;
          notifyListeners();
          timer.cancel();
        }
      } catch (e) {
        // Still down
      }
    });
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }
}
