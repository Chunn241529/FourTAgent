import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings/settings_dialog.dart';
import 'ai_subtitle_screen.dart';
import 'tts_screen.dart';
import 'chat/chat_screen.dart';
import '../widgets/music/floating_music_player.dart';
import '../widgets/mac_dock.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  int _selectedIndex = 0; // Default to TTS (index 0)

  @override
  void initState() {
    super.initState();
    debugPrint('DesktopHomeScreen init: _selectedIndex = $_selectedIndex');
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    // Check settings first
    final settings = context.read<SettingsProvider>(); // Use read here as we don't need to listen to updates inside this async method's future execution flow usually, but access current value. Actually, if we want to be safe, read is fine.
    if (!settings.autoUpdate) return;

    // Wait a bit for UI to settle
    await Future.delayed(const Duration(seconds: 2));
    
    try {
      final updateInfo = await UpdateService.checkForUpdates();
      
      if (updateInfo != null && mounted) {
        // Show update dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => UpdateDialog(updateInfo: updateInfo),
        );
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
  }

  final List<Widget> _screens = const [
    TtsScreen(), // 0: TTS (Primary - default)
    AiSubtitleScreen(), // 1: Studio
    ChatScreen(), // 2: Chat
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Main content - Use SizedBox.expand as the base non-positioned child
          // to ensure the Stack fills the screen and provides constraints.
          SizedBox.expand(
            child: IndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),

          // macOS Style Dock
          MacDock(
            items: [
              DockItem(
                icon: Icons.record_voice_over_outlined,
                selectedIcon: Icons.record_voice_over,
                label: 'TTS',
                isSelected: _selectedIndex == 0,
                onTap: () => setState(() => _selectedIndex = 0),
              ),
              DockItem(
                icon: Icons.subtitles_outlined,
                selectedIcon: Icons.subtitles,
                label: 'Studio',
                isSelected: _selectedIndex == 1,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
              DockItem(
                icon: Icons.chat_bubble_outline,
                selectedIcon: Icons.chat_bubble,
                label: 'Chat',
                isSelected: _selectedIndex == 2,
                onTap: () => setState(() => _selectedIndex = 2),
              ),
            ],
            actionItems: [
              DockItem(
                icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                label: isDark ? 'Chế độ sáng' : 'Chế độ tối',
                onTap: () => context.read<ThemeProvider>().toggleTheme(),
              ),
              DockItem(
                icon: Icons.settings_outlined,
                label: 'Cài đặt',
                onTap: () => showDialog(
                  context: context,
                  builder: (context) => const SettingsDialog(),
                ),
              ),
              DockItem(
                icon: Icons.logout,
                label: 'Đăng xuất',
                color: theme.colorScheme.error,
                onTap: () async {
                  final authProvider = context.read<AuthProvider>();
                  await authProvider.logout();
                },
              ),
            ],
          ),

          const FloatingMusicPlayer(),
        ],
      ),
    );
  }
}
