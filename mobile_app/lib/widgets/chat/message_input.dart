// import 'dart:io'; // Removed for Web compatibility
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Modern message input - input on top, icons on bottom
class MessageInput extends StatefulWidget {
  final Function(String) onSend;
  final bool isLoading;
  final VoidCallback? onStop;

  const MessageInput({
    super.key,
    required this.onSend,
    this.isLoading = false,
    this.onStop,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _audioRecorder = AudioRecorder();
  
  bool _hasText = false;
  bool _isListening = false;
  
  // Attachments (Paths or Names)
  String? _selectedImagePath;
  String? _selectedFileName; // FilePicker on web might not give path, so use name
  String? _recordedAudioPath;
  // For file upload later, we might need bytes, but for now just UI
  
  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedImagePath = picked.path; // On web this is blob URL or similar
        _selectedFileName = null;
        _recordedAudioPath = null;
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _selectedFileName = result.files.single.name;
        _selectedImagePath = null;
        _recordedAudioPath = null;
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_isListening) {
      // Stop recording
      final path = await _audioRecorder.stop();
      setState(() {
        _isListening = false;
        if (path != null) {
          _recordedAudioPath = path;
          _selectedImagePath = null;
          _selectedFileName = null;
        }
      });
      print('>>> Audio recorded to: $path');
    } else {
      // Start recording
      // Check permissions (skip on web generally or handle differently)
      // Permission handler on web is limited
      
      bool hasPermission = true;
      try {
        if (!kIsWeb && !await Permission.microphone.isGranted) {
           final status = await Permission.microphone.request();
           hasPermission = status.isGranted;
        }
      } catch (e) {
        // Web might throw or return generic
        print('Permission check error (ignore on web): $e');
      }

      if (hasPermission) {
        // On Web, path is ignored by some recorders or handled by browser
        // On mobile, use temp dir
        String path = '';
        try {
           if (kIsWeb) {
             // Web doesn't use file paths the same way, but package might need something
             path = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
           } else {
             final dir = await getTemporaryDirectory();
             path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
           }
        } catch (_) {
           path = 'audio_temp.m4a'; 
        }
        
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() => _isListening = true);
      }
    }
  }

  void _send() {
    final text = _controller.text.trim();
    
    if (text.isEmpty && _selectedImagePath == null && _selectedFileName == null && _recordedAudioPath == null) return;
    
    String message = text;
    if (_selectedImagePath != null) message += '\n[Image: ${_selectedImagePath!.split('/').last}]';
    if (_selectedFileName != null) message += '\n[File: $_selectedFileName]';
    if (_recordedAudioPath != null) message += '\n[Audio: ${_recordedAudioPath!.split('/').last}]';

    widget.onSend(message);
    
    _controller.clear();
    setState(() {
      _selectedImagePath = null;
      _selectedFileName = null;
      _recordedAudioPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).viewPadding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE8E8E8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Attachments Preview
            if (_selectedImagePath != null || _selectedFileName != null || _recordedAudioPath != null)
              _buildAttachmentPreview(theme),

            // Text input or Waveform
            _isListening 
              ? _buildWaveform(theme)
              : TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  minLines: 3,
                  textInputAction: TextInputAction.newline,
                  textAlignVertical: TextAlignVertical.top,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'Nhắn tin cho FourT AI...',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  ),
                  enabled: !widget.isLoading,
                ),
            // Icons row
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 6),
              child: Row(
                children: [
                  _IconBtn(
                    icon: Icons.add_circle_outline,
                    onTap: _pickFile,
                    color: _selectedFileName != null ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                  _IconBtn(
                    icon: Icons.image_outlined,
                    onTap: _pickImage,
                    color: _selectedImagePath != null ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                  _IconBtn(
                    icon: _isListening ? Icons.mic : Icons.mic_none_outlined,
                    onTap: _toggleRecording,
                    color: (_isListening || _recordedAudioPath != null) ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                  const Spacer(),
                  widget.isLoading
                      ? _buildStopButton(theme)
                      : _buildSendButton(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview(ThemeData theme) {
     return Container(
       padding: const EdgeInsets.all(8.0),
       color: theme.colorScheme.surface.withOpacity(0.5),
       child: Row(
         children: [
           Icon(
             _selectedImagePath != null ? Icons.image : 
             _selectedFileName != null ? Icons.insert_drive_file : Icons.mic,
             color: theme.colorScheme.primary,
             size: 20,
           ),
           const SizedBox(width: 8),
           Expanded(
             child: Text(
               _selectedImagePath?.split('/').last ??
               _selectedFileName ??
               'Audio Recording',
               style: theme.textTheme.bodySmall,
               overflow: TextOverflow.ellipsis,
             ),
           ),
           IconButton(
             icon: const Icon(Icons.close, size: 18),
             onPressed: () {
               setState(() {
                 _selectedImagePath = null;
                 _selectedFileName = null;
                 _recordedAudioPath = null;
               });
             },
             padding: EdgeInsets.zero,
             constraints: const BoxConstraints(),
           ),
         ],
       ),
     );
  }


  Widget _buildWaveform(ThemeData theme) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.mic, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(10, (index) {
                return _AnimatedBar(color: theme.colorScheme.primary);
              }),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Đang nghe...',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton(ThemeData theme) {
    final canSend = _hasText && !widget.isLoading;
    
    return Material(
      color: canSend ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: canSend ? _send : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(
            Icons.arrow_upward_rounded,
            color: canSend ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.3),
            size: 20,
          ),
        ),
      ),
    );
  }
  Widget _buildStopButton(ThemeData theme) {
    return Material(
      color: theme.colorScheme.error,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: widget.onStop,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: const Icon(
            Icons.stop_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _AnimatedBar extends StatefulWidget {
  final Color color;
  const _AnimatedBar({required this.color});

  @override
  State<_AnimatedBar> createState() => _AnimatedBarState();
}

class _AnimatedBarState extends State<_AnimatedBar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300 + (100 * (0.5 - DateTime.now().millisecond / 1000).abs()).toInt()), // Randomize slightly
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 10, end: 32).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 4,
          height: _animation.value,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.6),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _IconBtn({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 22),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }
}
