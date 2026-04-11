import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/music_player_provider.dart';
import 'providers/canvas_provider.dart';
import 'providers/server_connection_provider.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/desktop_home_screen.dart';
import 'screens/splash_screen.dart';
import 'auth_wrapper.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize MediaKit for desktop support
  MediaKit.ensureInitialized();
  
  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const FourTChatApp());
}

/// Global key for showing SnackBars from anywhere safely
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class FourTChatApp extends StatefulWidget {
  const FourTChatApp({super.key});

  @override
  State<FourTChatApp> createState() => _FourTChatAppState();
}

class _FourTChatAppState extends State<FourTChatApp> with WidgetsBindingObserver {
  // Create provider instance here to keep a reference
  final _musicPlayerProvider = MusicPlayerProvider();
  final _serverConnectionProvider = ServerConnectionProvider();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Setup global API connection error listener
    ApiService.onConnectionError = () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _serverConnectionProvider.reportConnectionError();
      });
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _musicPlayerProvider.dispose();
    _serverConnectionProvider.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // App is closing/terminating
      debugPrint('App detached: Stopping music...');
      try {
        // Stop music directly using our reference
        // Pass clearQueue: true to ensure everything is reset
        _musicPlayerProvider.stop(clearQueue: true); 
      } catch (e) {
        debugPrint('Error stopping music on detach: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        // Use the existing instance via value/create. 
        // Since we manage its lifecycle in this State, we use ChangeNotifierProvider.value if possible, 
        // or create that returns it. But simply passing it to create: (_) => _musicPlayerProvider is fine 
        // provided we don't dispose it twice accidentally (MultiProvider usually disposes).
        // Better: Use ChangeNotifierProvider.value
        ChangeNotifierProvider.value(value: _musicPlayerProvider),
        ChangeNotifierProvider.value(value: _serverConnectionProvider),
        ChangeNotifierProvider(create: (_) => CanvasProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            title: 'Lumina AI',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const SplashScreen(),
            builder: (context, child) {
              return Stack(
                textDirection: TextDirection.ltr,
                children: [
                  if (child != null) child,
                  Consumer<ServerConnectionProvider>(
                    builder: (context, provider, _) {
                      if (provider.isConnected) return const SizedBox.shrink();
                      
                      final isDark = themeProvider.themeMode == ThemeMode.dark;
                      return Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.6),
                          child: Center(
                            child: Material(
                              color: Colors.transparent,
                              child: Container(
                                padding: const EdgeInsets.all(32),
                                margin: const EdgeInsets.symmetric(horizontal: 40),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    )
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: CircularProgressIndicator(strokeWidth: 4),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      'Mất kết nối máy chủ',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black87,
                                        fontFamily: 'Inter',
                                        decoration: TextDecoration.none,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Server đang khởi động lại hoặc có lỗi mạng.\nVui lòng đợi trong giây lát, hệ thống sẽ tự động kết nối lại khi đã sẵn sàng...',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isDark ? Colors.white70 : Colors.black54,
                                        fontFamily: 'Inter',
                                        height: 1.5,
                                        decoration: TextDecoration.none,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
