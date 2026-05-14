import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../services/music_service.dart';
import '../../../widgets/audio/waveform_player.dart';
import '../../../widgets/common/custom_snackbar.dart';
import '../../../services/api_service.dart';
import '../../../services/storage_service.dart';

class GenerateTab extends StatefulWidget {
  final String taskType; // text2music, cover, repaint
  const GenerateTab({super.key, required this.taskType});

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
          debugPrint('>>> Music result keys: ${result.keys.toList()}');
          debugPrint('>>> audio_url=$audioUrl');
          
          if (result['amplitudes'] != null && result['amplitudes'] is List) {
             _amplitudes = List<double>.from(result['amplitudes'].map((e) => e.toDouble()));
             debugPrint('>>> Amplitudes received: ${_amplitudes!.length} samples');
          } else {
             _amplitudes = null;
             debugPrint('>>> No amplitudes from server');
          }

          if (audioUrl != null) {
            CustomSnackBar.showSuccess(context, 'Tạo nhạc thành công! Đang tải audio...');
            
            // Use ApiService to automatically include Auth headers
            final response = audioUrl.startsWith('http') 
                ? await http.get(
                    Uri.parse(audioUrl), 
                    headers: {
                      'Authorization': 'Bearer ${await StorageService.getToken()}'
                    }
                  )
                : await ApiService.get(audioUrl);

            debugPrint('>>> Audio fetch status: ${response.statusCode}, bytes: ${response.bodyBytes.length}');

            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
              setState(() {
                _audioBytes = response.bodyBytes;
              });
              debugPrint('>>> _audioBytes set: ${_audioBytes!.length} bytes');
            } else {
              CustomSnackBar.showError(context, 'Không tải được audio (${response.statusCode})');
            }
          } else {
            debugPrint('>>> audioUrl is null! Cannot fetch audio.');
            CustomSnackBar.showError(context, 'Server không trả về audio URL');
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
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final surface = isDark ? theme.colorScheme.surface : Colors.white;
    final border = isDark ? theme.dividerColor.withOpacity(0.1) : Colors.black.withOpacity(0.08);
    final tp = isDark ? Colors.white : Colors.black87;
    final ts = isDark ? Colors.white54 : Colors.black45;

    return Theme(
      data: theme.copyWith(
        sliderTheme: theme.sliderTheme.copyWith(
          trackHeight: 2,
          activeTrackColor: accent,
          inactiveTrackColor: accent.withOpacity(0.1),
          thumbColor: accent,
          overlayColor: accent.withOpacity(0.1),
        ),
      ),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Row(
          children: [
            // ── LEFT: Main workspace (scrollable) ──
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Text('Production Canvas',
                            style: TextStyle(color: tp, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                          const SizedBox(height: 6),
                          Text('Define the sonic identity of your track.',
                            style: TextStyle(color: ts, fontSize: 14)),
                          const SizedBox(height: 28),

                          // Source audio (cover/repaint only)
                          if (widget.taskType != 'text2music') ...[
                            _sectionLabel('SOURCE AUDIO', ts),
                            const SizedBox(height: 10),
                            _buildSourceAudioPicker(border, accent, tp, ts, isDark),
                            const SizedBox(height: 24),
                          ],

                          // Tags
                          _sectionLabel('VIBE & GENRE', ts),
                          const SizedBox(height: 10),
                          _inputField(
                            controller: _tagsController,
                            hint: 'Pop, electronic, cinematic, 90s hip hop, ethereal vocals...',
                            maxLines: 3,
                            surface: surface, border: border, tp: tp, ts: ts,
                          ),
                          const SizedBox(height: 24),

                          // Lyrics
                          _sectionLabel('LYRICS (OPTIONAL)', ts),
                          const SizedBox(height: 10),
                          _inputField(
                            controller: _lyricsController,
                            hint: '[Verse 1]\nWalking down the neon streets...\n\n[Chorus]\nAnd the lights go down...',
                            maxLines: 10,
                            surface: surface, border: border, tp: tp, ts: ts,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Bottom bar: Generate + Output ──
                  Container(
                    decoration: BoxDecoration(
                      color: surface.withOpacity(isDark ? 0.85 : 1.0),
                      border: Border(top: BorderSide(color: border)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    child: Row(
                      children: [
                        _buildGenerateButton(accent),
                        const SizedBox(width: 24),
                        Container(height: 56, width: 1, color: border),
                        const SizedBox(width: 24),
                        Expanded(child: _buildOutputArea(accent, surface, border, ts, tp)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── RIGHT: Properties sidebar (scrollable) ──
            Container(
              width: 300,
              decoration: BoxDecoration(
                color: surface,
                border: Border(left: BorderSide(color: border)),
              ),
              child: Column(
                children: [
                  // Sidebar header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
                    child: Row(
                      children: [
                        Icon(Icons.tune_rounded, color: accent, size: 18),
                        const SizedBox(width: 10),
                        Text('PROPERTIES', style: TextStyle(color: tp, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('ENGINE', ts),
                          const SizedBox(height: 16),
                          _slider('BPM', _bpm, 60, 200, (v) => setState(() => _bpm = v), accent, tp),
                          const SizedBox(height: 12),
                          _slider('LENGTH', _duration, 30, 180, (v) => setState(() => _duration = v), accent, tp, unit: 's'),
                          const SizedBox(height: 20),
                          _dropdown('KEYSCALE', _selectedKeyscale, _keyscales, (v) => setState(() => _selectedKeyscale = v!), border, ts, tp),
                          const SizedBox(height: 14),
                          _dropdown('LANGUAGE', _selectedLanguage, _languages, (v) => setState(() => _selectedLanguage = v!), border, ts, tp),
                          const SizedBox(height: 20),
                          _sectionLabel('OUTPUT QUALITY', ts),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _bitrateChip('128k', 'STANDARD', accent, isDark),
                              const SizedBox(width: 8),
                              _bitrateChip('320k', 'HIGH-RES', accent, isDark),
                            ],
                          ),
                          if (widget.taskType != 'text2music') ...[
                            const SizedBox(height: 24),
                            _sectionLabel('ADVANCED', ts),
                            const SizedBox(height: 14),
                            _buildAdvancedSettings(accent, tp),
                          ],
                        ],
                      ),
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

  // ─── WIDGETS ───

  Widget _sectionLabel(String text, Color ts) {
    return Text(text, style: TextStyle(color: ts, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2));
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required int maxLines,
    required Color surface,
    required Color border,
    required Color tp,
    required Color ts,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: maxLines,
      style: TextStyle(color: tp, fontSize: 15, height: 1.6),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: ts.withOpacity(0.5), fontSize: 14, height: 1.6),
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.all(20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: tp.withOpacity(0.25), width: 1.5)),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged, Color accent, Color tp, {String unit = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: tp.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.bold)),
            Text('${value.toInt()}$unit', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w900)),
          ],
        ),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }

  Widget _dropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, Color border, Color ts, Color tp) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: ts, fontSize: 10, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: ts.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              style: TextStyle(color: tp, fontSize: 13),
              onChanged: onChanged,
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.toUpperCase()))).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bitrateChip(String value, String label, Color accent, bool isDark) {
    final sel = _outputBitrate == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _outputBitrate = value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: sel ? accent : (isDark ? Colors.black26 : Colors.black.withOpacity(0.04)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? accent : (isDark ? Colors.white10 : Colors.black12)),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: sel ? Colors.white : (isDark ? Colors.white38 : Colors.black45), fontSize: 10, fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }

  Widget _buildSourceAudioPicker(Color border, Color accent, Color tp, Color ts, bool isDark) {
    return InkWell(
      onTap: _isUploadingAudio ? null : _pickAndUploadAudio,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: _srcAudioServerPath != null ? accent.withOpacity(0.5) : border),
          borderRadius: BorderRadius.circular(12),
          color: _srcAudioServerPath != null ? accent.withOpacity(0.05) : (isDark ? Colors.black.withOpacity(0.2) : Colors.white),
        ),
        child: Row(
          children: [
            Icon(
              _srcAudioServerPath != null ? Icons.check_circle_rounded : Icons.cloud_upload_rounded,
              color: _srcAudioServerPath != null ? Colors.greenAccent : accent, size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _srcAudioFile?.path.split(Platform.pathSeparator).last ?? 'Select Audio File',
                style: TextStyle(color: _srcAudioServerPath != null ? tp : ts, fontSize: 13,
                  fontWeight: _srcAudioServerPath != null ? FontWeight.bold : FontWeight.normal),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_isUploadingAudio)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSettings(Color accent, Color tp) {
    if (widget.taskType == 'cover') {
      return _slider('COVER STRENGTH', _audioCoverStrength, 0.1, 1.0, (v) => setState(() => _audioCoverStrength = v), accent, tp);
    }
    if (widget.taskType == 'repaint') {
      return Column(
        children: [
          _slider('START TIME', _repaintingStart, 0, 180, (v) => setState(() => _repaintingStart = v), accent, tp, unit: 's'),
          const SizedBox(height: 12),
          _slider('END TIME', _repaintingEnd, -1, 180, (v) => setState(() => _repaintingEnd = v), accent, tp),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildGenerateButton(Color accent) {
    return SizedBox(
      width: 180,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleGenerate,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: accent.withOpacity(0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 6,
          shadowColor: accent.withOpacity(0.4),
        ),
        child: _isLoading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_fix_high_rounded, size: 20),
                  SizedBox(width: 10),
                  Text('GENERATE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ],
              ),
      ),
    );
  }

  Widget _buildOutputArea(Color accent, Color surface, Color border, Color ts, Color tp) {
    Widget content;
    if (_isLoading) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        child: Row(
          children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 14),
            Expanded(child: Text('COMPOSING...', style: TextStyle(color: tp, fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            Text('~90s', style: TextStyle(color: ts, fontSize: 11)),
          ],
        ),
      );
    } else if (_queuedMessage != null) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        child: Row(
          children: [
            Icon(Icons.hourglass_bottom_rounded, color: Colors.orangeAccent.withOpacity(0.6), size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(_queuedMessage!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => _queuedMessage = null)),
          ],
        ),
      );
    } else if (_audioBytes != null) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: WaveformPlayer(
                key: ValueKey(_audioBytes.hashCode),
                audioBytes: _audioBytes!,
                precalculatedAmplitudes: _amplitudes,
              ),
            ),
            const SizedBox(width: 16),
            InkWell(
              onTap: _downloadAudio,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: accent.withOpacity(0.2))),
                child: Icon(Icons.download_rounded, color: accent, size: 20),
              ),
            ),
          ],
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.album_rounded, color: ts.withOpacity(0.15), size: 28),
              const SizedBox(width: 12),
              Text('NO TRACK GENERATED', style: TextStyle(color: ts.withOpacity(0.3), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: content),
    );
  }
}
