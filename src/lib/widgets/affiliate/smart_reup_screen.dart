import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../screens/affiliate/theme/affiliate_theme.dart';
import '../../screens/affiliate/widgets/affiliate_animations.dart';
import '../../services/affiliate_service.dart';
import '../../services/cloud_file_service.dart';
import '../common/download_progress_dialog.dart';
import '../file_viewer_dialog.dart';
import 'smart_reup/media_input_section.dart';
import 'smart_reup/transform_config_section.dart';
import 'smart_reup/processing_timeline.dart';

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
  bool _speed = true;
  bool _trimEnd = true;

  // Audio mode
  String _audioMode = 'strip'; // 'strip' | 'shift'

  // Logo removal
  String _logoRemoval = 'none'; // 'none' | 'manual' | 'ai'

  // Manual logo crop settings
  double _logoCropTop = 0.0;
  double _logoCropRight = 15.0;
  double _logoCropBottom = 8.0;
  double _logoCropLeft = 0.0;

  // Subtitle options
  bool _blurSubtitles = false;
  Rect? _blurRegion; // user-selected region on frame
  bool _burnSubtitles = false;
  File? _subtitleFile; // uploaded SRT
  String? _subtitleText;
  double? _subtitleDuration;
  String _subtitlePosition = 'bottom'; // 'top' | 'bottom'
  int _subtitleFontSize = 18;

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking video: $e')));
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

  Future<void> _selectBlurRegion() async {
    if (_url == null && _videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chọn video trước khi chọn vùng blur')),
      );
      return;
    }

    try {
      String? frameData;
      int? videoWidth;
      int? videoHeight;
      if (_videoFile != null) {
        final result = await AffiliateService.extractFrame(
          videoFile: _videoFile,
        );
        frameData = result['image'] as String;
        videoWidth = result['video_width'] as int?;
        videoHeight = result['video_height'] as int?;
      } else if (_url != null) {
        final result = await AffiliateService.extractFrame(videoUrl: _url);
        frameData = result['image'] as String;
        videoWidth = result['video_width'] as int?;
        videoHeight = result['video_height'] as int?;
      }

      if (frameData == null || !mounted) return;

      // Show dialog with frame and region selector
      final result = await showDialog<Rect>(
        context: context,
        builder: (context) => _BlurRegionSelectorDialog(
          frameDataUrl: frameData!,
          videoWidth: videoWidth ?? 1920,
          videoHeight: videoHeight ?? 1080,
        ),
      );

      if (result != null) {
        setState(() => _blurRegion = result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi trích xuất frame: $e')));
      }
    }
  }

  Future<void> _pickSubtitleFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'ass'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _subtitleFile = File(result.files.single.path!);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi chọn file: $e')));
      }
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
    if (_speed) transforms.add('speed');
    if (_trimEnd) transforms.add('trim_end');
    // Note: strip_audio / pitch are handled via audioMode, not as transforms

    // Build blur region map (normalized values)
    Map<String, int>? blurRegionMap;
    if (_blurSubtitles && _blurRegion != null) {
      blurRegionMap = {
        'x': _blurRegion!.left.toInt(),
        'y': _blurRegion!.top.toInt(),
        'w': _blurRegion!.width.toInt(),
        'h': _blurRegion!.height.toInt(),
      };
    }

    // Subtitle style
    Map<String, dynamic>? subStyle;
    if (_burnSubtitles) {
      subStyle = {
        'font_size': _subtitleFontSize,
        'font_color': 'white',
        'position': _subtitlePosition,
      };
    }

    // Upload subtitle file if provided
    String? uploadedSubPath;
    if (_subtitleFile != null) {
      try {
        uploadedSubPath = await AffiliateService.uploadSubtitle(_subtitleFile!);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload subtitle thất bại: $e')),
          );
          return;
        }
      }
    }

    try {
      final jobId = await AffiliateService.smartReupDouyin(
        url: _url,
        videoFile: _videoFile,
        transforms: transforms,
        audioMode: _audioMode,
        logoRemoval: _logoRemoval,
        blurSubtitles: _blurSubtitles,
        blurRegion: blurRegionMap,
        burnSubtitles: _burnSubtitles,
        subtitleFile: uploadedSubPath,
        subtitleText: _subtitleText,
        subtitleDuration: _subtitleDuration,
        subtitleStyle: subStyle,
      );

      setState(() {
        _activeJobId = jobId;
        _isProcessing = true;
        _jobStatus = {'status': 'pending', 'progress': 0};
      });
      _startPolling(jobId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Smart Reup error: $e')));
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
      case 'blur_subtitles':
        return 'Đang blur vùng subtitle...';
      case 'burn_subtitles':
        return 'Đang đốt phụ đề...';
      case 'assemble':
        return 'Đang ghép video...';
      case 'save':
        return 'Đang lưu...';
      default:
        return 'Đang xử lý...';
    }
  }

  Future<void> _downloadResult() async {
    if (_jobStatus?['output_path'] == null) return;

    final cloudPath = _jobStatus!['output_path'] as String;
    final filename = cloudPath.split('/').last;

    final outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Chọn nơi lưu tệp',
      fileName: filename,
    );

    if (outputFile == null) return;

    await DownloadProgressDialog.show(
      context: context,
      filename: filename,
      downloadTask: CloudFileService.downloadToLocal(cloudPath, outputFile),
    );
  }

  Widget _buildJobStateUI(ThemeData theme) {
    if (_jobStatus?['status'] == 'done') {
      return _buildSuccessState(theme);
    } else if (_jobStatus?['status'] == 'failed') {
      return _buildFailedState(theme);
    } else {
      return _buildProcessingState(theme);
    }
  }

  Widget _buildSuccessState(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: FadeInTranslate(
          child: Container(
            padding: const EdgeInsets.all(40),
            decoration: AffiliateTheme.cardDecoration(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_outline, color: Colors.green, size: 64),
                ),
                const SizedBox(height: 24),
                Text('Processing Complete!', style: AffiliateTheme.titleStyle(context).copyWith(color: Colors.green)),
                const SizedBox(height: 12),
                Text(
                  'Your video has been successfully transformed and is ready for use.',
                  textAlign: TextAlign.center,
                  style: AffiliateTheme.subtitleStyle(context),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final cloudPath = _jobStatus!['output_path'] as String;
                          FileViewerDialog.showByPath(context, cloudPath);
                        },
                        icon: const Icon(Icons.play_circle),
                        label: const Text('View Video'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AffiliateTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _downloadResult,
                        icon: const Icon(Icons.download),
                        label: const Text('Download'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _activeJobId = null;
                          _jobStatus = null;
                          _isProcessing = false;
                        }),
                        icon: const Icon(Icons.refresh),
                        label: const Text('New Reup'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFailedState(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: FadeInTranslate(
          child: Container(
            padding: const EdgeInsets.all(40),
            decoration: AffiliateTheme.cardDecoration(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.error_outline, color: Colors.red, size: 64),
                ),
                const SizedBox(height: 24),
                Text('Processing Failed', style: AffiliateTheme.titleStyle(context).copyWith(color: Colors.red)),
                const SizedBox(height: 12),
                Text(
                  _jobStatus?['error'] ?? 'An unknown error occurred during transformation.',
                  textAlign: TextAlign.center,
                  style: AffiliateTheme.subtitleStyle(context),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() {
                      _activeJobId = null;
                      _jobStatus = null;
                      _isProcessing = false;
                    }),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Widget _buildProcessingState(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    // Timeline stages dynamically built based on selected options
    final stages = <Map<String, dynamic>>[];

    if (_url != null) {
      stages.add({
        'key': 'scrape',
        'label': 'Cào dữ liệu (Scraping)',
        'icon': Icons.public,
      });
      stages.add({
        'key': 'download',
        'label': 'Đang tải (Downloading)',
        'icon': Icons.downloading,
      });
    }

    // We always have some sort of transform/processing
    stages.add({
      'key': 'transform',
      'label': 'Bộ lọc (Transforming)',
      'icon': Icons.movie_filter,
    });

    if (_logoRemoval == 'ai') {
      stages.add({
        'key': 'ai_logo_removal',
        'label': 'Xóa logo (AI Inpaint)',
        'icon': Icons.auto_fix_high,
      });
    }

    if (_blurSubtitles) {
      stages.add({
        'key': 'blur_subtitles',
        'label': 'Che phụ đề (Blur)',
        'icon': Icons.blur_on,
      });
    }

    if (_burnSubtitles) {
      stages.add({
        'key': 'burn_subtitles',
        'label': 'Đốt phụ đề (Subtitles)',
        'icon': Icons.subtitles,
      });
    }

    stages.add({
      'key': 'assemble',
      'label': 'Ghép nối (Assembling)',
      'icon': Icons.smart_display,
    });
    stages.add({
      'key': 'save',
      'label': 'Đang lưu (Saving)',
      'icon': Icons.cloud_done,
    });

    final backendStages = _jobStatus?['stages'] as List? ?? [];
    final currentStage = backendStages.isNotEmpty ? backendStages.last : 'init';

    int activeIndex = -1;
    for (int i = 0; i < stages.length; i++) {
      // Match perfectly or try to find fallback
      if (currentStage == stages[i]['key']) {
        activeIndex = i;
        break;
      }
    }

    // Fallback if current Stage is somehow not perfectly matched due to timing or skips
    if (activeIndex == -1 &&
        currentStage != 'init' &&
        currentStage != 'starting') {
      if (currentStage == 'blur_subtitles' ||
          currentStage == 'burn_subtitles') {
        activeIndex = stages.indexWhere(
          (e) => e['key'] == 'blur_subtitles' || e['key'] == 'burn_subtitles',
        );
        if (activeIndex == -1)
          activeIndex = stages.indexWhere((e) => e['key'] == 'transform');
      }
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.02)
              : Colors.black.withOpacity(0.01),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.03),
              blurRadius: 40,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Circular Progress
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: (_jobStatus?['progress'] ?? 0) / 100,
                        strokeWidth: 10,
                        backgroundColor: theme.colorScheme.primary.withOpacity(
                          0.1,
                        ),
                        color: theme.colorScheme.primary,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          '${_jobStatus?['progress'] ?? 0}%',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Đang xử lý',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Job: $_activeJobId',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 48),
            Container(
              width: 1,
              height: 250,
              color: theme.colorScheme.onSurface.withOpacity(0.1),
            ),
            const SizedBox(width: 48),

            // Timeline stepper
            SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(stages.length, (index) {
                  final isCompleted =
                      activeIndex > index || _jobStatus?['progress'] == 100;
                  final isActive =
                      activeIndex == index && _jobStatus?['progress'] != 100;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? Colors.green
                                : isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withOpacity(0.1),
                            shape: BoxShape.circle,
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: theme.colorScheme.primary
                                          .withOpacity(0.3),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isCompleted
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : Icon(
                                  stages[index]['icon'] as IconData,
                                  size: 14,
                                  color: isActive
                                      ? Colors.white
                                      : theme.colorScheme.onSurface.withOpacity(
                                          0.5,
                                        ),
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            stages[index]['label'] as String,
                            style: TextStyle(
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isActive
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withOpacity(
                                      isCompleted ? 0.8 : 0.4,
                                    ),
                            ),
                          ),
                        ),
                        if (isActive)
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_jobStatus != null || _isProcessing) {
      return _buildProcessingFlow(context);
    }
    return _buildInputFlow(context);
  }

  Widget _buildInputFlow(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeInTranslate(
            child: MediaInputSection(
              url: _url,
              videoFile: _videoFile,
              urlController: _urlController,
              onPickVideo: _pickVideo,
              onPaste: _pasteFromClipboard,
              onUrlChanged: (v) {
                setState(() {
                  _url = v.isEmpty ? null : v;
                  _videoFile = null;
                });
              },
            ),
          ),
          const SizedBox(height: 20),
          FadeInTranslate(
            delay: const Duration(milliseconds: 100),
            child: TransformConfigSection(
              configs: {
                'strip_metadata': _stripMetadata,
                'mirror': _mirror,
                'flip_h': _flipH,
                'zoom_4%': _zoom,
                'color_shift': _color,
                'noise': _noise,
                're_encode': _recode,
                'speed_±2%': _speed,
                'trim_4s_end': _trimEnd,
              },
              onChanged: (key, val) {
                setState(() {
                  switch (key) {
                    case 'strip_metadata': _stripMetadata = val; break;
                    case 'mirror': _mirror = val; break;
                    case 'flip_h': _flipH = val; break;
                    case 'zoom_4%': _zoom = val; break;
                    case 'color_shift': _color = val; break;
                    case 'noise': _noise = val; break;
                    case 're_encode': _recode = val; break;
                    case 'speed_±2%': _speed = val; break;
                    case 'trim_4s_end': _trimEnd = val; break;
                  }
                });
              },
              audioMode: _audioMode,
              onAudioModeChanged: (v) => setState(() => _audioMode = v!),
              logoRemoval: _logoRemoval,
              onLogoRemovalChanged: (v) => setState(() => _logoRemoval = v!),
            ),
          ),
          if (_logoRemoval == 'manual') 
            FadeInTranslate(
              delay: const Duration(milliseconds: 200),
              child: Container(
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.all(20),
                decoration: AffiliateTheme.cardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Text('Manual Logo Crop (%)', style: AffiliateTheme.titleStyle(context).copyWith(fontSize: 16)),
                     const SizedBox(height: 12),
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
                ),
              ),
            ),
          const SizedBox(height: 32),
          FadeInTranslate(
            delay: const Duration(milliseconds: 300),
            child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: AffiliateTheme.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AffiliateTheme.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: (_url != null || _videoFile != null) ? _startSmartReup : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  'Start Smart Reup',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildProcessingFlow(BuildContext context) {
    if (_jobStatus?['status'] == 'done') {
      return _buildSuccessState(Theme.of(context));
    } else if (_jobStatus?['status'] == 'failed') {
      return _buildFailedState(Theme.of(context));
    }

    final stages = <Map<String, dynamic>>[];
    if (_url != null) {
      stages.add({'key': 'scrape', 'label': 'Scraping', 'icon': Icons.public});
      stages.add({'key': 'download', 'label': 'Downloading', 'icon': Icons.downloading});
    }
    stages.add({'key': 'transform', 'label': 'Transforming', 'icon': Icons.movie_filter});
    if (_logoRemoval == 'ai') stages.add({'key': 'ai_logo_removal', 'label': 'AI Inpaint', 'icon': Icons.auto_fix_high});
    if (_blurSubtitles) stages.add({'key': 'blur_subtitles', 'label': 'Blur Subtitles', 'icon': Icons.blur_on});
    if (_burnSubtitles) stages.add({'key': 'burn_subtitles', 'label': 'Burn Subtitles', 'icon': Icons.subtitles});
    stages.add({'key': 'assemble', 'label': 'Assembling', 'icon': Icons.movie});
    stages.add({'key': 'save', 'label': 'Saving', 'icon': Icons.cloud_done});

    final backendStages = _jobStatus?['stages'] as List? ?? [];
    final currentStage = backendStages.isNotEmpty ? backendStages.last : 'init';
    int activeIndex = stages.indexWhere((e) => e['key'] == currentStage);
    if (activeIndex == -1) activeIndex = 0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: FadeInTranslate(
          child: ProcessingTimeline(
            jobStatus: _jobStatus,
            stages: stages,
            activeIndex: activeIndex,
            activeJobId: _activeJobId ?? 'Unknown',
          ),
        ),
      ),
    );
  }

  Widget _cropSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ${value.toStringAsFixed(1)}%',
          style: const TextStyle(fontSize: 10),
        ),
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

/// Dialog for selecting a blur region on a video frame.
class _BlurRegionSelectorDialog extends StatefulWidget {
  final String frameDataUrl; // base64 data URL
  final int videoWidth;
  final int videoHeight;

  const _BlurRegionSelectorDialog({
    required this.frameDataUrl,
    required this.videoWidth,
    required this.videoHeight,
  });

  @override
  State<_BlurRegionSelectorDialog> createState() =>
      _BlurRegionSelectorDialogState();
}

class _BlurRegionSelectorDialogState extends State<_BlurRegionSelectorDialog> {
  Rect? _selection;
  // Rendered image position and size within the container (for coordinate scaling)
  double _renderedX = 0;
  double _renderedY = 0;
  double _renderedW = 0;
  double _renderedH = 0;
  bool _imageLoaded = false;

  /// Scale coordinates from display space (container pixels) to original video space.
  Rect _toVideoCoords(Rect displayRect) {
    if (!_imageLoaded || _renderedW == 0 || _renderedH == 0) return displayRect;

    // Adjust for image offset within container (centering)
    final imgLeft = displayRect.left - _renderedX;
    final imgTop = displayRect.top - _renderedY;

    // Scale to video coordinates
    final scaleX = widget.videoWidth / _renderedW;
    final scaleY = widget.videoHeight / _renderedH;

    final leftVideo = (imgLeft * scaleX).round().clamp(0, widget.videoWidth);
    final topVideo = (imgTop * scaleY).round().clamp(0, widget.videoHeight);
    final wVideo = (displayRect.width * scaleX).round().clamp(
      0,
      widget.videoWidth,
    );
    final hVideo = (displayRect.height * scaleY).round().clamp(
      0,
      widget.videoHeight,
    );

    return Rect.fromLTWH(
      leftVideo.toDouble(),
      topVideo.toDouble(),
      wVideo.toDouble(),
      hVideo.toDouble(),
    );
  }

  /// Compute rendered image rect after image loads, given container constraints.
  void _computeRenderedRect(Size containerSize, Size imageSize) {
    final containerW = containerSize.width;
    final containerH = containerSize.height;
    final imgW = imageSize.width;
    final imgH = imageSize.height;

    if (imgW == 0 || imgH == 0 || containerW == 0 || containerH == 0) return;

    final scale = (containerW / imgW).clamp(0.0, 1.0) < (containerH / imgH)
        ? containerW / imgW
        : containerH / imgH;

    final renderedW = imgW * scale;
    final renderedH = imgH * scale;
    final renderedX = (containerW - renderedW) / 2;
    final renderedY = (containerH - renderedH) / 2;

    setState(() {
      _renderedW = renderedW;
      _renderedH = renderedH;
      _renderedX = renderedX;
      _renderedY = renderedY;
      _imageLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chọn vùng blur subtitle'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Kéo chọn vùng chứa subtitle trên video để blur',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final containerSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _selection = Rect.fromPoints(
                          details.localPosition,
                          details.localPosition,
                        );
                      });
                    },
                    onPanUpdate: (details) {
                      if (_selection != null) {
                        setState(() {
                          _selection = Rect.fromPoints(
                            _selection!.topLeft,
                            details.localPosition,
                          );
                        });
                      }
                    },
                    onPanEnd: (_) {},
                    child: Stack(
                      children: [
                        Image.memory(
                          base64Decode(widget.frameDataUrl.split(',').last),
                          fit: BoxFit.contain,
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          frameBuilder: (context, child, frame, loaded) {
                            if (loaded && frame != null && !_imageLoaded) {
                              // Compute rendered rect from natural image size + container
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _computeRenderedRect(
                                  containerSize,
                                  Size(
                                    widget.videoWidth.toDouble(),
                                    widget.videoHeight.toDouble(),
                                  ),
                                );
                              });
                            }
                            return child;
                          },
                        ),
                        if (_selection != null)
                          Positioned(
                            left: _selection!.left < _selection!.right
                                ? _selection!.left
                                : _selection!.right,
                            top: _selection!.top < _selection!.bottom
                                ? _selection!.top
                                : _selection!.bottom,
                            child: Container(
                              width: _selection!.width.abs(),
                              height: _selection!.height.abs(),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.red, width: 2),
                                color: Colors.red.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _selection != null && _imageLoaded
              ? () {
                  final rect = _selection!;
                  final normalized = Rect.fromLTRB(
                    rect.left < rect.right ? rect.left : rect.right,
                    rect.top < rect.bottom ? rect.top : rect.bottom,
                    rect.left > rect.right ? rect.left : rect.right,
                    rect.top > rect.bottom ? rect.top : rect.bottom,
                  );
                  final videoRect = _toVideoCoords(normalized);
                  Navigator.pop(context, videoRect);
                }
              : null,
          child: const Text('Xác nhận'),
        ),
      ],
    );
  }
}
