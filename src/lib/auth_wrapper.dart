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
          return const DesktopHomeScreen(); 
        }

        debugPrint('AuthWrapper: Not authenticated. Showing LoginScreen');
        return const LoginScreen();
      },
    );
  }
}
