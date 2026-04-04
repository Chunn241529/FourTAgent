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
  String _status = 'Đang kết nối...';
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
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _animationController.forward();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      setState(() => _status = 'Đang tải xuống...');
      final path = await widget.downloadTask;
      if (mounted) {
        setState(() {
          _savedPath = path;
          _isDone = true;
          _status = 'Hoàn tất!';
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
                  Expanded(
                    child: Text('Đã lưu: $path'),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade600,
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
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _isDone
                        ? Colors.green.shade50
                        : _hasError
                            ? Colors.red.shade50
                            : Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isDone
                        ? Icons.check_circle
                        : _hasError
                            ? Icons.error
                            : Icons.downloading,
                    size: 40,
                    color: _isDone
                        ? Colors.green
                        : _hasError
                            ? Colors.red
                            : Colors.blue,
                  ),
                ),
                const SizedBox(height: 20),

                // Filename
                Text(
                  widget.filename,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Status
                Text(
                  _status,
                  style: TextStyle(
                    color: _hasError
                        ? Colors.red
                        : _isDone
                            ? Colors.green
                            : Colors.grey.shade600,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),

                if (!_isDone && !_hasError) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ],

                if (_isDone && _savedPath != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.folder, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _savedPath!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
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
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Đóng'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
