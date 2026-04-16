import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/tts_service.dart';
import '../widgets/audio/waveform_player.dart';
import '../widgets/common/custom_snackbar.dart';

// ════════════════════════════════════════════════════════════════
// TTS SCREEN — Entry Point
// ════════════════════════════════════════════════════════════════
class TtsScreen extends StatelessWidget {
  const TtsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TtsScreenContent();
  }
}

// ════════════════════════════════════════════════════════════════
// MAIN CONTENT SHELL
// ════════════════════════════════════════════════════════════════
class _TtsScreenContent extends StatefulWidget {
  const _TtsScreenContent();

  @override
  State<_TtsScreenContent> createState() => _TtsScreenContentState();
}

class _TtsScreenContentState extends State<_TtsScreenContent> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        // ── Gradient background (no BackdropFilter, no AnimatedBlob) ──
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.5, 1.0],
            colors: isDark
                ? [
                    const Color(0xFF0A0A0B),
                    const Color(0xFF0F0A1A),
                    const Color(0xFF0A0A0B),
                  ]
                : [
                    const Color(0xFFF9FAFB),
                    const Color(0xFFF0F0FF),
                    const Color(0xFFF9FAFB),
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildFloatingHeader(theme, isDark),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _selectedTab == 0
                      ? const SynthesisView(key: ValueKey('synthesis'))
                      : const VoiceLabView(key: ValueKey('voicelab')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Floating Glass Header (mirrors Translate Studio) ──
  Widget _buildFloatingHeader(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.white.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          // ── Icon badge ──
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.graphic_eq_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 16),
          // ── Title ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "TTS Studio",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  "Chuyển văn bản thành giọng nói chuyên nghiệp",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ── Compact tab pills ──
          _buildCompactTabs(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildCompactTabs(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCompactTab(
              0, Icons.mic_rounded, "Synthesis", theme, isDark),
          _buildCompactTab(
              1, Icons.science_rounded, "Voice Lab", theme, isDark),
        ],
      ),
    );
  }

  Widget _buildCompactTab(
      int index, IconData icon, String label, ThemeData theme, bool isDark) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuart,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white10 : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected && !isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.4),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// SYNTHESIS VIEW
// ════════════════════════════════════════════════════════════════
class SynthesisView extends StatefulWidget {
  const SynthesisView({super.key});

  @override
  State<SynthesisView> createState() => _SynthesisViewState();
}

class _SynthesisViewState extends State<SynthesisView>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _textController = TextEditingController();
  List<Voice> _voices = [];
  String? _selectedVoiceId;
  bool _isLoading = false;
  Uint8List? _audioBytes;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadVoices() async {
    try {
      final voices = await TtsService.getVoices(isTurbo: false);
      if (mounted) {
        setState(() {
          _voices = voices;
          if (_voices.isNotEmpty) {
            _selectedVoiceId = _voices.any((v) => v.id == 'Binh')
                ? 'Binh'
                : _voices.first.id;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, "Lỗi tải danh sách giọng: $e");
      }
    }
  }

  Future<void> _synthesize() async {
    if (_selectedVoiceId == null || _textController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final bytes = await TtsService.synthesize(
        _textController.text,
        _selectedVoiceId!,
        isTurbo: false,
      );
      setState(() => _audioBytes = Uint8List.fromList(bytes));
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, "Chuyển đổi thất bại: $e");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadAudio() async {
    if (_audioBytes == null) return;
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'tts_audio_$timestamp.mp3';

      String? downloadPath;
      if (Platform.isLinux || Platform.isMacOS) {
        downloadPath = '${Platform.environment['HOME']}/Downloads';
      } else if (Platform.isWindows) {
        downloadPath = '${Platform.environment['USERPROFILE']}\\Downloads';
      } else {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Audio',
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
        CustomSnackBar.showSuccess(context, 'Đã lưu audio tại: ${file.path}');
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, 'Lỗi tải xuống: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          // ── Top: Text Editor (Reduced height) ──
          Flexible(
            flex: 2,
            child: _buildEditorPanel(theme, isDark),
          ),
          const SizedBox(height: 16),
          // ── Bottom: Voice Selector + Audio Result (Expanded space) ──
          Expanded(
            flex: 3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Voice selector
                Expanded(
                  flex: 1,
                  child: _buildVoiceSelectorPanel(theme, isDark),
                ),
                const SizedBox(width: 16),
                // Audio result (Bigger space)
                Expanded(
                  flex: 1,
                  child: _buildAudioResultPanel(theme, isDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Text Editor Panel ──
  Widget _buildEditorPanel(ThemeData theme, bool isDark) {
    return _GlassPanel(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel header
          Row(
            children: [
              Icon(Icons.text_snippet_rounded,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                "Nội dung văn bản",
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${_textController.text.length} / 5000",
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Text input area
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withOpacity(0.2)
                    : Colors.grey.withOpacity(0.03),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: GoogleFonts.beVietnamPro(fontSize: 14, height: 1.6),
                maxLength: 5000,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText:
                      "Nhập hoặc dán nội dung bạn muốn chuyển sang giọng nói...",
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.2),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(24),
                  counterText: "",
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Generate button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed:
                  _isLoading || _textController.text.isEmpty ? null : _synthesize,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: Text(
                _isLoading ? "Đang tạo giọng nói..." : "Tạo giọng nói ngay",
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                shadowColor: theme.colorScheme.primary.withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Voice Selector Panel ──
  Widget _buildVoiceSelectorPanel(ThemeData theme, bool isDark) {
    return _GlassPanel(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.person_search_rounded,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                "Chọn Giọng nói",
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loadVoices,
                icon: Icon(Icons.refresh_rounded, 
                    size: 18, color: theme.colorScheme.primary),
                tooltip: "Tải lại danh sách giọng",
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Voice list
          Expanded(
            child: _voices.isEmpty
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : ListView.separated(
                    itemCount: _voices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final voice = _voices[index];
                      final isSelected = _selectedVoiceId == voice.id;
                      return _buildVoiceCard(voice, isSelected, theme, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceCard(
      Voice voice, bool isSelected, ThemeData theme, bool isDark) {
    return InkWell(
      onTap: () => setState(() => _selectedVoiceId = voice.id),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.1)
              : (isDark
                  ? Colors.white.withOpacity(0.02)
                  : Colors.black.withOpacity(0.02)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withOpacity(0.5)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: isSelected
                  ? theme.colorScheme.primary
                  : (isDark ? Colors.white10 : Colors.black12),
              child: Icon(
                voice.type == 'preset'
                    ? Icons.face_rounded
                    : Icons.person_add_rounded,
                color: isSelected
                    ? Colors.white
                    : theme.colorScheme.onSurface.withOpacity(0.5),
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    voice.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  Text(
                    voice.type == 'preset' ? "Hệ thống" : "Tùy chỉnh",
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded,
                  color: theme.colorScheme.primary, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Audio Result Panel ──
  Widget _buildAudioResultPanel(ThemeData theme, bool isDark) {
    return _GlassPanel(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.audio_file_rounded,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                "Kết quả Audio",
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (_audioBytes != null) ...[
                const Spacer(),
                InkWell(
                  onTap: _downloadAudio,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_rounded,
                            size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          "Tải về",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // Content
          if (_audioBytes != null)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: WaveformPlayer(
                    key: ValueKey(_audioBytes.hashCode),
                    audioBytes: _audioBytes!,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_none_rounded,
                        size: 28,
                        color:
                            theme.colorScheme.onSurface.withOpacity(0.15)),
                    const SizedBox(height: 8),
                    Text(
                      "Sẵn sàng",
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// VOICE LAB VIEW
// ════════════════════════════════════════════════════════════════
class VoiceLabView extends StatefulWidget {
  const VoiceLabView({super.key});

  @override
  State<VoiceLabView> createState() => _VoiceLabViewState();
}

class _VoiceLabViewState extends State<VoiceLabView>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _nameController = TextEditingController();
  File? _selectedFile;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      setState(() => _selectedFile = File(result.files.single.path!));
    }
  }

  Future<void> _createVoice() async {
    if (_nameController.text.isEmpty || _selectedFile == null) return;
    setState(() => _isUploading = true);
    try {
      final newVoice = await TtsService.createVoice(
        _nameController.text,
        _selectedFile!,
        onProgress: (progress) {
          if (mounted) setState(() => _uploadProgress = progress);
        },
      );
      if (mounted) {
        CustomSnackBar.showSuccess(
          context,
          "Giọng nói '${newVoice.name}' đã được tạo thành công!",
        );
        setState(() {
          _nameController.clear();
          _selectedFile = null;
          _uploadProgress = 0.0;
        });
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, "Lỗi tạo giọng: $e");
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _GlassPanel(
            isDark: isDark,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Icon ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.mic_external_on_rounded,
                      size: 36, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 20),
                // ── Title ──
                Text(
                  "Tạo Bản sao Giọng nói",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Tải lên file ghi âm mẫu (10-30 giây) để AI học và tạo ra bản sao giọng nói của chính bạn.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.45),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                // ── Voice Name Input ──
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Tên giọng nói",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black26
                            : Colors.black.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextField(
                        controller: _nameController,
                        style: const TextStyle(fontSize: 13),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: "Ví dụ: Giọng của tôi",
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.2),
                          ),
                          prefixIcon: Icon(Icons.edit_rounded,
                              size: 18,
                              color: theme.colorScheme.primary
                                  .withOpacity(0.5)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // ── File Picker ──
                InkWell(
                  onTap: _pickAudio,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.02)
                          : Colors.black.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _selectedFile != null
                            ? theme.colorScheme.primary.withOpacity(0.5)
                            : theme.colorScheme.onSurface.withOpacity(0.08),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedFile != null
                              ? Icons.audio_file_rounded
                              : Icons.upload_rounded,
                          size: 22,
                          color: _selectedFile != null
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface.withOpacity(0.3),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedFile != null
                                    ? "Sẵn sàng tải lên"
                                    : "Chọn file mẫu",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedFile != null
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurface
                                          .withOpacity(0.5),
                                ),
                              ),
                              if (_selectedFile != null)
                                Text(
                                  _selectedFile!.path.split('/').last,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.3),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (_selectedFile != null)
                          InkWell(
                            onTap: () =>
                                setState(() => _selectedFile = null),
                            child: Icon(Icons.close_rounded,
                                size: 18,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.4)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                // ── Create Button ──
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _isUploading ||
                            _nameController.text.isEmpty ||
                            _selectedFile == null
                        ? null
                        : _createVoice,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    child: _isUploading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  value: _uploadProgress,
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(_uploadProgress * 100).toInt()}%',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          )
                        : const Text(
                            "Tiến hành Clone Giọng nói",
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
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
}

// ════════════════════════════════════════════════════════════════
// SHARED GLASS PANEL WIDGET
// ════════════════════════════════════════════════════════════════
class _GlassPanel extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const _GlassPanel({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.02) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: child,
    );
  }
}
