import 'dart:ui';
import 'package:flutter/material.dart';

/// A professional download progress dialog
class DownloadProgressDialog extends StatefulWidget {
  final String filename;
  final Future<String> downloadTask;
  final VoidCallback? onSuccess;
  final VoidCallback? onError;

  const DownloadProgressDialog({
    super.key,
    required this.filename,
    required this.downloadTask,
    this.onSuccess,
    this.onError,
  });

  /// Show the dialog and handle download
  static Future<void> show({
    required BuildContext context,
    required String filename,
    required Future<String> downloadTask,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (ctx) => DownloadProgressDialog(
        filename: filename,
        downloadTask: downloadTask,
      ),
    );
  }

  @override
  State<DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<DownloadProgressDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  String _status = 'Đang trích xuất video...';
  bool _isDone = false;
  bool _hasError = false;
  String? _savedPath;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _animationController.forward();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      setState(() => _status = 'Đang tải về máy...');
      final path = await widget.downloadTask;
      if (mounted) {
        setState(() {
          _savedPath = path;
          _isDone = true;
          _status = 'Tải xuống hoàn tất';
        });
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Đã lưu: $path')),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _status = 'Lỗi: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.05),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 30,
                      spreadRadius: -5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon Container
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _isDone
                            ? Colors.green.withOpacity(0.1)
                            : _hasError
                            ? Colors.red.withOpacity(0.1)
                            : theme.colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _isDone
                                ? Colors.green.withOpacity(0.2)
                                : (_hasError
                                      ? Colors.red.withOpacity(0.2)
                                      : theme.colorScheme.primary.withOpacity(
                                          0.2,
                                        )),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isDone
                            ? Icons.check_circle_rounded
                            : _hasError
                            ? Icons.error_rounded
                            : Icons.cloud_download_rounded,
                        size: 40,
                        color: _isDone
                            ? Colors.green
                            : _hasError
                            ? Colors.red
                            : theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Filename
                    Text(
                      widget.filename,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Status
                    Text(
                      _status,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _hasError
                            ? Colors.red
                            : _isDone
                            ? Colors.green
                            : theme.colorScheme.onSurface.withOpacity(0.5),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    if (!_isDone && !_hasError) ...[
                      const SizedBox(height: 24),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          backgroundColor: theme.colorScheme.primary
                              .withOpacity(0.1),
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],

                    if (_isDone && _savedPath != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.black.withOpacity(0.2)
                              : Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.onSurface.withOpacity(
                              0.05,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.video_library_rounded,
                              size: 14,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _savedPath!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.7),
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_hasError) ...[
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Đóng'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.withOpacity(0.1),
                          foregroundColor: Colors.red,
                          elevation: 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
