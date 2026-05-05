import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../services/music_service.dart';
import '../../../widgets/audio/waveform_player.dart';
import '../../../widgets/common/custom_snackbar.dart';
import '../../../config/api_config.dart';

class GenerateTab extends StatefulWidget {
  final String taskType; // text2music, cover, repaint
  final TabController? tabController;
  const GenerateTab({super.key, required this.taskType, this.tabController});

  @override
  State<GenerateTab> createState() => _GenerateTabState();
}

class _GenerateTabState extends State<GenerateTab> {
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _lyricsController = TextEditingController();
  
  bool _isLoading = false;
  String? _queuedMessage;
  Uint8List? _audioBytes;
  
  // Settings
  double _bpm = 95;
  double _duration = 120;
  String _selectedLanguage = 'vi';
  String _selectedKeyscale = 'E minor';
  
  // Advanced parameters
  File? _srcAudioFile;
  String? _srcAudioServerPath;
  bool _isUploadingAudio = false;
  double _audioCoverStrength = 0.5;
  bool _noFsq = false;
  double _repaintingStart = 0.0;
  double _repaintingEnd = -1.0;
  String _outputBitrate = '320k';
  List<double>? _amplitudes;
  
  final List<String> _languages = ['vi', 'en', 'ja', 'ko', 'zh', 'fr', 'de', 'es'];
  final List<String> _keyscales = [
    'C major', 'C minor', 'C# major', 'C# minor',
    'D major', 'D minor', 'D# major', 'D# minor',
    'E major', 'E minor',
    'F major', 'F minor', 'F# major', 'F# minor',
    'G major', 'G minor', 'G# major', 'G# minor',
    'A major', 'A minor', 'A# major', 'A# minor',
    'B major', 'B minor',
  ];

  @override
  void dispose() {
    _tagsController.dispose();
    _lyricsController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      setState(() {
        _srcAudioFile = file;
        _isUploadingAudio = true;
      });
      
      try {
        final response = await MusicService.uploadAudio(file.path);
        if (mounted) {
          setState(() {
            _srcAudioServerPath = response['file_path'];
            _isUploadingAudio = false;
          });
          CustomSnackBar.showSuccess(context, 'Tải lên âm thanh gốc thành công!');
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isUploadingAudio = false);
          CustomSnackBar.showError(context, 'Lỗi tải lên: $e');
        }
      }
    }
  }

  Future<void> _handleGenerate() async {
    if (widget.taskType == 'text2music') {
      final tags = _tagsController.text.trim();
      if (tags.isEmpty) {
        CustomSnackBar.showError(context, 'Vui lòng nhập tags (thể loại nhạc, cảm xúc...)');
        return;
      }
    } else {
      // Cover / Repaint requires source audio
      if (_srcAudioServerPath == null) {
        CustomSnackBar.showError(context, 'Vui lòng tải lên âm thanh gốc (Source Audio) trước!');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _queuedMessage = null;
      _audioBytes = null;
    });

    try {
      final actualTaskType = (widget.taskType == 'cover' && _noFsq) ? 'cover-nofsq' : widget.taskType;
      
      final result = await MusicService.generateMusic(
        tags: _tagsController.text.trim(),
        lyrics: _lyricsController.text.trim(),
        bpm: _bpm.toInt(),
        duration: _duration.toInt(),
        language: _selectedLanguage.toLowerCase(),
        keyscale: _selectedKeyscale,
        taskType: actualTaskType,
        srcAudio: _srcAudioServerPath,
        audioCoverStrength: _audioCoverStrength,
        repaintingStart: _repaintingStart,
        repaintingEnd: _repaintingEnd,
        outputBitrate: _outputBitrate,
      );

      if (mounted) {
        if (result['queued'] == true) {
          setState(() {
            _queuedMessage = result['message'] ?? 'Đang chờ đến lượt...';
          });
          CustomSnackBar.showSuccess(context, 'Yêu cầu đã được xếp hàng (Job: ${result['job_id']})');
        } else {
          final audioUrl = result['audio_url'] ?? result['url'];
          
          if (result['amplitudes'] != null && result['amplitudes'] is List) {
             _amplitudes = List<double>.from(result['amplitudes'].map((e) => e.toDouble()));
          } else {
             _amplitudes = null;
          }

          if (audioUrl != null) {
            CustomSnackBar.showSuccess(context, 'Tạo nhạc thành công! Đang tải audio...');
            // Fix relative URI issue
            final String fullAudioUrl = audioUrl.startsWith('http') 
                ? audioUrl 
                : '${ApiConfig.baseUrl}$audioUrl';
                
            // Fetch audio bytes for waveform
            final response = await http.get(Uri.parse(fullAudioUrl));
            if (response.statusCode == 200) {
              setState(() {
                _audioBytes = response.bodyBytes;
              });
            } else {
              CustomSnackBar.showError(context, 'Không tải được audio: ${response.statusCode}');
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadAudio() async {
    if (_audioBytes == null) return;
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'producer_studio_$timestamp.mp3';

      String? downloadPath;
      if (Platform.isLinux || Platform.isMacOS) {
        downloadPath = '${Platform.environment['HOME']}/Downloads';
      } else if (Platform.isWindows) {
        downloadPath = '${Platform.environment['USERPROFILE']}\\Downloads';
      } else {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Music',
          fileName: fileName,
          type: FileType.audio,
          bytes: _audioBytes,
        );
        if (result != null && mounted) {
          CustomSnackBar.showSuccess(context, 'Đã lưu audio tại: $result');
        }
        return;
      }

      final file = File('$downloadPath/$fileName');
      await file.writeAsBytes(_audioBytes!);
      if (mounted) {
        CustomSnackBar.showSuccess(context, 'Đã lưu nhạc tại: ${file.path}');
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, 'Lỗi tải xuống: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // We force a dark studio theme for this screen for a professional look
    final studioBg = const Color(0xFF0B0D13);
    final studioSurface = const Color(0xFF161922);
    final studioBorder = const Color(0xFF2D313E);
    final studioAccent = const Color(0xFF6366F1);

    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: studioBg,
        colorScheme: theme.colorScheme.copyWith(
          surface: studioSurface,
          primary: studioAccent,
        ),
      ),
      child: Scaffold(
        backgroundColor: studioBg,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── LEFT SIDEBAR: CONTROLS ──
            Container(
              width: 300,
              decoration: BoxDecoration(
                color: studioSurface,
                border: Border(right: BorderSide(color: studioBorder)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStudioHeader(studioAccent),
                  _buildTabSwitcher(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.taskType != 'text2music') ...[
                            _buildSidebarSectionTitle('SOURCE AUDIO'),
                            const SizedBox(height: 12),
                            _buildSourceAudioPicker(studioBorder, studioAccent),
                            const SizedBox(height: 24),
                          ],
                          _buildSidebarSectionTitle('ENGINE PARAMETERS'),
                          const SizedBox(height: 16),
                          _buildParameterSliders(studioAccent),
                          const SizedBox(height: 20),
                          _buildDropdowns(studioBorder),
                          const SizedBox(height: 20),
                          _buildBitrateSelector(studioAccent),
                          if (widget.taskType != 'text2music') ...[
                            const SizedBox(height: 24),
                            _buildSidebarSectionTitle('ADVANCED'),
                            const SizedBox(height: 12),
                            _buildAdvancedSettings(studioAccent),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── MAIN CONTENT: WORKSPACE ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Workspace Area
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildWorkspaceHeader(),
                          const SizedBox(height: 32),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: _buildInputStation(
                                    title: 'VIBE & GENRE',
                                    icon: Icons.auto_awesome_mosaic_rounded,
                                    controller: _tagsController,
                                    hint: 'Pop, electronic, cinematic, 90s hip hop, ethereal vocals...',
                                    studioSurface: studioSurface,
                                    studioBorder: studioBorder,
                                  ),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  flex: 6,
                                  child: _buildInputStation(
                                    title: 'LYRICS (OPTIONAL)',
                                    icon: Icons.lyrics_rounded,
                                    controller: _lyricsController,
                                    hint: '[Verse 1]\nWalking down the neon streets...\n\n[Chorus]\nAnd the lights go down...',
                                    studioSurface: studioSurface,
                                    studioBorder: studioBorder,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Master Output Area (The "Mất tiêu" part fixed)
                  Container(
                    height: 240,
                    decoration: BoxDecoration(
                      color: studioSurface.withOpacity(0.5),
                      border: Border(top: BorderSide(color: studioBorder)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                    child: Row(
                      children: [
                        // Generate Controls
                        _buildGenerateButton(studioAccent),
                        const SizedBox(width: 40),
                        const VerticalDivider(width: 1, color: Color(0xFF2D313E)),
                        const SizedBox(width: 40),
                        // Master Results
                        Expanded(
                          child: _buildMasterOutputDisplay(studioAccent, studioSurface, studioBorder),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HELPER WIDGETS ──

  Widget _buildStudioHeader(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Row(
        children: [
          Icon(Icons.waves_rounded, color: accent, size: 28),
          const SizedBox(width: 12),
          const Text(
            'STUDIO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    if (widget.tabController == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: TabBar(
          controller: widget.tabController,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            color: const Color(0xFF2D313E),
            borderRadius: BorderRadius.circular(6),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          unselectedLabelColor: Colors.white38,
          labelColor: Colors.white,
          tabs: const [
            Tab(text: 'TEXT2M'),
            Tab(text: 'COVER'),
            Tab(text: 'REPAINT'),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withOpacity(0.4),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildSourceAudioPicker(Color border, Color accent) {
    return InkWell(
      onTap: _isUploadingAudio ? null : _pickAndUploadAudio,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: _srcAudioServerPath != null ? accent.withOpacity(0.5) : border),
          borderRadius: BorderRadius.circular(12),
          color: _srcAudioServerPath != null ? accent.withOpacity(0.05) : Colors.black.withOpacity(0.2),
        ),
        child: Row(
          children: [
            Icon(
              _srcAudioServerPath != null ? Icons.check_circle_rounded : Icons.cloud_upload_rounded,
              color: _srcAudioServerPath != null ? Colors.greenAccent : accent,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _srcAudioFile?.path.split(Platform.pathSeparator).last ?? 'Select Audio File',
                style: TextStyle(
                  color: _srcAudioServerPath != null ? Colors.white : Colors.white38,
                  fontSize: 12,
                  fontWeight: _srcAudioServerPath != null ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParameterSliders(Color accent) {
    return Column(
      children: [
        _buildStudioSlider(
          label: 'BPM',
          value: _bpm,
          min: 60,
          max: 200,
          onChanged: (v) => setState(() => _bpm = v),
          accent: accent,
        ),
        const SizedBox(height: 16),
        _buildStudioSlider(
          label: 'LENGTH',
          value: _duration,
          min: 30,
          max: 180,
          unit: 's',
          onChanged: (v) => setState(() => _duration = v),
          accent: accent,
        ),
      ],
    );
  }

  Widget _buildStudioSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    String unit = '',
    required ValueChanged<double> onChanged,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            Text('${value.toInt()}$unit', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w900)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            activeTrackColor: accent,
            inactiveTrackColor: Colors.white10,
            thumbColor: Colors.white,
            overlayColor: accent.withOpacity(0.1),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }

  Widget _buildDropdowns(Color border) {
    return Column(
      children: [
        _buildStudioDropdown(
          label: 'KEYSCALE',
          value: _selectedKeyscale,
          items: _keyscales,
          onChanged: (v) => setState(() => _selectedKeyscale = v!),
          border: border,
        ),
        const SizedBox(height: 16),
        _buildStudioDropdown(
          label: 'LANGUAGE',
          value: _selectedLanguage,
          items: _languages,
          onChanged: (v) => setState(() => _selectedLanguage = v!),
          border: border,
        ),
      ],
    );
  }

  Widget _buildStudioDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required Color border,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF161922),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              onChanged: onChanged,
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.toUpperCase()))).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBitrateSelector(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('OUTPUT QUALITY', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildBitrateChip('128k', 'STANDARD', accent),
            const SizedBox(width: 8),
            _buildBitrateChip('320k', 'HIGH-RES', accent),
          ],
        ),
      ],
    );
  }

  Widget _buildBitrateChip(String value, String label, Color accent) {
    final isSelected = _outputBitrate == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _outputBitrate = value),
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: isSelected ? accent : Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isSelected ? accent : Colors.white10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedSettings(Color accent) {
    if (widget.taskType == 'cover') {
      return _buildStudioSlider(
        label: 'COVER STRENGTH',
        value: _audioCoverStrength,
        min: 0.1,
        max: 1.0,
        onChanged: (v) => setState(() => _audioCoverStrength = v),
        accent: accent,
      );
    }
    if (widget.taskType == 'repaint') {
      return Column(
        children: [
          _buildStudioSlider(
            label: 'START TIME',
            value: _repaintingStart,
            min: 0,
            max: 180,
            unit: 's',
            onChanged: (v) => setState(() => _repaintingStart = v),
            accent: accent,
          ),
          const SizedBox(height: 16),
          _buildStudioSlider(
            label: 'END TIME',
            value: _repaintingEnd,
            min: -1,
            max: 180,
            onChanged: (v) => setState(() => _repaintingEnd = v),
            accent: accent,
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildWorkspaceHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Production Canvas',
          style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1),
        ),
        const SizedBox(height: 8),
        Text(
          'Define the sonic identity of your track. Use comma-separated tags for best results.',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildInputStation({
    required String title,
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    required Color studioSurface,
    required Color studioBorder,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: studioSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: studioBorder),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white38, size: 18),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 15),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateButton(Color accent) {
    return SizedBox(
      width: 200,
      height: 64,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleGenerate,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: accent.withOpacity(0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 20,
          shadowColor: accent.withOpacity(0.4),
        ),
        child: _isLoading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_fix_high_rounded, size: 22),
                  SizedBox(width: 12),
                  Text('GENERATE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ],
              ),
      ),
    );
  }

  Widget _buildMasterOutputDisplay(Color accent, Color surface, Color border) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            if (_isLoading)
              _buildProcessingIndicator(accent)
            else if (_queuedMessage != null)
              _buildQueueState(accent)
            else if (_audioBytes != null)
              _buildAudioResult(accent)
            else
              _buildEmptyOutputState(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyOutputState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.album_rounded, color: Colors.white.withOpacity(0.05), size: 48),
          const SizedBox(height: 12),
          Text(
            'NO TRACK GENERATED',
            style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingIndicator(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 20),
              const Text('ORCHESTRATING COMPOSITION...', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('ETA: ~60s', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(backgroundColor: Colors.white.withOpacity(0.05), valueColor: AlwaysStoppedAnimation(accent)),
        ],
      ),
    );
  }

  Widget _buildQueueState(Color accent) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_bottom_rounded, color: Colors.orangeAccent.withOpacity(0.5), size: 32),
          const SizedBox(height: 12),
          Text(
            _queuedMessage ?? 'SYSTEM BUSY - QUEUED',
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() => _queuedMessage = null),
            child: const Text('DISMISS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioResult(Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: WaveformPlayer(
              key: ValueKey(_audioBytes.hashCode),
              audioBytes: _audioBytes!,
              precalculatedAmplitudes: _amplitudes,
            ),
          ),
          const SizedBox(width: 24),
          _buildActionButton(Icons.download_rounded, 'DL', _downloadAudio, accent),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap, Color accent) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: accent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withOpacity(0.2)),
        ),
        child: Icon(icon, color: accent, size: 20),
      ),
    );
  }
}

