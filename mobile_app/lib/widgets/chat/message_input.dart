import 'dart:io'; // Read file from path
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For RawKeyboardListener / KeyboardListener
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import '../common/custom_snackbar.dart';

/// Modern message input - input on top, icons on bottom
class MessageInput extends StatefulWidget {
  final Function(String) onSend;
  final Function(String, String?)? onSendWithFile; // message, base64 file
  final bool isLoading;
  final VoidCallback? onStop;
  final VoidCallback? onMusicTap;
  final bool voiceModeEnabled;
  final ValueChanged<bool>? onVoiceModeChanged;

  const MessageInput({
    super.key,
    required this.onSend,
    this.onSendWithFile,
    this.isLoading = false,
    this.onStop,
    this.onMusicTap,
    this.voiceModeEnabled = false,
    this.onVoiceModeChanged,
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
  Uint8List? _selectedImageBytes; // Image bytes for upload
  String? _selectedFileName;
  Uint8List? _selectedFileBytes; // File bytes for upload
  String? _recordedAudioPath;
  
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
  // Maximum image size in bytes (5MB)
  static const int _maxImageSizeBytes = 5 * 1024 * 1024;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    // Pick with compression to reduce size
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 80, // Compress to 80% quality
    );
    if (picked != null) {
      // Read bytes for upload
      final bytes = await picked.readAsBytes();
      
      // Check file size
      if (bytes.length > _maxImageSizeBytes) {
        // Show error dialog
        if (mounted) {
          CustomSnackBar.showError(
            context,
            'Ảnh quá lớn (${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB). Tối đa 5MB.',
          );
        }
        return;
      }
      
      setState(() {
        _selectedImagePath = picked.path;
        _selectedImageBytes = bytes;
        _selectedFileName = null;
        _selectedFileBytes = null;
        _recordedAudioPath = null;
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true, // Request bytes for web compatibility
    );
    
    if (result != null) {
      final file = result.files.single;
      Uint8List? fileBytes = file.bytes;
      
      // On mobile, bytes might be null, read from path
      if (fileBytes == null && file.path != null && !kIsWeb) {
        try {
          fileBytes = await File(file.path!).readAsBytes();
        } catch (e) {
          print("Error reading file: $e");
        }
      }

      if (fileBytes != null) {
        setState(() {
          _selectedFileName = file.name;
          _selectedFileBytes = fileBytes;
          _selectedImagePath = null;
          _recordedAudioPath = null;
        });
      }
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
        if (mounted && !kIsWeb) {
           CustomSnackBar.showError(context, 'Lỗi quyền truy cập microphone');
        }
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

  void _send() async {
    final text = _controller.text.trim();
    
    // Check if we have content to send
    final hasContent = text.isNotEmpty || 
                       _selectedImageBytes != null || 
                       _selectedFileBytes != null || 
                       _recordedAudioPath != null;
                       
    if (!hasContent) return;
    
    String message = text;
    String? fileBase64;
    
    // Encode image/file to base64 with data URL prefix for backend detection
    if (_selectedImageBytes != null) {
      final rawBase64 = base64Encode(_selectedImageBytes!);
      // Add data URL prefix so backend recognizes as image
      fileBase64 = 'data:image/jpeg;base64,$rawBase64';
      if (text.isEmpty) {
        message = '[Đã gửi hình ảnh]';
      }
    } else if (_selectedFileBytes != null) {
      final rawBase64 = base64Encode(_selectedFileBytes!);
      // Determine MIME type based on extension (simple check)
      String mimeType = 'application/octet-stream';
      if (_selectedFileName != null) {
        final lowerName = _selectedFileName!.toLowerCase();
        if (lowerName.endsWith('.pdf')) mimeType = 'application/pdf';
        else if (lowerName.endsWith('.doc')) mimeType = 'application/msword';
        else if (lowerName.endsWith('.docx')) mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        else if (lowerName.endsWith('.txt')) mimeType = 'text/plain';
        else if (lowerName.endsWith('.csv')) mimeType = 'text/csv';
      }
      
      fileBase64 = 'data:$mimeType;base64,$rawBase64';
      if (text.isEmpty) {
        message = '[Đã gửi file: $_selectedFileName]';
      }
    }
    
    // Use onSendWithFile if available and we have a file
    if (widget.onSendWithFile != null && fileBase64 != null) {
      widget.onSendWithFile!(message, fileBase64);
    } else {
      widget.onSend(message);
    }
    
    _controller.clear();
    setState(() {
      _selectedImagePath = null;
      _selectedImageBytes = null;
      _selectedFileName = null;
      _selectedFileBytes = null;
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
        color: isDark ? const Color(0xFF525252) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF565869) : const Color(0xFFD1D5DB),
          width: 1,
        ),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
              : Focus(
                  onKeyEvent: (node, event) {
                    // Check for Enter key without Shift (Shift+Enter for new line)
                    if (event is KeyDownEvent && 
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      // Prevent default newline and send message
                      if (_hasText && !widget.isLoading) {
                        _send();
                      }
                      // Return handled to prevent Enter from being added to TextField
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    minLines: 3,
                    textInputAction: TextInputAction.newline,
                    textAlignVertical: TextAlignVertical.top,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      hintText: 'Nhắn tin cho Lumina AI...',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    ),
                    enabled: !widget.isLoading,
                  ),
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
                  // _IconBtn(
                  //   icon: _isListening ? Icons.mic : Icons.mic_none_outlined,
                  //   onTap: _toggleRecording,
                  //   color: (_isListening || _recordedAudioPath != null) ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.5),
                  // ),
                  // if (widget.onMusicTap != null)
                  //   _IconBtn(
                  //     icon: Icons.music_note_outlined,
                  //     onTap: widget.onMusicTap!,
                  //     color: theme.colorScheme.onSurface.withOpacity(0.5),
                  //   ),
                  // Voice Mode Toggle
                  _IconBtn(
                    icon: widget.voiceModeEnabled 
                        ? Icons.record_voice_over 
                        : Icons.voice_over_off_outlined,
                    onTap: () => widget.onVoiceModeChanged?.call(!widget.voiceModeEnabled),
                    color: widget.voiceModeEnabled 
                        ? theme.colorScheme.primary 
                        : theme.colorScheme.onSurface.withOpacity(0.5),
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
