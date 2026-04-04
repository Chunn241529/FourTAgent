import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../utils/wav_parser.dart';

class WaveformPlayer extends StatefulWidget {
  final Uint8List audioBytes; // Raw WAV bytes
  final VoidCallback? onDispose;
  
  const WaveformPlayer({
    super.key,
    required this.audioBytes,
    this.onDispose,
  });

  @override
  State<WaveformPlayer> createState() => _WaveformPlayerState();
}

class _WaveformPlayerState extends State<WaveformPlayer> {
  late AudioPlayer _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  List<double> _amplitudes = [];
  bool _isDragging = false;
  bool _isReady = false;
  String? _tempFilePath;
  
  // Cache the waveform samples to avoid re-parsing on every build
  static const int _waveformResolution = 100;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _parseWaveform();
    _initAudio();
    
    // Listeners
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });

    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _player.onPositionChanged.listen((p) {
      if (mounted && !_isDragging) {
        setState(() => _position = p);
      }
    });

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }
  
  Future<void> _initAudio() async {
    try {
      // Write audio bytes to a temp file — BytesSource is unreliable on Linux desktop
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/tts_preview_${DateTime.now().millisecondsSinceEpoch}.wav');
      await tempFile.writeAsBytes(widget.audioBytes);
      _tempFilePath = tempFile.path;
      
      // Set source from file
      await _player.setSource(DeviceFileSource(tempFile.path));

      // Try to get duration from WAV header as fallback
      if (_duration == Duration.zero) {
        final wavDuration = WavParser.getDuration(widget.audioBytes);
        if (wavDuration != null && mounted) {
          setState(() => _duration = wavDuration);
        }
      }

      if (mounted) {
        setState(() => _isReady = true);
      }
    } catch (e) {
      debugPrint('WaveformPlayer: Failed to init audio: $e');
    }
  }

  void _parseWaveform() {
    _amplitudes = WavParser.getAmplitudes(widget.audioBytes, samples: _waveformResolution);
  }

  @override
  void dispose() {
    _player.dispose();
    // Clean up temp file
    if (_tempFilePath != null) {
      try {
        File(_tempFilePath!).deleteSync();
      } catch (_) {}
    }
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Waveform & Seek Area
          SizedBox(
            height: 80,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onHorizontalDragStart: (details) => _isDragging = true,
                  onHorizontalDragEnd: (details) {
                    _isDragging = false;
                    _seekTo(details.localPosition.dx, constraints.maxWidth);
                  },
                  onHorizontalDragUpdate: (details) {
                    _updateDragPosition(details.localPosition.dx, constraints.maxWidth);
                  },
                  onTapDown: (details) => _seekTo(details.localPosition.dx, constraints.maxWidth),
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 80),
                    painter: WaveformPainter(
                      amplitudes: _amplitudes,
                      progress: _duration.inMilliseconds > 0 
                          ? _position.inMilliseconds / _duration.inMilliseconds 
                          : 0.0,
                      waveColor: Theme.of(context).primaryColor.withOpacity(0.3),
                      progressColor: Theme.of(context).primaryColor,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(_position), style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
              
              IconButton(
                onPressed: _isReady ? _togglePlayPause : null,
                icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                iconSize: 48,
                color: _isReady 
                    ? Theme.of(context).primaryColor 
                    : Theme.of(context).disabledColor,
              ),
              
              Text(_formatDuration(_duration), style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_position == Duration.zero || _position >= _duration) {
        if (_tempFilePath != null) {
          await _player.play(DeviceFileSource(_tempFilePath!));
          return;
        }
      }
      await _player.resume();
    }
  }
  
  void _seekTo(double dx, double width) {
    if (_duration.inMilliseconds == 0) return;
    
    // Clamp
    double relative = (dx / width).clamp(0.0, 1.0);
    final pos = Duration(milliseconds: (_duration.inMilliseconds * relative).round());
    _player.seek(pos);
  }

  void _updateDragPosition(double dx, double width) {
     if (_duration.inMilliseconds == 0) return;
     double relative = (dx / width).clamp(0.0, 1.0);
     setState(() {
       _position = Duration(milliseconds: (_duration.inMilliseconds * relative).round());
     });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }
}

// Custom Painter
class WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;
  final Color waveColor;
  final Color progressColor;

  WaveformPainter({
    required this.amplitudes,
    required this.progress,
    required this.waveColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final double width = size.width;
    final double height = size.height;
    final double midY = height / 2;
    
    if (amplitudes.isEmpty) return;
    
    // Calculate bar width (with spacing)
    final int count = amplitudes.length;
    final double barWidth = width / count;
    final double spacing = barWidth * 0.2;
    final double effectiveBarWidth = barWidth - spacing;
    
    for (int i = 0; i < count; i++) {
      double amp = amplitudes[i];
      // Min height for visibility
      double barHeight = (height * 0.8) * amp;
      if (barHeight < 2) barHeight = 2;
      
      double x = i * barWidth + spacing / 2;
      double top = midY - barHeight / 2;
      double bottom = midY + barHeight / 2;

      // Color depends on progress
      double progressX = progress * width;
      
      if (x < progressX) {
        paint.color = progressColor;
      } else {
        paint.color = waveColor;
      }

      RRect barRect = RRect.fromRectAndRadius(
         Rect.fromLTRB(x, top, x + effectiveBarWidth, bottom),
         Radius.circular(effectiveBarWidth / 2)
      );
      canvas.drawRRect(barRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
     return oldDelegate.progress != progress || oldDelegate.amplitudes != amplitudes;
  }
}
