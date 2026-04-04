import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/desktop_home_screen.dart';
import 'widgets/common/loading_indicator.dart';

/// Wrapper to check authentication state
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        Widget child;
        // Show loading only during initial auth check (app startup)
        if (authProvider.isInitializing) {
          debugPrint('AuthWrapper: Initializing... Showing LoadingIndicator');
          child = const Scaffold(
            key: ValueKey('loading'),
            body: Center(
              child: LoadingIndicator(message: 'Đang tải...'),
            ),
          );
        } else if (authProvider.isAuthenticated) {
          // Navigate based on auth state
          debugPrint('AuthWrapper: Authenticated! Removing LoadingIndicator, showing DesktopHomeScreen');
          child = const DesktopHomeScreen(key: ValueKey('home')); 
        } else {
          debugPrint('AuthWrapper: Not authenticated. Showing LoginScreen');
          child = const LoginScreen(key: ValueKey('login'));
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: child,
        );
      },
    );
  }
}
