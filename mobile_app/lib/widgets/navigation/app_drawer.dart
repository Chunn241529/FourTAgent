import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/conversation.dart';
import '../../screens/auth/login_screen.dart';
import '../settings/settings_dialog.dart';
import '../../screens/desktop_home_screen.dart';

/// App drawer for navigation
class AppDrawer extends StatelessWidget {
  final Function(Conversation)? onConversationTap;
  final VoidCallback? onNewChat;

  const AppDrawer({
    super.key,
    this.onConversationTap,
    this.onNewChat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authProvider = context.watch<AuthProvider>();
    final chatProvider = context.watch<ChatProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.secondary,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lumina AI',
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          authProvider.user?.email ?? '',
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Theme toggle
                  IconButton(
                    onPressed: () => themeProvider.toggleTheme(),
                    icon: Icon(
                      themeProvider.isDark
                          ? Icons.light_mode
                          : Icons.dark_mode,
                    ),
                  ),
                ],
              ),
            ),
            // New chat button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onNewChat?.call();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Cuộc trò chuyện mới'),
                ),
              ),
            ),
            // Conversations list
            Expanded(
              child: chatProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : chatProvider.conversations.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 48,
                                color: theme.colorScheme.onSurface.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Chưa có cuộc trò chuyện nào',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: chatProvider.conversations.length,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemBuilder: (context, index) {
                            final conversation = chatProvider.conversations[index];
                            final isSelected = 
                                chatProvider.currentConversation?.id == conversation.id;
                            
                            return Dismissible(
                              key: Key('conv_${conversation.id}'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16),
                                color: theme.colorScheme.error,
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                ),
                              ),
                              onDismissed: (_) {
                                chatProvider.deleteConversation(conversation.id);
                              },
                              child: ListTile(
                                onTap: () {
                                  Navigator.pop(context);
                                  onConversationTap?.call(conversation);
                                },
                                selected: isSelected,
                                selectedTileColor: theme.colorScheme.primary.withOpacity(0.1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                leading: Icon(
                                  Icons.chat_bubble_outline,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface.withOpacity(0.5),
                                ),
                                title: Text(
                                  conversation.title ?? 'Cuộc trò chuyện mới',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  _formatDate(conversation.createdAt),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            );
                          },
                        ),
            ),
            // Bottom actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Column(
                children: [
                  ListTile(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (_) => const DesktopHomeScreen())
                      );
                    },
                    leading: const Icon(Icons.auto_awesome_motion),
                    title: const Text('AI Studio (TTS)'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  ListTile(
                    onTap: () {
                      Navigator.pop(context);
                      SettingsDialog.show(context);
                    },
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Cài đặt'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  ListTile(
                    onTap: () async {
                      await authProvider.logout();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    },
                    leading: Icon(
                      Icons.logout,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Đăng xuất',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateDay = DateTime(date.year, date.month, date.day);

    if (dateDay == today) {
      return 'Hôm nay';
    } else if (dateDay == yesterday) {
      return 'Hôm qua';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
