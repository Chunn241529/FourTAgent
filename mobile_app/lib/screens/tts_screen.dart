import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/tts_service.dart';
import '../widgets/audio/waveform_player.dart';
import '../widgets/common/custom_snackbar.dart';

class TtsScreen extends StatefulWidget {
  const TtsScreen({super.key});

  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildTopBar(theme, isDark),
          Expanded(
            child: Center(
              child: _selectedTab == 0
                  ? const SynthesisView()
                  : const VoiceLabView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
              : [const Color(0xFF667EEA), const Color(0xFF764BA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isDark ? const Color(0xFF667EEA) : const Color(0xFF667EEA))
                .withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.record_voice_over,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "TTS Engine",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      "Advanced Text-to-Speech Synthesis & Voice Lab",
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTabBar(theme),
        ],
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildTabButton(0, Icons.graphic_eq, "Synthesis"),
          const SizedBox(width: 4),
          _buildTabButton(1, Icons.science, "Voice Lab"),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final isSelected = _selectedTab == index;
    final theme = Theme.of(context);

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? (theme.brightness == Brightness.dark
                        ? const Color(0xFF667EEA)
                        : const Color(0xFF764BA2))
                    : Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? (theme.brightness == Brightness.dark
                          ? const Color(0xFF667EEA)
                          : const Color(0xFF764BA2))
                      : Colors.white70,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SynthesisView extends StatefulWidget {
  const SynthesisView({super.key});

  @override
  State<SynthesisView> createState() => _SynthesisViewState();
}

class _SynthesisViewState extends State<SynthesisView> {
  final TextEditingController _textController = TextEditingController();
  List<Voice> _voices = [];
  String? _selectedVoiceId;
  bool _isLoading = false;
  Uint8List? _audioBytes;

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
      final voices = await TtsService.getVoices();
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
        CustomSnackBar.showError(context, "Error loading voices: $e");
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
      );
      setState(() {
        _audioBytes = Uint8List.fromList(bytes);
      });
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, "Synthesis failed: $e");
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
          CustomSnackBar.showSuccess(context, 'Audio saved to: $result');
        }
        return;
      }

      final file = File('$downloadPath/$fileName');
      await file.writeAsBytes(_audioBytes!);

      if (mounted) {
        CustomSnackBar.showSuccess(context, 'Audio saved to: ${file.path}');
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, 'Download failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Reduced height to prevent touching bottom edge
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1150, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Row(
            children: [
              Expanded(child: _buildEditorPanel(theme)),
              const SizedBox(width: 12),
              SizedBox(width: 280, child: _buildControlPanel(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorPanel(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor.withOpacity(0.08)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.text_fields,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  "Text Input",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  "${_textController.text.length} / 5000",
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 13, height: 1.5),
              maxLength: 5000,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
                hintText: "Type or paste your text here...",
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.25),
                  fontSize: 13,
                ),
                counterText: "",
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Voice",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.15),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedVoiceId,
                      isExpanded: true,
                      isDense: true,
                      items: _voices
                          .map(
                            (v) => DropdownMenuItem(
                              value: v.id,
                              child: Text(
                                v.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedVoiceId = val),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _audioBytes != null
                ? _buildAudioResult(theme)
                : _buildEmptyState(theme),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              height: 38,
              child: FilledButton.icon(
                onPressed: _isLoading || _textController.text.isEmpty
                    ? null
                    : _synthesize,
                icon: _isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow, size: 16),
                label: Text(
                  _isLoading ? "Generating..." : "Generate",
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mic_none,
            size: 28,
            color: theme.colorScheme.onSurface.withOpacity(0.25),
          ),
          const SizedBox(height: 8),
          Text(
            "Ready",
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioResult(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                "Done",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.green,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: _downloadAudio,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.download,
                        size: 12,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "Save",
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: WaveformPlayer(
              key: ValueKey(_audioBytes.hashCode),
              audioBytes: _audioBytes!,
            ),
          ),
        ],
      ),
    );
  }
}

class VoiceLabView extends StatefulWidget {
  const VoiceLabView({super.key});

  @override
  State<VoiceLabView> createState() => _VoiceLabViewState();
}

class _VoiceLabViewState extends State<VoiceLabView> {
  final TextEditingController _nameController = TextEditingController();
  File? _selectedFile;
  bool _isUploading = false;

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
      );
      if (mounted) {
        CustomSnackBar.showSuccess(
          context,
          "Voice '${newVoice.name}' created!",
        );
        setState(() {
          _nameController.clear();
          _selectedFile = null;
        });
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.showError(context, "Error creating voice: $e");
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(0.12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mic,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Clone Voice",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Upload audio (10-30s) to create custom voice",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withOpacity(0.45),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: "Voice Name",
                  labelStyle: const TextStyle(fontSize: 12),
                  hintText: "Enter voice name",
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.25),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickAudio,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.25),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedFile != null
                            ? Icons.audio_file
                            : Icons.upload_rounded,
                        size: 18,
                        color: _selectedFile != null
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedFile != null
                              ? _selectedFile!.path.split('/').last
                              : "Select audio file",
                          style: TextStyle(
                            fontSize: 12,
                            color: _selectedFile != null
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface.withOpacity(0.4),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: FilledButton(
                  onPressed:
                      _isUploading ||
                          _nameController.text.isEmpty ||
                          _selectedFile == null
                      ? null
                      : _createVoice,
                  child: _isUploading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "Create Voice",
                          style: TextStyle(fontSize: 12),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
