import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class MusicPlayerWidget extends StatefulWidget {
  final String audioUrl;
  final String title;

  const MusicPlayerWidget({
    super.key,
    required this.audioUrl,
    required this.title,
  });

  @override
  State<MusicPlayerWidget> createState() => _MusicPlayerWidgetState();
}

class _MusicPlayerWidgetState extends State<MusicPlayerWidget> {
  late AudioPlayer _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _player.setSourceUrl(widget.audioUrl);
      
      _player.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() => _isPlaying = state == PlayerState.playing);
        }
      });

      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      });

      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      });

      _player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
          });
        }
      });
      
      if (mounted) setState(() => _isReady = true);
    } catch (e) {
      debugPrint('MusicPlayerWidget Error: $e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : const Color(0xFFF5F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2D2D44) : const Color(0xFFE5E9F2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.music_note, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'AI Generated Audio',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: _isReady
                    ? () {
                        if (_isPlaying) {
                          _player.pause();
                        } else {
                          _player.resume();
                        }
                      }
                    : null,
                icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                iconSize: 42,
                color: theme.colorScheme.primary,
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                    activeTrackColor: theme.colorScheme.primary,
                    inactiveTrackColor: theme.colorScheme.primary.withOpacity(0.2),
                    thumbColor: theme.colorScheme.primary,
                  ),
                  child: Slider(
                    value: _position.inMilliseconds.toDouble(),
                    min: 0.0,
                    max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                    onChanged: _isReady
                        ? (value) {
                            _player.seek(Duration(milliseconds: value.toInt()));
                          }
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "${_formatDuration(_position)} / ${_formatDuration(_duration)}",
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
