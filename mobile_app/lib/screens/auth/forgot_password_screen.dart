import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/custom_text_field.dart';
import '../../widgets/common/custom_button.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    
    final success = await authProvider.forgotPassword(
      _emailController.text.trim(),
    );

    if (success && mounted) {
      setState(() => _emailSent = true);
    } else if (authProvider.error != null && mounted) {
      _showError(authProvider.error!);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quên mật khẩu'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _emailSent ? _buildSuccessView(theme) : _buildFormView(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 48),
          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withOpacity(0.1),
            ),
            child: Icon(
              Icons.lock_reset,
              size: 40,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),
          // Title
          Text(
            'Quên mật khẩu?',
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Nhập email của bạn để nhận link đặt lại mật khẩu',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          // Email field
          CustomTextField(
            controller: _emailController,
            label: 'Email',
            hint: 'Nhập email của bạn',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.email_outlined),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitRequest(),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Vui lòng nhập email';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return 'Email không hợp lệ';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),
          // Submit button
          Consumer<AuthProvider>(
            builder: (context, auth, _) => CustomButton(
              text: 'Gửi yêu cầu',
              isLoading: auth.isLoading,
              onPressed: _submitRequest,
            ),
          ),
          const SizedBox(height: 24),
          // Back to login
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Quay lại đăng nhập'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green.withOpacity(0.1),
          ),
          child: const Icon(
            Icons.mark_email_read,
            size: 50,
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Email đã được gửi!',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Vui lòng kiểm tra hộp thư của bạn và nhấp vào link để đặt lại mật khẩu.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _emailController.text,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
        CustomButton(
          text: 'Quay lại đăng nhập',
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => setState(() => _emailSent = false),
          child: const Text('Gửi lại email'),
        ),
      ],
    );
  }
}
