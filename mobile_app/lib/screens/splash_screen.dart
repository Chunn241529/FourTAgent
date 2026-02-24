import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../main.dart'; // To access AuthWrapper
import '../auth_wrapper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  String _statusMessage = 'Connecting to server...';
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _checkConnection();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    // Try tunnel first
    bool tunnelSuccess = await _tryConnect(ApiConfig.tunnelUrl);
    
    if (_isDisposed) return;

    if (tunnelSuccess) {
      ApiConfig.baseUrl = ApiConfig.tunnelUrl;
      setState(() {
        _statusMessage = 'Connecting to server...';
      });
    } else {
      // Fallback to local
      setState(() {
        _statusMessage = 'Tunnel unreachable. Trying Local...';
      });
      
      bool localSuccess = await _tryConnect(ApiConfig.localUrl);
      
      if (_isDisposed) return;

      if (localSuccess) {
        ApiConfig.baseUrl = ApiConfig.localUrl;
        setState(() {
          _statusMessage = 'Connecting to server...';
        });
      } else {
        // Both failed - Default to Tunnel but maybe show error? 
        // For now, let's just default to tunnel (original behavior) or local?
        // Let's default to local as it's safer for dev if tunnel is down.
        ApiConfig.baseUrl = ApiConfig.localUrl;
        setState(() {
          _statusMessage = 'Connection failed. Defaulting to Local...';
        });
      }
    }

    // Small delay to show the status
    await Future.delayed(const Duration(milliseconds: 1200));
    if (_isDisposed) return;

    // Navigate to AuthWrapper
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
    );
  }

  Future<bool> _tryConnect(String url) async {
    try {
      // Just check root endpoint or simple health check
      // We'll use a short timeout (e.g., 3 seconds)
      print('Checking connection to: $url');
      final response = await http.get(Uri.parse('$url/')).timeout(
        const Duration(seconds: 3),
      );
      print('Response status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('Connection failed to $url: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo / Icon Animation
             ScaleTransition(
              scale: _animation,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surface,
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/icon/icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Title
            Text(
              'Lumina AI',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 16),
            // Status Message
            Text(
              _statusMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            // Loading Indicator
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
