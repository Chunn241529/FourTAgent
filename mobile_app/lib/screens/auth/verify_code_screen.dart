import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/custom_button.dart';
import '../chat/conversation_list_screen.dart';
import '../../widgets/common/custom_snackbar.dart';

class VerifyCodeScreen extends StatefulWidget {
  final int userId;
  final String? email;

  const VerifyCodeScreen({
    super.key,
    required this.userId,
    this.email,
  });

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || code.length != 6) {
      setState(() => _errorMessage = 'Vui lòng nhập mã 6 số');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.verifyDevice(widget.userId, code);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ConversationListScreen()),
        (route) => false,
      );
    } else {
      setState(() => _errorMessage = authProvider.error ?? 'Mã xác minh không đúng');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Xác minh thiết bị'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              // Icon
              Icon(
                Icons.security,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              // Title
              Text(
                'Nhập mã xác minh',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Description
              Text(
                'Chúng tôi đã gửi mã xác minh 6 số đến email${widget.email != null ? '\n${widget.email}' : ' của bạn'}',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // Error message
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.error.withOpacity(0.5)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              // Code input
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 32, letterSpacing: 12),
                decoration: InputDecoration(
                  hintText: '000000',
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onSubmitted: (_) => _verifyCode(),
              ),
              const SizedBox(height: 24),
              // Verify button
              CustomButton(
                text: 'Xác minh',
                isLoading: _isLoading,
                onPressed: _verifyCode,
              ),
              const SizedBox(height: 16),
              // Resend code
              TextButton(
                onPressed: _isLoading ? null : _resendCode,
                child: const Text('Gửi lại mã'),
              ),
            ],
          ),
        ),
      ),
      ),
    ),
  );
}

  void _resendCode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.resendCode(widget.userId);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      CustomSnackBar.showSuccess(context, 'Đã gửi lại mã xác minh');
    } else {
      setState(() => _errorMessage = authProvider.error ?? 'Gửi lại mã thất bại');
    }
  }
}
