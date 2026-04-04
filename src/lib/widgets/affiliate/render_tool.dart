import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/settings_provider.dart';
import '../../services/affiliate_service.dart';
import '../../services/cloud_file_service.dart';

/// Render tool panel - independent video rendering.
class RenderTool extends StatefulWidget {
  final List<dynamic> products;
  final String? selectedProductId;
  final Map<String, dynamic>? generatedScript;
  final Map<String, dynamic>? jobStatus;
  final VoidCallback? onBack;

  const RenderTool({
    super.key,
    required this.products,
    this.selectedProductId,
    this.generatedScript,
    this.jobStatus,
    this.onBack,
  });

  @override
  State<RenderTool> createState() => _RenderToolState();
}

class _RenderToolState extends State<RenderTool> {
  bool _useTts = false;
  String? _activeJobId;
  Map<String, dynamic>? _jobStatus;
  Timer? _pollTimer;
  bool _isAiVideoJob = false;
  String? _activeApiKey;
  String? _uploadedModelUrl;
  bool _uploadingModel = false;

  @override
  void initState() {
    super.initState();
    _jobStatus = widget.jobStatus;
    if (_jobStatus != null && _jobStatus!['job_id'] != null) {
      _activeJobId = _jobStatus!['job_id'];
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final status = _isAiVideoJob && _activeApiKey != null
            ? await AffiliateService.checkAiVideoStatus(jobId: jobId, apiKey: _activeApiKey!)
            : await AffiliateService.getJobStatus(jobId);
        if (mounted) {
          setState(() => _jobStatus = status);
          if (status['status'] == 'done' || status['status'] == 'success' || status['status'] == 'failed') {
            timer.cancel();
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _startRender() async {
    final scriptText = widget.generatedScript?['script']?['full_script'] ??
        widget.generatedScript?['raw_text'] ??
        '';
    try {
      final jobId = await AffiliateService.startRenderVideo(
        productId: widget.selectedProductId!,
        scriptText: scriptText,
        useTts: _useTts,
      );
      setState(() {
        _activeJobId = jobId;
        _jobStatus = {'status': 'pending', 'progress': 0};
      });
      _startPolling(jobId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Render error: $e')),
        );
      }
    }
  }

  void _showAiVideoDialog(String apiKey) {
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng vào Cài đặt > Video AI để nhập API Key trước khi thử lại')),
      );
      return;
    }

    final prompt = widget.generatedScript?['script']?['ai_video_prompt'] ?? 'Cinematic 4k high detail';
    String selectedModel = 'kling';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Bắt đầu Render AI Video'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Chọn Model AI Video:'),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: selectedModel,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'kling', child: Text('Kling AI')),
                  DropdownMenuItem(value: 'veo', child: Text('Google Veo')),
                  DropdownMenuItem(value: 'wan', child: Text('Wan Video')),
                ],
                onChanged: (val) {
                  setState(() => selectedModel = val!);
                },
              ),
              const SizedBox(height: 16),
              const Text('Ảnh người mẫu (Tùy chọn):'),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _uploadedModelUrl != null ? 'Đã tải lên ảnh mẫu' : 'Chưa chọn ảnh',
                      style: TextStyle(
                        fontSize: 12,
                        color: _uploadedModelUrl != null ? Colors.green : Colors.grey,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _uploadingModel
                        ? null
                        : () async {
                            setState(() => _uploadingModel = true);
                            try {
                              final result = await FilePicker.platform.pickFiles(type: FileType.image);
                              if (result != null && result.files.single.path != null) {
                                final file = File(result.files.single.path!);
                                final res = await AffiliateService.uploadModelImage(file);
                                if (mounted) {
                                  setState(() => _uploadedModelUrl = res['url']);
                                }
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text('Upload error: $e')),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _uploadingModel = false);
                              }
                            }
                          },
                    icon: _uploadingModel
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload, size: 16),
                    label: const Text('Tải lên'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Prompt (Tự động tạo từ bước trước):'),
              const SizedBox(height: 4),
              Text(
                prompt,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _startAiVideoRender(apiKey, selectedModel, prompt);
              },
              child: const Text('Khởi tạo Job'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startAiVideoRender(String apiKey, String model, String prompt) async {
    try {
      String? imageUrl;
      final product = widget.products.firstWhere(
        (p) => p['product_id'] == widget.selectedProductId,
        orElse: () => null,
      );
      if (product != null && product['image_urls'] != null && (product['image_urls'] as List).isNotEmpty) {
        imageUrl = product['image_urls'][0];
      }

      final result = await AffiliateService.generateAiVideo(
        prompt: prompt,
        imageUrl: imageUrl,
        modelImageUrl: _uploadedModelUrl,
        model: model,
        apiKey: apiKey,
      );

      final jobId = result['job_id'];
      if (jobId != null) {
        setState(() {
          _activeJobId = jobId;
          _isAiVideoJob = true;
          _activeApiKey = apiKey;
          _jobStatus = {'status': 'pending', 'progress': 0};
        });
        _startPolling(jobId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI Video error: $e')),
        );
      }
    }
  }

  Future<void> _downloadVideo() async {
    if (_activeJobId == null) return;
    
    try {
      String cloudPath;
      String filename;
      
      if (_isAiVideoJob && _jobStatus?['result_url'] != null) {
        // AI video - result_url might be a local path or cloud path
        final resultUrl = _jobStatus!['result_url'] as String;
        if (resultUrl.startsWith('http')) {
          // Direct URL - open in browser
          final uri = Uri.parse(resultUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return;
        }
        // It's a local path, use the download endpoint
        cloudPath = resultUrl;
        filename = '${_activeJobId}_ai.mp4';
      } else if (_jobStatus?['output_path'] != null) {
        // Regular render job with cloud path
        cloudPath = _jobStatus!['output_path'] as String;
        filename = cloudPath.split('/').last;
      } else {
        // Fall back to direct URL
        final downloadUrl = '${AffiliateService.baseUrl}/affiliate/jobs/$_activeJobId/download';
        final uri = Uri.parse(downloadUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return;
      }
      
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Đang tải video...'),
            ],
          ),
        ),
      );
      
      final localPath = await CloudFileService.downloadBinaryFile(cloudPath, filename);
      
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã tải: $localPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading if still open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải video: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();
    final product = widget.selectedProductId != null
        ? widget.products.cast<Map<String, dynamic>?>().firstWhere(
              (p) => p?['product_id'] == widget.selectedProductId,
              orElse: () => null,
            )
        : null;
    final bool hasVideo = product != null && (product['video_urls'] as List?)?.isNotEmpty == true;

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
            const Icon(Icons.movie_creation, size: 20),
            const SizedBox(width: 8),
            Text('Render', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),

        if (hasVideo) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.video_library, color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sản phẩm này là Video Gốc.\nBạn có thể bật TTS để thêm lồng tiếng/sub vào video gốc.',
                    style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // TTS Toggle
        SwitchListTile(
          title: const Text('Sử dụng Voice (TTS)'),
          subtitle: const Text('Bật để thêm giọng đọc vào video'),
          value: _useTts,
          onChanged: (v) => setState(() => _useTts = v),
          contentPadding: EdgeInsets.zero,
        ),
        const Divider(),
        const SizedBox(height: 8),

        // Render buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.selectedProductId == null || widget.generatedScript == null
                    ? null
                    : _startRender,
                icon: const Icon(Icons.play_arrow),
                label: Text(hasVideo && !_useTts ? 'Chuyển Video Gốc' : 'Bắt đầu Render'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.tertiary,
                  foregroundColor: theme.colorScheme.onTertiary,
                  padding: const EdgeInsets.all(16),
                ),
                onPressed: () => _showAiVideoDialog(settings.aiVideoApiKey),
                icon: const Icon(Icons.movie_creation),
                label: const Text('AI Video'),
              ),
            ),
          ],
        ),

        if (widget.selectedProductId == null || widget.generatedScript == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Cần chọn sản phẩm và tạo script trước',
              style: TextStyle(color: theme.hintColor, fontSize: 12),
            ),
          ),
        const SizedBox(height: 16),

        // Job status
        if (_jobStatus != null)
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildStatusIcon(_jobStatus!['status']),
                        const SizedBox(width: 8),
                        Text(
                          'Job: $_activeJobId',
                          style: theme.textTheme.titleSmall,
                        ),
                        const Spacer(),
                        // Download button when done
                        if (_jobStatus!['status'] == 'done' && _activeJobId != null)
                          IconButton(
                            icon: const Icon(Icons.download),
                            tooltip: 'Tải Video',
                            onPressed: () => _downloadVideo(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (_jobStatus!['progress'] ?? 0) / 100,
                    ),
                    const SizedBox(height: 4),
                    Text('${_jobStatus!['progress'] ?? 0}% • ${_jobStatus!['status']}'),
                    if (_jobStatus!['error'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _jobStatus!['error'],
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    // Show video preview URL when done
                    if (_jobStatus!['status'] == 'done') ...[
                      if (_jobStatus!['output_path'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Video: ${_jobStatus!['output_path']}',
                            style: TextStyle(fontSize: 11, color: theme.hintColor),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (_jobStatus!['result_url'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'AI Video: ${_jobStatus!['result_url']}',
                            style: TextStyle(fontSize: 11, color: theme.hintColor),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          )
        else
          const Spacer(),
      ],
    );
  }

  Widget _buildStatusIcon(String? status) {
    switch (status) {
      case 'done':
        return const Icon(Icons.check_circle, color: Colors.green);
      case 'failed':
        return const Icon(Icons.error, color: Colors.red);
      case 'processing':
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      default:
        return const Icon(Icons.schedule, color: Colors.orange);
    }
  }
}
