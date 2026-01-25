import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../audio/waveform_player.dart';

/// Voice Message Bubble - displays AI voice response with waveform
/// Auto-plays on creation and shows animated waveform
class VoiceMessageBubble extends StatefulWidget {
  final List<Map<String, dynamic>> audioChunks;
  final bool autoPlay;

  const VoiceMessageBubble({
    super.key,
    required this.audioChunks,
    this.autoPlay = true,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  int _currentIndex = 0;
  Uint8List? _currentAudioBytes;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentChunk();
  }

  void _loadCurrentChunk() {
    if (widget.audioChunks.isEmpty) return;
    
    final chunk = widget.audioChunks[_currentIndex];
    final audioBase64 = chunk['audio'] as String?;
    
    if (audioBase64 != null) {
      setState(() {
        _currentAudioBytes = base64Decode(audioBase64);
      });
    }
  }

  void _nextChunk() {
    if (_currentIndex < widget.audioChunks.length - 1) {
      setState(() {
        _currentIndex++;
        _currentAudioBytes = null;
      });
      _loadCurrentChunk();
    }
  }

  void _prevChunk() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _currentAudioBytes = null;
      });
      _loadCurrentChunk();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (widget.audioChunks.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentChunk = widget.audioChunks[_currentIndex];
    final sentence = currentChunk['sentence'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF1A1A2E) 
            : const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? const Color(0xFF2A2A4E) 
              : const Color(0xFFD0D8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.graphic_eq,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Voice Response',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.grey[800],
                          ),
                        ),
                        Text(
                          '${_currentIndex + 1} / ${widget.audioChunks.length} segments',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey[500],
                  ),
                ],
              ),
            ),
          ),

          // Content
          if (_isExpanded) ...[
            // Sentence text
            if (sentence.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  sentence,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            const SizedBox(height: 8),

            // Audio Player
            if (_currentAudioBytes != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: WaveformPlayer(
                  key: ValueKey(_currentAudioBytes.hashCode),
                  audioBytes: _currentAudioBytes!,
                  onDispose: widget.autoPlay ? _nextChunk : null,
                ),
              ),

            // Navigation
            if (widget.audioChunks.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _currentIndex > 0 ? _prevChunk : null,
                      icon: const Icon(Icons.skip_previous),
                      iconSize: 28,
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: _currentIndex < widget.audioChunks.length - 1 
                          ? _nextChunk 
                          : null,
                      icon: const Icon(Icons.skip_next),
                      iconSize: 28,
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
