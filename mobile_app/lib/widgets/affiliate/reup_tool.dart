import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/affiliate_service.dart';

/// Reup tool panel - independent smart reup processing.
class ReupTool extends StatefulWidget {
  final Map<String, String> transforms;
  final List<dynamic> products;
  final String? selectedProductId;
  final Map<String, dynamic>? jobStatus;
  final VoidCallback? onBack;

  const ReupTool({
    super.key,
    required this.transforms,
    required this.products,
    this.selectedProductId,
    this.jobStatus,
    this.onBack,
  });

  @override
  State<ReupTool> createState() => _ReupToolState();
}

class _ReupToolState extends State<ReupTool> {
  Map<String, bool> _selectedTransforms = {};
  bool _reupProcessing = false;
  Map<String, dynamic>? _reupResult;
  String? _selectedVideoName;

  @override
  void initState() {
    super.initState();
    _selectedTransforms = {
      for (var key in widget.transforms.keys) key: ['metadata', 'mirror', 'zoom', 'color', 'speed', 'pitch', 'recode'].contains(key),
    };
  }

  Future<void> _pickAndReupVideo() async {
    File? file;
    String? sourcePath;
    String? productId;

    final product = _getSelectedProduct();
    final bool hasVideo = product != null && (product['video_urls'] as List?)?.isNotEmpty == true;
    final bool hasRendered = widget.jobStatus != null && widget.jobStatus!['status'] == 'done' && widget.jobStatus!['output_path'] != null;

    if (hasRendered) {
      sourcePath = widget.jobStatus!['output_path'];
      setState(() => _selectedVideoName = 'Rendered Video (Auto)');
    } else if (hasVideo) {
      productId = widget.selectedProductId;
      setState(() => _selectedVideoName = 'Source Video (Auto)');
    } else {
      // Pick video file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.first.path;
      if (filePath == null) return;

      file = File(filePath);
      setState(() {
        _selectedVideoName = result.files.first.name;
      });
    }

    setState(() {
      _reupProcessing = true;
      _reupResult = null;
    });

    // Get selected transforms
    final activeTransforms = _selectedTransforms.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (activeTransforms.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hãy chọn ít nhất 1 transform')),
        );
        setState(() => _reupProcessing = false);
      }
      return;
    }

    // Upload and process
    try {
      final uploadResult = await AffiliateService.smartReupVideo(
        videoFile: file,
        sourcePath: sourcePath,
        productId: productId,
        transforms: activeTransforms,
      );
      if (mounted) setState(() => _reupResult = uploadResult);
    } catch (e) {
      if (mounted) {
        setState(() => _reupResult = {'error': e.toString()});
      }
    } finally {
      if (mounted) setState(() => _reupProcessing = false);
    }
  }

  Map<String, dynamic>? _getSelectedProduct() {
    if (widget.selectedProductId == null) return null;
    for (var p in widget.products) {
      if (p['product_id'] == widget.selectedProductId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            if (widget.onBack != null)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
            const Icon(Icons.transform, size: 20),
            const SizedBox(width: 8),
            Text('Smart Reup', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),

        // Transform selection
        Text('Chọn transforms để áp dụng:', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: widget.transforms.entries.map((e) {
              return CheckboxListTile(
                title: Text(e.key),
                subtitle: Text(e.value, style: const TextStyle(fontSize: 12)),
                value: _selectedTransforms[e.key] ?? false,
                onChanged: (v) => setState(() => _selectedTransforms[e.key] = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              );
            }).toList(),
          ),
        ),
        const Divider(),

        // Selected video display
        if (_selectedVideoName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.video_file, size: 18),
                const SizedBox(width: 4),
                Expanded(child: Text(_selectedVideoName!, overflow: TextOverflow.ellipsis)),
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() => _selectedVideoName = null),
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _reupProcessing ? null : _pickAndReupVideo,
            icon: _reupProcessing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: Text(_reupProcessing ? 'Đang xử lý...' : 'Chọn Video để Smart Reup'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
          ),
        ),

        // Reup result
        if (_reupResult != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              color: _reupResult!['error'] != null
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _reupResult!['error'] != null ? '❌ Lỗi' : '✅ Hoàn tất!',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    if (_reupResult!['error'] != null)
                      Text(_reupResult!['error'])
                    else ...[
                      Text('Output: ${_reupResult!['output_path'] ?? 'N/A'}'),
                      if (_reupResult!['transforms_applied'] != null)
                        Text('Applied: ${(_reupResult!['transforms_applied'] as List).join(', ')}'),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
