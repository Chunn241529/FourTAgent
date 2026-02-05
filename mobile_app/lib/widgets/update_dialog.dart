import 'package:flutter/material.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({Key? key, required this.updateInfo}) : super(key: key);

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _status = '';

  Future<void> _handleUpdate() async {
    final downloadUrl = widget.updateInfo.downloadUrl;
    if (downloadUrl == null) {
      setState(() {
        _status = 'Không tìm thấy link tải cho hệ điều hành này';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _status = 'Đang tải xuống...';
    });

    // Download update
    final filePath = await UpdateService.downloadUpdate(downloadUrl);

    if (filePath == null || !mounted) {
      setState(() {
        _isDownloading = false;
        _status = 'Tải xuống thất bại';
      });
      return;
    }

    setState(() {
      _status = 'Đang cài đặt...';
    });

    // Install update (will restart app)
    final success = await UpdateService.installUpdate(filePath);

    if (!success && mounted) {
      setState(() {
        _isDownloading = false;
        _status = 'Cài đặt thất bại';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              children: [
                Icon(
                  Icons.system_update,
                  color: theme.colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Có Bản Cập Nhật Mới!',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Version info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Phiên bản mới:',
                    style: theme.textTheme.bodyLarge,
                  ),
                  Text(
                    'v${widget.updateInfo.version}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            
            // Changelog
            if (widget.updateInfo.changelog != null && 
                widget.updateInfo.changelog!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Thay đổi:',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    widget.updateInfo.changelog!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
            
            // Progress or status
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                style: theme.textTheme.bodySmall,
              ),
            ],
            
            const SizedBox(height: 24),
            
            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isDownloading) ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Để sau'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _handleUpdate,
                    icon: const Icon(Icons.download),
                    label: const Text('Cập nhật ngay'),
                  ),
                ] else ...[
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
