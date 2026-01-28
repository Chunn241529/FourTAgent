import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/music_player_provider.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/desktop_home_screen.dart';
import 'widgets/common/loading_indicator.dart';

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

class FourTChatApp extends StatefulWidget {
  const FourTChatApp({super.key});

  @override
  State<FourTChatApp> createState() => _FourTChatAppState();
}

class _FourTChatAppState extends State<FourTChatApp> with WidgetsBindingObserver {
  // Create provider instance here to keep a reference
  final _musicPlayerProvider = MusicPlayerProvider();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _musicPlayerProvider.dispose();
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
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Lumina AI',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}

/// Wrapper to check authentication state
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        // Show loading only during initial auth check (app startup)
        if (authProvider.isInitializing) {
          debugPrint('AuthWrapper: Initializing... Showing LoadingIndicator');
          return const Scaffold(
            body: Center(
              child: LoadingIndicator(message: 'Đang tải...'),
            ),
          );
        }

        // Navigate based on auth state
        if (authProvider.isAuthenticated) {
          debugPrint('AuthWrapper: Authenticated! Removing LoadingIndicator, showing DesktopHomeScreen');
          return DesktopHomeScreen(key: UniqueKey()); 
        }

        debugPrint('AuthWrapper: Not authenticated. Showing LoginScreen');
        return const LoginScreen();
      },
    );
  }
}
