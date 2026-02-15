import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/tts_service.dart';
import '../widgets/audio/waveform_player.dart';
import '../widgets/common/custom_tab_selector.dart';
import '../widgets/common/custom_snackbar.dart';

class TtsScreen extends StatefulWidget {
  const TtsScreen({super.key});

  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
       if (_tabController.index != _selectedIndex) {
         setState(() => _selectedIndex = _tabController.index);
       }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, 
      body: Column(
        children: [
          const SizedBox(height: 16),
          // Header & Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Image.asset('assets/icon/icon.png'),
                ),
                const SizedBox(width: 12),
                const Text("TTS Engine", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(width: 32),
                Expanded(
                  child: CustomTabSelector(
                    tabs: const ["Synthesis", "Voice Lab"],
                    selectedIndex: _selectedIndex,
                    onTabSelected: (index) {
                      _tabController.animateTo(index);
                    },
                  ),
                ),
                const SizedBox(width: 100), 
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                SynthesisTab(),
                VoiceLabTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SynthesisTab extends StatefulWidget {
  const SynthesisTab({super.key});

  @override
  State<SynthesisTab> createState() => _SynthesisTabState();
}

class _SynthesisTabState extends State<SynthesisTab> {
  final TextEditingController _textController = TextEditingController();
  List<Voice> _voices = [];
  String? _selectedVoiceId;
  bool _isLoading = false;

  // State for WaveformPlayer
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
             _selectedVoiceId = _voices.any((v) => v.id == 'Binh') ? 'Binh' : _voices.first.id;
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
      final bytes = await TtsService.synthesize(_textController.text, _selectedVoiceId!);
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
      // Generate filename with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'tts_audio_$timestamp.mp3';
      
      // Get downloads directory
      String? downloadPath;
      if (Platform.isLinux || Platform.isMacOS) {
        downloadPath = '${Platform.environment['HOME']}/Downloads';
      } else if (Platform.isWindows) {
        downloadPath = '${Platform.environment['USERPROFILE']}\\Downloads';
      } else {
        // For mobile, use file picker to save
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
      
      // Write file for desktop
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
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Voice Selector Card
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.person_pin),
                  const SizedBox(width: 16),
                  const Text("Speaker:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedVoiceId,
                        isExpanded: true,
                        items: _voices.map((v) => DropdownMenuItem(
                          value: v.id, 
                          child: Text("${v.name} (${v.type})", overflow: TextOverflow.ellipsis)
                        )).toList(),
                        onChanged: (val) => setState(() => _selectedVoiceId = val),
                        hint: const Text("Select Voice"),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Main Input Area
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontSize: 16, height: 1.5),
              maxLength: 5000,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Enter text to synthesize...",
                alignLabelWithHint: true,
                filled: true,
                counterText: "",
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Audio Player Area (if generated)
          if (_audioBytes != null) ...[
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 const Text("Generated Audio:", style: TextStyle(fontWeight: FontWeight.bold)),
                 IconButton(
                   onPressed: _downloadAudio,
                   icon: const Icon(Icons.download_rounded),
                   tooltip: 'Download Audio',
                   style: IconButton.styleFrom(
                     backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                     foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                   ),
                 ),
               ],
             ),
             const SizedBox(height: 8),
             WaveformPlayer(
               key: ValueKey(_audioBytes.hashCode), // Rebuild if bytes change
               audioBytes: _audioBytes!,
             ),
             const SizedBox(height: 24),
          ],

          // Synthesize Button
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _synthesize,
              icon: _isLoading 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                : const Icon(Icons.auto_awesome, size: 28),
              label: Text(_isLoading ? "Synthesizing..." : "Generate Speech", style: const TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}

class VoiceLabTab extends StatefulWidget {
  const VoiceLabTab({super.key});

  @override
  State<VoiceLabTab> createState() => _VoiceLabTabState();
}

class _VoiceLabTabState extends State<VoiceLabTab> {
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
      final newVoice = await TtsService.createVoice(_nameController.text, _selectedFile!);
      if (mounted) {
        CustomSnackBar.showSuccess(context, "Voice '${newVoice.name}' created!");
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Card(
          elevation: 4,
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                   children: [
                      Icon(Icons.mic, size: 32, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 16),
                      Text("Clone New Voice", style: Theme.of(context).textTheme.headlineSmall),
                   ]
                ),
                const SizedBox(height: 16),
                const Text("Upload a short audio sample (10-30s) containing clear speech. The system will analyze it to create a custom voice profile."),
                const SizedBox(height: 32),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: "Voice Name",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label),
                  ),
                ),
                const SizedBox(height: 24),
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Colors.grey)),
                  leading: const Icon(Icons.audio_file),
                  title: Text(_selectedFile != null ? _selectedFile!.path.split('/').last : "No audio file selected"),
                  trailing: TextButton(onPressed: _pickAudio, child: const Text("BROWSE")),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _isUploading ? null : _createVoice,
                    child: _isUploading 
                       ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                       : const Text("Create Custom Voice"),
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
