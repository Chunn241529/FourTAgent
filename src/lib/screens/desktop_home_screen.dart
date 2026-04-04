import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../models/conversation.dart';
import '../widgets/settings/settings_dialog.dart';
import 'ai_subtitle_screen.dart';
import 'tts_screen.dart';
import 'affiliate/affiliate_screen.dart';
import 'chat/chat_screen.dart';
import 'image_studio/image_studio_screen.dart';
import '../widgets/music/floating_music_player.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  int _selectedIndex = 0;
  bool _sidebarCollapsed = false;
  bool _showChats = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.autoUpdate) return;

    await Future.delayed(const Duration(seconds: 2));

    try {
      final updateInfo = await UpdateService.checkForUpdates();
      if (updateInfo != null && mounted) {
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

  void _navigate(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final screens = <Widget>[
      const ChatScreen(),
      const TtsScreen(),
      const AiSubtitleScreen(),
      const AffiliateScreen(),
      const ImageStudioScreen(),
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Row(
            children: [
              // ── Global Sidebar ──
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _sidebarCollapsed ? 60 : 280,
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: _sidebarCollapsed ? 60 : 280,
                    child: _sidebarCollapsed
                        ? _buildCollapsedSidebar(theme)
                        : _buildExpandedSidebar(theme),
                  ),
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: theme.dividerColor.withOpacity(0.15),
              ),
              // ── Content area ──
              Expanded(
                child: IndexedStack(index: _selectedIndex, children: screens),
              ),
            ],
          ),
          const FloatingMusicPlayer(),
        ],
      ),
    );
  }

  // ════════════════════════════════════════
  // EXPANDED SIDEBAR
  // ════════════════════════════════════════
  Widget _buildExpandedSidebar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark
        ? const Color(0xFF171717)
        : const Color(0xFFF9F9F9);
    final hoverColor = isDark
        ? Colors.white.withOpacity(0.07)
        : Colors.black.withOpacity(0.04);
    final selectedColor = isDark
        ? Colors.white.withOpacity(0.10)
        : Colors.black.withOpacity(0.07);
    final textColor = isDark
        ? Colors.white.withOpacity(0.85)
        : Colors.black.withOpacity(0.8);
    final subtleColor = isDark
        ? Colors.white.withOpacity(0.45)
        : Colors.black.withOpacity(0.4);

    return Container(
      decoration: BoxDecoration(color: surfaceColor),
      child: Column(
        children: [
          // ── Header: Menu + Logo + New chat ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 8, 4),
            child: Row(
              children: [
                _SidebarIconBtn(
                  icon: Icons.menu,
                  tooltip: 'Thu gọn',
                  onTap: () => setState(() => _sidebarCollapsed = true),
                  hoverColor: hoverColor,
                  iconColor: subtleColor,
                ),
                const SizedBox(width: 4),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/icon/icon.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Lumina',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                _SidebarIconBtn(
                  icon: Icons.edit_outlined,
                  tooltip: 'Cuộc trò chuyện mới',
                  onTap: () async {
                    _navigate(0);
                    await context.read<ChatProvider>().createConversation();
                  },
                  hoverColor: hoverColor,
                  iconColor: textColor,
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // ── Tool Menu Items ──
          _buildMenuItem(
            icon: Icons.search,
            label: 'Tìm kiếm',
            hoverColor: hoverColor,
            textColor: textColor,
            onTap: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
          _buildMenuItem(
            icon: Icons.image_outlined,
            label: 'Tạo ảnh',
            hoverColor: hoverColor,
            textColor: textColor,
            isActive: _selectedIndex == 4,
            onTap: () => _navigate(4),
          ),
          _buildMenuItem(
            icon: Icons.record_voice_over_outlined,
            label: 'TTS',
            hoverColor: hoverColor,
            textColor: textColor,
            isActive: _selectedIndex == 1,
            onTap: () => _navigate(1),
          ),
          _buildMenuItem(
            icon: Icons.translate,
            label: 'AI Translator',
            hoverColor: hoverColor,
            textColor: textColor,
            isActive: _selectedIndex == 2,
            onTap: () => _navigate(2),
          ),
          _buildMenuItem(
            icon: Icons.auto_awesome_outlined,
            label: 'Affiliate',
            hoverColor: hoverColor,
            textColor: textColor,
            isActive: _selectedIndex == 3,
            onTap: () => _navigate(3),
          ),

          const SizedBox(height: 4),

          // ── Search bar ──
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: _isSearching
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: TextStyle(fontSize: 13, color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Tìm kiếm cuộc trò chuyện...',
                        hintStyle: TextStyle(fontSize: 13, color: subtleColor),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: subtleColor,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: subtleColor,
                                ),
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.1),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.1),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary.withOpacity(0.5),
                          ),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.black.withOpacity(0.03),
                      ),
                      onChanged: (value) =>
                          setState(() => _searchQuery = value.toLowerCase()),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // ── "Your chats" ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 2),
            child: GestureDetector(
              onTap: () => setState(() => _showChats = !_showChats),
              child: Row(
                children: [
                  Text(
                    'Cuộc trò chuyện',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: subtleColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _showChats ? 0 : -0.25,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: subtleColor,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Conversation list ──
          if (_showChats)
            Expanded(
              child: Selector<ChatProvider, (List<Conversation>, int?)>(
                selector: (_, provider) =>
                    (provider.conversations, provider.currentConversation?.id),
                shouldRebuild: (prev, next) => prev != next,
                builder: (context, data, child) {
                  var conversations = data.$1;
                  final currentId = data.$2;

                  if (_searchQuery.isNotEmpty) {
                    conversations = conversations.where((c) {
                      final title = (c.title ?? '').toLowerCase();
                      return title.contains(_searchQuery);
                    }).toList();
                  }

                  if (conversations.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'Không tìm thấy kết quả'
                              : 'Chưa có cuộc trò chuyện',
                          style: TextStyle(fontSize: 13, color: subtleColor),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: conversations.length,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      final isSelected = currentId == conversation.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              _navigate(0);
                              context.read<ChatProvider>().selectConversation(
                                conversation,
                              );
                            },
                            hoverColor: hoverColor,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: isSelected
                                    ? selectedColor
                                    : Colors.transparent,
                              ),
                              child: Text(
                                conversation.title ?? 'Cuộc trò chuyện',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w500
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? textColor
                                      : textColor.withOpacity(0.85),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            )
          else
            const Spacer(),

          // ── Bottom section ──
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.06),
                ),
              ),
            ),
            child: Column(
              children: [
                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    final user = auth.user;
                    return _buildMenuItem(
                      icon: Icons.person_outline,
                      label: user?.fullName?.isNotEmpty == true
                          ? user!.fullName!
                          : (user?.username ?? 'Người dùng'),
                      hoverColor: hoverColor,
                      textColor: textColor,
                      onTap: () => showDialog(
                        context: context,
                        builder: (context) => const SettingsDialog(),
                      ),
                    );
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildMenuItem(
                        icon: Icons.settings_outlined,
                        label: 'Cài đặt',
                        hoverColor: hoverColor,
                        textColor: textColor,
                        compact: true,
                        onTap: () => showDialog(
                          context: context,
                          builder: (context) => const SettingsDialog(),
                        ),
                      ),
                    ),
                    _SidebarIconBtn(
                      icon: isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      tooltip: isDark ? 'Chế độ sáng' : 'Chế độ tối',
                      onTap: () => context.read<ThemeProvider>().toggleTheme(),
                      hoverColor: hoverColor,
                      iconColor: subtleColor,
                    ),
                    _SidebarIconBtn(
                      icon: Icons.logout,
                      tooltip: 'Đăng xuất',
                      onTap: () async {
                        final authProvider = context.read<AuthProvider>();
                        await authProvider.logout();
                      },
                      hoverColor: hoverColor,
                      iconColor: Colors.red.shade400,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════
  // COLLAPSED SIDEBAR
  // ════════════════════════════════════════
  Widget _buildCollapsedSidebar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark
        ? const Color(0xFF171717)
        : const Color(0xFFF9F9F9);
    final subtleColor = isDark
        ? Colors.white.withOpacity(0.45)
        : Colors.black.withOpacity(0.4);
    final hoverColor = isDark
        ? Colors.white.withOpacity(0.07)
        : Colors.black.withOpacity(0.04);
    final textColor = isDark
        ? Colors.white.withOpacity(0.85)
        : Colors.black.withOpacity(0.8);

    return Container(
      decoration: BoxDecoration(color: surfaceColor),
      child: Column(
        children: [
          const SizedBox(height: 14),
          _SidebarIconBtn(
            icon: Icons.menu,
            tooltip: 'Mở rộng',
            onTap: () => setState(() => _sidebarCollapsed = false),
            hoverColor: hoverColor,
            iconColor: textColor,
          ),
          const SizedBox(height: 4),
          _SidebarIconBtn(
            icon: Icons.edit_outlined,
            tooltip: 'Cuộc trò chuyện mới',
            onTap: () async {
              _navigate(0);
              await context.read<ChatProvider>().createConversation();
            },
            hoverColor: hoverColor,
            iconColor: textColor,
          ),
          const SizedBox(height: 8),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : Colors.black.withOpacity(0.06),
          ),
          const SizedBox(height: 8),
          _SidebarIconBtn(
            icon: Icons.search,
            tooltip: 'Tìm kiếm',
            onTap: () => setState(() {
              _sidebarCollapsed = false;
              _isSearching = true;
            }),
            hoverColor: hoverColor,
            iconColor: subtleColor,
          ),
          _SidebarIconBtn(
            icon: Icons.image_outlined,
            tooltip: 'Tạo ảnh',
            onTap: () => _navigate(4),
            hoverColor: hoverColor,
            iconColor: _selectedIndex == 4 ? textColor : subtleColor,
          ),
          _SidebarIconBtn(
            icon: Icons.record_voice_over_outlined,
            tooltip: 'TTS',
            onTap: () => _navigate(1),
            hoverColor: hoverColor,
            iconColor: _selectedIndex == 1 ? textColor : subtleColor,
          ),
          _SidebarIconBtn(
            icon: Icons.translate,
            tooltip: 'AI Translator',
            onTap: () => _navigate(2),
            hoverColor: hoverColor,
            iconColor: _selectedIndex == 2 ? textColor : subtleColor,
          ),
          _SidebarIconBtn(
            icon: Icons.auto_awesome_outlined,
            tooltip: 'Affiliate',
            onTap: () => _navigate(3),
            hoverColor: hoverColor,
            iconColor: _selectedIndex == 3 ? textColor : subtleColor,
          ),
          const Spacer(),
          _SidebarIconBtn(
            icon: Icons.settings_outlined,
            tooltip: 'Cài đặt',
            onTap: () => showDialog(
              context: context,
              builder: (context) => const SettingsDialog(),
            ),
            hoverColor: hoverColor,
            iconColor: subtleColor,
          ),
          _SidebarIconBtn(
            icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            tooltip: isDark ? 'Chế độ sáng' : 'Chế độ tối',
            onTap: () => context.read<ThemeProvider>().toggleTheme(),
            hoverColor: hoverColor,
            iconColor: subtleColor,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ════════════════════════════════════════
  // HELPER WIDGETS
  // ════════════════════════════════════════
  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required Color hoverColor,
    required Color textColor,
    required VoidCallback onTap,
    bool isActive = false,
    bool compact = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 0 : 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          hoverColor: hoverColor,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: compact ? 8 : 10,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isActive ? hoverColor : Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: textColor.withOpacity(isActive ? 1.0 : 0.7),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable icon button for sidebar
class _SidebarIconBtn extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;
  final Color hoverColor;
  final Color iconColor;

  const _SidebarIconBtn({
    required this.icon,
    this.tooltip,
    required this.onTap,
    required this.hoverColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        hoverColor: hoverColor,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, preferBelow: false, child: btn);
    }
    return btn;
  }
}
