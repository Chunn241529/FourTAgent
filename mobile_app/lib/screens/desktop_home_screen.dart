import 'package:flutter/material.dart';
import 'ai_subtitle_screen.dart';
import 'tts_screen.dart';
import 'chat/chat_screen.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  int _selectedIndex = 1; // Default to TTS (index 1)

  final List<Widget> _screens = const [
    ChatScreen(),      // 0: Chat (Secondary)
    TtsScreen(),       // 1: TTS (Primary - default)
    AiSubtitleScreen(),// 2: AI Subtitle
  ];

  @override
  Widget build(BuildContext context) {
    // Ensure we have providers if needed.
    // Ideally ChatProvider is provided above MaterialApp or this screen.
    
    return Scaffold(
      body: Row(
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
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: Text('Chat'),
              ),
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
            ],
            leading: const Column(
              children: [
                SizedBox(height: 16),
                Icon(Icons.auto_awesome, size: 32),
                SizedBox(height: 16),
              ],
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Main content - full width
          Expanded(
            child: _screens[_selectedIndex],
          ),
        ],
      ),
    );
  }
}
