import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/chat_service.dart';
import '../../services/auth_service.dart';
import '../../screens/auth/login_screen.dart';

/// Settings popup dialog with 2-column layout
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const SettingsDialog(),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  int _selectedIndex = 0;
  bool _isDeleting = false;

  final List<_MenuItem> _menuItems = [
    _MenuItem(icon: Icons.settings_outlined, label: 'Tổng quát'),
    _MenuItem(icon: Icons.storage_outlined, label: 'Quản lý dữ liệu'),
    _MenuItem(icon: Icons.notifications_outlined, label: 'Thông báo'),
    _MenuItem(icon: Icons.person_outline, label: 'Tài khoản'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    
    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: screenSize.width * 0.85,
        height: screenSize.height * 0.75,
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 550),
        child: Row(
          children: [
            // Left sidebar menu
            Container(
              width: 180,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Close button
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      tooltip: 'Đóng',
                    ),
                  ),
                  // Menu items
                  ...List.generate(_menuItems.length, (index) {
                    final item = _menuItems[index];
                    final isSelected = _selectedIndex == index;
                    return _buildMenuItem(item, isSelected, index, theme, isDark);
                  }),
                ],
              ),
            ),
            // Right content
            Expanded(
              child: _buildContent(theme, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(_MenuItem item, bool isSelected, int index, ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected 
            ? (isDark ? Colors.white10 : Colors.black.withAlpha(13))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => setState(() => _selectedIndex = index),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(item.icon, size: 20, color: theme.colorScheme.onSurface.withAlpha(180)),
                const SizedBox(width: 10),
                Text(
                  item.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          Text(
            _menuItems[_selectedIndex].label,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          // Section content
          _buildSectionContent(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildSectionContent(ThemeData theme, bool isDark) {
    switch (_selectedIndex) {
      case 0:
        return _buildGeneralSection(theme, isDark);
      case 1:
        return _buildDataControlsSection(theme, isDark);
      case 2:
        return _buildNotificationsSection(theme, isDark);
      case 3:
        return _buildAccountSection(theme, isDark);
      default:
        return const SizedBox();
    }
  }

  // ===== GENERAL SECTION =====
  Widget _buildGeneralSection(ThemeData theme, bool isDark) {
    final themeProvider = context.watch<ThemeProvider>();
    final settings = context.watch<SettingsProvider>();
    
    return Column(
      children: [
        _SettingsTile(
          title: 'Giao diện',
          subtitle: _getThemeLabel(themeProvider.themeMode),
          onTap: () => _showThemePicker(themeProvider),
        ),
        _SettingsTile(
          title: 'Ngôn ngữ',
          subtitle: settings.language == 'vi' ? 'Tiếng Việt' : 'English',
          onTap: () => _showLanguagePicker(settings),
        ),
        _SettingsTile(
          title: 'Cỡ chữ',
          subtitle: _getFontSizeLabel(settings.fontScale),
          onTap: () => _showFontSizePicker(settings),
        ),
        _SettingsSwitch(
          title: 'Âm thanh',
          subtitle: 'Phát âm thanh khi gửi/nhận tin',
          value: settings.soundEnabled,
          onChanged: settings.setSoundEnabled,
        ),
      ],
    );
  }

  // ===== DATA CONTROLS SECTION =====
  Widget _buildDataControlsSection(ThemeData theme, bool isDark) {
    final settings = context.watch<SettingsProvider>();
    final chatProvider = context.read<ChatProvider>();
    
    return Column(
      children: [
        _SettingsSwitch(
          title: 'Cải thiện AI',
          subtitle: 'Cho phép sử dụng dữ liệu để cải thiện model',
          value: settings.improveModel,
          onChanged: settings.setImproveModel,
        ),
        _SettingsTile(
          title: 'Số cuộc trò chuyện',
          subtitle: '${chatProvider.conversations.length} cuộc trò chuyện',
        ),
        _SettingsTile(
          title: 'Xóa tất cả chat',
          trailing: _isDeleting 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : _ActionButton(
                label: 'Xóa hết',
                isDestructive: true,
                onTap: () => _confirmDeleteAllChats(chatProvider),
              ),
        ),
      ],
    );
  }

  // ===== NOTIFICATIONS SECTION =====
  Widget _buildNotificationsSection(ThemeData theme, bool isDark) {
    final settings = context.watch<SettingsProvider>();
    
    return Column(
      children: [
        _SettingsSwitch(
          title: 'Thông báo đẩy',
          subtitle: 'Nhận thông báo khi có tin nhắn mới',
          value: settings.pushNotifications,
          onChanged: settings.setPushNotifications,
        ),
        _SettingsSwitch(
          title: 'Thông báo email',
          subtitle: 'Nhận email về hoạt động quan trọng',
          value: settings.emailNotifications,
          onChanged: settings.setEmailNotifications,
        ),
        _SettingsSwitch(
          title: 'Âm thanh thông báo',
          subtitle: 'Phát âm thanh khi có thông báo',
          value: settings.soundNotifications,
          onChanged: settings.setSoundNotifications,
        ),
        _SettingsSwitch(
          title: 'Rung',
          subtitle: 'Rung khi có thông báo',
          value: settings.vibration,
          onChanged: settings.setVibration,
        ),
      ],
    );
  }

  // ===== ACCOUNT SECTION =====
  Widget _buildAccountSection(ThemeData theme, bool isDark) {
    final authProvider = context.watch<AuthProvider>();
    
    return Column(
      children: [
        _SettingsTile(
          title: 'Email',
          subtitle: authProvider.user?.email ?? 'Chưa đăng nhập',
        ),
        _SettingsTile(
          title: 'Tên hiển thị',
          subtitle: authProvider.user?.username ?? 'Chưa cập nhật',
          onTap: () => _showEditNameDialog(authProvider),
        ),
        _SettingsTile(
          title: 'Đổi mật khẩu',
          onTap: () => _showChangePasswordDialog(),
        ),
        _SettingsTile(
          title: 'Thiết bị đã đăng nhập',
          trailing: _ActionButton(
            label: 'Quản lý',
            onTap: () => _ManageDevicesDialog.show(context),
          ),
        ),
        const SizedBox(height: 24),
        _SettingsTile(
          title: 'Đăng xuất',
          titleColor: theme.colorScheme.primary,
          onTap: () => _confirmSignOut(authProvider),
        ),
        _SettingsTile(
          title: 'Xóa tài khoản',
          titleColor: theme.colorScheme.error,
          subtitle: 'Hành động không thể hoàn tác',
          onTap: () => _showDeleteAccountWarning(),
        ),
      ],
    );
  }

  // ===== HELPER METHODS =====
  String _getThemeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light: return 'Sáng';
      case ThemeMode.dark: return 'Tối';
      case ThemeMode.system: return 'Theo hệ thống';
    }
  }

  String _getFontSizeLabel(double scale) {
    if (scale <= 0.9) return 'Nhỏ';
    if (scale >= 1.1) return 'Lớn';
    return 'Trung bình';
  }

  void _showThemePicker(ThemeProvider themeProvider) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Chọn giao diện'),
        children: [
          _dialogOption('Sáng', () => themeProvider.setTheme(ThemeMode.light), ctx),
          _dialogOption('Tối', () => themeProvider.setTheme(ThemeMode.dark), ctx),
          _dialogOption('Theo hệ thống', () => themeProvider.setTheme(ThemeMode.system), ctx),
        ],
      ),
    );
  }

  void _showLanguagePicker(SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Chọn ngôn ngữ'),
        children: [
          _dialogOption('Tiếng Việt', () => settings.setLanguage('vi'), ctx),
          _dialogOption('English', () => settings.setLanguage('en'), ctx),
        ],
      ),
    );
  }

  void _showFontSizePicker(SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Chọn cỡ chữ'),
        children: [
          _dialogOption('Nhỏ', () => settings.setFontScale(0.85), ctx),
          _dialogOption('Trung bình', () => settings.setFontScale(1.0), ctx),
          _dialogOption('Lớn', () => settings.setFontScale(1.15), ctx),
        ],
      ),
    );
  }

  Widget _dialogOption(String label, VoidCallback onTap, BuildContext ctx) {
    return SimpleDialogOption(
      onPressed: () {
        onTap();
        Navigator.pop(ctx);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(label),
      ),
    );
  }

  void _confirmDeleteAllChats(ChatProvider chatProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa tất cả chat?'),
        content: const Text('Hành động này không thể hoàn tác. Tất cả cuộc trò chuyện sẽ bị xóa vĩnh viễn.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteAllChats(chatProvider);
            },
            child: Text('Xóa', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAllChats(ChatProvider chatProvider) async {
    setState(() => _isDeleting = true);
    
    try {
      // Delete all conversations via API
      await ChatService.deleteAllConversations();
      
      // Clear current conversation so chat screen closes
      chatProvider.clearCurrentConversation();
      
      // Reload conversations (should be empty now)
      await chatProvider.loadConversations();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa tất cả cuộc trò chuyện')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  void _showEditNameDialog(AuthProvider authProvider) {
    final controller = TextEditingController(text: authProvider.user?.username ?? '');
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên hiển thị'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Tên hiển thị',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await authProvider.updateProfile(username: controller.text.trim());
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(success ? 'Đã cập nhật tên' : 'Lỗi: ${authProvider.error}')),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentPw = TextEditingController();
    final newPw = TextEditingController();
    final confirmPw = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi mật khẩu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPw,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPw,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPw,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Xác nhận mật khẩu mới'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              if (newPw.text != confirmPw.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mật khẩu xác nhận không khớp')),
                );
                return;
              }
              Navigator.pop(ctx);
              final authProvider = context.read<AuthProvider>();
              final success = await authProvider.changePassword(currentPw.text, newPw.text);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(success ? 'Đã đổi mật khẩu' : 'Lỗi: ${authProvider.error}')),
                );
              }
            },
            child: const Text('Đổi mật khẩu'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountWarning() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa tài khoản?'),
        content: const Text(
          'Tất cả dữ liệu của bạn sẽ bị xóa vĩnh viễn. '
          'Hành động này KHÔNG THỂ hoàn tác.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showDeleteAccountDialog();
            },
            child: Text('Xóa tài khoản', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    final passwordController = TextEditingController();
    bool isLoading = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Xác nhận xóa tài khoản'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Vui lòng nhập mật khẩu để xác nhận.'),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: isLoading ? null : () async {
                setState(() {
                  isLoading = true;
                  error = null;
                });
                
                final authProvider = context.read<AuthProvider>();
                final success = await authProvider.deleteAccount(passwordController.text);
                
                if (!mounted) return;
                
                if (success) {
                   Navigator.pop(ctx); // Close password dialog
                   Navigator.pop(context); // Close settings dialog
                   // AuthWrapper handles navigation
                } else {
                   setState(() {
                     isLoading = false;
                     error = authProvider.error ?? 'Mật khẩu không đúng';
                   });
                }
              },
              child: isLoading 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                  : Text('Xóa vĩnh viễn', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSignOut(AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text('Bạn có chắc muốn đăng xuất khỏi tài khoản?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx); // Close confirm dialog
              Navigator.pop(context); // Close settings dialog
              await authProvider.logout();
              
              if (!mounted) return;
              
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }
}

// ===== HELPER WIDGETS =====
class _MenuItem {
  final IconData icon;
  final String label;
  const _MenuItem({required this.icon, required this.label});
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.title,
    this.subtitle,
    this.titleColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(color: titleColor),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(150),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (trailing == null && onTap != null)
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurface.withAlpha(100)),
          ],
        ),
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitch({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isDestructive ? theme.colorScheme.error : theme.colorScheme.onSurface;
    
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(128)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(label),
    );
  }
}

class _ManageDevicesDialog extends StatefulWidget {
  const _ManageDevicesDialog();

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const _ManageDevicesDialog(),
    );
  }

  @override
  State<_ManageDevicesDialog> createState() => _ManageDevicesDialogState();
}

class _ManageDevicesDialogState extends State<_ManageDevicesDialog> {
  late Future<Map<String, dynamic>> _devicesFuture;
  
  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  void _loadDevices() {
    setState(() {
      _devicesFuture = AuthService.getDevices();
    });
  }

  Future<void> _removeDevice(String deviceId) async {
    try {
      await AuthService.removeDevice(deviceId);
      _loadDevices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa thiết bị')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thiết bị đã đăng nhập'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _devicesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Lỗi tải danh sách: ${snapshot.error}'));
            }
            
            final data = snapshot.data!;
            final devices = List<Map<String, dynamic>>.from(data['verified_devices'] ?? []);
            final currentId = data['current_device_id'];
            
            if (devices.isEmpty) {
              return const Center(child: Text('Không có thiết bị nào'));
            }
            
            return ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                final id = device['device_id'];
                final isCurrent = id == currentId || device['is_current'] == true;
                final name = device['device_name'] ?? device['device_info']?['hostname'] ?? 'Thiết bị';
                
                return ListTile(
                  leading: Icon(
                    isCurrent ? Icons.phone_android : Icons.devices_other,
                    color: isCurrent ? Theme.of(context).colorScheme.primary : null,
                  ),
                  title: Text(
                    name,
                    style: isCurrent ? const TextStyle(fontWeight: FontWeight.bold) : null,
                  ),
                  subtitle: Text('ID: ${id.toString().substring(0, 8)}...'),
                  trailing: isCurrent 
                      ? const Text('Hiện tại', style: TextStyle(fontSize: 12)) 
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _removeDevice(id),
                        ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
      ],
    );
  }
}
