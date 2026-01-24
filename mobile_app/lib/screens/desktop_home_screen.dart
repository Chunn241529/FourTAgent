import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/settings/settings_dialog.dart';
import 'ai_subtitle_screen.dart';
import 'tts_screen.dart';
import 'chat/chat_screen.dart';
import '../widgets/music/floating_music_player.dart';
import '../providers/music_player_provider.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  int _selectedIndex = 0; // Default to TTS (index 0)

  final List<Widget> _screens = const [
    TtsScreen(),       // 0: TTS (Primary - default)
    AiSubtitleScreen(),// 1: Studio
    ChatScreen(),      // 2: Chat
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (int index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                },
                labelType: NavigationRailLabelType.all,
                destinations: const <NavigationRailDestination>[
                  NavigationRailDestination(
                    icon: Icon(Icons.record_voice_over_outlined),
                    selectedIcon: Icon(Icons.record_voice_over),
                    label: Text('TTS'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.subtitles_outlined),
                    selectedIcon: Icon(Icons.subtitles),
                    label: Text('Studio'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.chat_bubble_outline),
                    selectedIcon: Icon(Icons.chat_bubble),
                    label: Text('Chat'),
                  ),
                ],
                leading: const Column(
                  children: [
                    SizedBox(height: 16),
                    Icon(Icons.auto_awesome, size: 32),
                    SizedBox(height: 16),
                  ],
                ),
                trailing: Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Theme toggle
                      IconButton(
                        icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                        tooltip: isDark ? 'Chế độ sáng' : 'Chế độ tối',
                        onPressed: () {
                          context.read<ThemeProvider>().toggleTheme();
                        },
                      ),
                      const SizedBox(height: 8),
                      // Settings
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: 'Cài đặt',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => const SettingsDialog(),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      // Logout
                      IconButton(
                        icon: Icon(Icons.logout, color: theme.colorScheme.error),
                        tooltip: 'Đăng xuất',
                        onPressed: () async {
                          final authProvider = context.read<AuthProvider>();
                          await authProvider.logout();
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              // Main content - IndexedStack preserves state of all screens
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: _screens,
                ),
              ),
            ],
          ),
          const FloatingMusicPlayer(),
        ],
      ),
    );
  }
}
