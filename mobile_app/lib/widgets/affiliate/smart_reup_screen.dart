import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/affiliate_service.dart';
import '../../services/cloud_file_service.dart';
import '../../widgets/file_viewer_dialog.dart';

/// Smart Reup Douyin screen - paste Douyin URL or upload local video.
class SmartReupScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const SmartReupScreen({super.key, this.onBack});

  @override
  State<SmartReupScreen> createState() => _SmartReupScreenState();
}

class _SmartReupScreenState extends State<SmartReupScreen> {
  final _urlController = TextEditingController();

  // Input
  String? _url;
  File? _videoFile;

  // Transforms
  bool _stripMetadata = true;
  bool _mirror = true;
  bool _flipH = false;
  bool _zoom = true;
  bool _color = true;
  bool _noise = false;
  bool _recode = false;
  bool _stripAudio = true;
  bool _speed = true;
  bool _pitch = false;
  bool _trimEnd = true;

  // Audio mode
  String _audioMode = 'strip';  // 'strip' | 'shift'

  // Logo removal
  String _logoRemoval = 'none';  // 'none' | 'manual' | 'ai'

  // Manual logo crop settings
  double _logoCropTop = 0.0;
  double _logoCropRight = 15.0;
  double _logoCropBottom = 8.0;
  double _logoCropLeft = 0.0;

  // Job state
  bool _isProcessing = false;
  String? _activeJobId;
  Map<String, dynamic>? _jobStatus;
  Timer? _pollTimer;

  @override
  void dispose() {
    _urlController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final status = await AffiliateService.getJobStatus(jobId);
        if (mounted) {
          setState(() => _jobStatus = status);
          if (status['status'] == 'done' || status['status'] == 'failed') {
            timer.cancel();
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.video);
      if (result != null && result.files.single.path != null) {
        setState(() {
          _videoFile = File(result.files.single.path!);
          _url = null;
          _urlController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking video: $e')),
        );
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _url = data.text;
        _urlController.text = data.text!;
        _videoFile = null;
      });
    }
  }

  Future<void> _startSmartReup() async {
    if (_url == null && _videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập URL hoặc chọn file video')),
      );
      return;
    }

    final transforms = <String>[];
    if (_stripMetadata) transforms.add('metadata');
    if (_mirror) transforms.add('mirror');
    if (_flipH) transforms.add('flip_h');
    if (_zoom) transforms.add('zoom');
    if (_color) transforms.add('color');
    if (_noise) transforms.add('noise');
    if (_recode) transforms.add('recode');
    if (_stripAudio) transforms.add('strip_audio');
    if (_speed) transforms.add('speed');
    if (_pitch) transforms.add('pitch');
    if (_trimEnd) transforms.add('trim_end');

    try {
      final jobId = await AffiliateService.smartReupDouyin(
        url: _url,
        videoFile: _videoFile,
        transforms: transforms,
        audioMode: _audioMode,
        logoRemoval: _logoRemoval,
      );

      setState(() {
        _activeJobId = jobId;
        _isProcessing = true;
        _jobStatus = {'status': 'pending', 'progress': 0};
      });
      _startPolling(jobId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Smart Reup error: $e')),
        );
      }
    }
  }

  String _getStageText() {
    final stages = _jobStatus?['stages'] as List? ?? [];
    final currentStage = stages.isNotEmpty ? stages.last : 'processing';
    switch (currentStage) {
      case 'init':
        return 'Khởi tạo...';
      case 'scrape':
        return 'Đang cào video...';
      case 'download':
        return 'Đang tải video...';
      case 'transform':
        return 'Đang xử lý video...';
      case 'ai_logo_removal':
        return 'Đang xóa logo bằng AI...';
      case 'assemble':
        return 'Đang ghép video...';
      case 'save':
        return 'Đang lưu...';
      default:
        return 'Đang xử lý...';
    }
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
            const Icon(Icons.smart_display, size: 20),
            const SizedBox(width: 8),
            Text('Smart Reup Douyin', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),

        if (_jobStatus?['status'] == 'done') ...[
          // Success result
          Expanded(
            child: Center(
              child: Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Xử lý hoàn tất!',
                        style: theme.textTheme.titleLarge?.copyWith(color: Colors.green.shade700),
                      ),
                      const SizedBox(height: 8),
                      if (_jobStatus?['output_path'] != null)
                        Text(
                          'Cloud: ${_jobStatus!['output_path']}',
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      if (_jobStatus?['transforms_applied'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Transforms: ${(_jobStatus!['transforms_applied'] as List).join(", ")}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (_jobStatus?['output_path'] != null)
                        ElevatedButton.icon(
                          onPressed: () {
                            final cloudPath = _jobStatus!['output_path'] as String;
                            FileViewerDialog.showByPath(context, cloudPath);
                          },
                          icon: const Icon(Icons.play_circle),
                          label: const Text('Xem video'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _activeJobId = null;
                            _jobStatus = null;
                            _isProcessing = false;
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Xử lý video khác'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ] else if (_jobStatus?['status'] == 'failed') ...[
          // Error result
          Expanded(
            child: Center(
              child: Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Xử lý thất bại',
                        style: theme.textTheme.titleLarge?.copyWith(color: Colors.red.shade700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _jobStatus?['error'] ?? 'Unknown error',
                        style: TextStyle(color: Colors.red.shade700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _activeJobId = null;
                            _jobStatus = null;
                            _isProcessing = false;
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ] else if (_isProcessing) ...[
          // Processing
          Expanded(
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Job: $_activeJobId',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: ((_jobStatus?['progress'] ?? 0) / 100),
                      ),
                      const SizedBox(height: 4),
                      Text('${_jobStatus?['progress'] ?? 0}% • ${_getStageText()}'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ] else ...[
          // Input form
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // URL input
                  Text('Nhập URL Douyin', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            hintText: 'https://v.douyin.com/...',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                          ),
                          onChanged: (v) {
                            setState(() {
                              _url = v.isEmpty ? null : v;
                              _videoFile = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.paste),
                        tooltip: 'Paste from clipboard',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('— hoặc —', style: TextStyle(color: Colors.grey)),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _pickVideo,
                        icon: const Icon(Icons.video_file, size: 18),
                        label: Text(_videoFile != null
                            ? _videoFile!.path.split('/').last
                            : 'Chọn file video'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),

                  // Transforms
                  Text('Transforms', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      FilterChip(
                        label: const Text('Strip Metadata'),
                        selected: _stripMetadata,
                        onSelected: (v) => setState(() => _stripMetadata = v),
                      ),
                      FilterChip(
                        label: const Text('Mirror'),
                        selected: _mirror,
                        onSelected: (v) => setState(() => _mirror = v),
                      ),
                      FilterChip(
                        label: const Text('Flip H'),
                        selected: _flipH,
                        onSelected: (v) => setState(() => _flipH = v),
                      ),
                      FilterChip(
                        label: const Text('Zoom 4%'),
                        selected: _zoom,
                        onSelected: (v) => setState(() => _zoom = v),
                      ),
                      FilterChip(
                        label: const Text('Color Shift'),
                        selected: _color,
                        onSelected: (v) => setState(() => _color = v),
                      ),
                      FilterChip(
                        label: const Text('Noise'),
                        selected: _noise,
                        onSelected: (v) => setState(() => _noise = v),
                      ),
                      FilterChip(
                        label: const Text('Re-encode'),
                        selected: _recode,
                        onSelected: (v) => setState(() => _recode = v),
                      ),
                      FilterChip(
                        label: const Text('Speed ±2%'),
                        selected: _speed,
                        onSelected: (v) => setState(() => _speed = v),
                      ),
                      FilterChip(
                        label: const Text('Pitch Shift'),
                        selected: _pitch,
                        onSelected: (v) => setState(() => _pitch = v),
                      ),
                      FilterChip(
                        label: const Text('Strip Audio'),
                        selected: _stripAudio,
                        onSelected: (v) => setState(() => _stripAudio = v),
                      ),
                      FilterChip(
                        label: const Text('Cắt 4s cuối'),
                        selected: _trimEnd,
                        onSelected: (v) => setState(() => _trimEnd = v),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // // Audio mode
                  // Text('Audio Mode', style: theme.textTheme.titleSmall),
                  // const SizedBox(height: 8),
                  // Row(
                  //   children: [
                  //     Radio<String>(
                  //       value: 'strip',
                  //       groupValue: _audioMode,
                  //       onChanged: (v) => setState(() => _audioMode = v!),
                  //     ),
                  //     const Text('Strip audio'),
                  //     const SizedBox(width: 16),
                  //     Radio<String>(
                  //       value: 'shift',
                  //       groupValue: _audioMode,
                  //       onChanged: (v) => setState(() => _audioMode = v!),
                  //     ),
                  //     const Text('Pitch shift'),
                  //   ],
                  // ),
                  // const SizedBox(height: 16),

                  // Logo removal
                  Text('Logo Removal', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Column(
                    children: [
                      RadioListTile<String>(
                        title: const Text('None'),
                        value: 'none',
                        groupValue: _logoRemoval,
                        onChanged: (v) => setState(() => _logoRemoval = v!),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      RadioListTile<String>(
                        title: const Text('Manual crop'),
                        subtitle: const Text('Crop out logo area manually'),
                        value: 'manual',
                        groupValue: _logoRemoval,
                        onChanged: (v) => setState(() => _logoRemoval = v!),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      RadioListTile<String>(
                        title: const Text('AI (ComfyUI)'),
                        subtitle: const Text('Remove logo using inpainting'),
                        value: 'ai',
                        groupValue: _logoRemoval,
                        onChanged: (v) => setState(() => _logoRemoval = v!),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ],
                  ),

                  // Manual logo crop settings
                  if (_logoRemoval == 'manual') ...[
                    const SizedBox(height: 8),
                    Text('Logo Crop Settings (%)', style: theme.textTheme.bodySmall),
                    Row(
                      children: [
                        Expanded(child: _cropSlider('Top', _logoCropTop, (v) => setState(() => _logoCropTop = v))),
                        Expanded(child: _cropSlider('Right', _logoCropRight, (v) => setState(() => _logoCropRight = v))),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(child: _cropSlider('Bottom', _logoCropBottom, (v) => setState(() => _logoCropBottom = v))),
                        Expanded(child: _cropSlider('Left', _logoCropLeft, (v) => setState(() => _logoCropLeft = v))),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_url != null || _videoFile != null) ? _startSmartReup : null,
                      icon: const Icon(Icons.smart_display),
                      label: const Text('Smart Reup Douyin'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _cropSlider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 10)),
        Slider(
          value: value,
          min: 0,
          max: 20,
          divisions: 40,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
