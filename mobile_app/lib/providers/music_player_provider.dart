import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'dart:async';
import 'dart:io';

enum RepeatMode { off, one, all }

/// Music Player Provider - Global state for music playback
class MusicPlayerProvider extends ChangeNotifier {
  // Mobile: audioplayers
  AudioPlayer? _mobilePlayer;
  
  // Desktop: media_kit
  Player? _desktopPlayer;
  
  // Subscriptions
  final List<StreamSubscription> _subs = [];

  // Current track info
  String? _currentUrl;
  String _title = '';
  String _thumbnail = '';
  
  // Player state
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isVisible = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  RepeatMode _repeatMode = RepeatMode.all; // Default to repeat all
  
  // Floating player position
  double _posX = -1; // Use -1 to trigger auto-positioning in UI on first show
  double _posY = -1;
  bool _isExpanded = false;

  // Platform check
  bool get _isDesktop => !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  // Getters
  String get title => _title;
  String get thumbnail => _thumbnail;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get isVisible => _isVisible;
  Duration get position => _position;
  Duration get duration => _duration;
  RepeatMode get repeatMode => _repeatMode;
  double get posX => _posX;
  double get posY => _posY;
  bool get isExpanded => _isExpanded;

  MusicPlayerProvider() {
    if (_isDesktop) {
      _initDesktopPlayer();
    } else {
      _initMobilePlayer();
    }
  }

  void _initDesktopPlayer() {
    // Configure for audio only (no video window)
    _desktopPlayer = Player(
      configuration: const PlayerConfiguration(
        vo: 'null', // Disable video output on Linux/mpv
        title: 'Lumina AI Music',
        // Add better network handling
        protocolWhitelist: ['http', 'https', 'tls', 'tcp', 'file'],
        logLevel: MPVLogLevel.warn, // Reduce noise from FFmpeg
      ),
    );
    _desktopPlayer!.setVolume(100.0);

    // Listen to desktop streams
    _subs.add(_desktopPlayer!.stream.position.listen((pos) {
      _position = pos;
      notifyListeners();
    }));
    
    _subs.add(_desktopPlayer!.stream.duration.listen((dur) {
      _duration = dur;
      notifyListeners();
    }));
    
    _subs.add(_desktopPlayer!.stream.playing.listen((playing) {
      debugPrint('Desktop Player State: playing=$playing');
      _isPlaying = playing;
      if (playing) _isLoading = false;
      notifyListeners();
    }));
    
    _subs.add(_desktopPlayer!.stream.completed.listen((completed) {
      if (completed) {
        debugPrint('Desktop Player: Track completed');
        _isPlaying = false;
        _position = Duration.zero;
        notifyListeners();
        
        if (!_stoppedManually) {
          playNext();
        }
      }
    }));
    
    _subs.add(_desktopPlayer!.stream.error.listen((error) {
      debugPrint('Desktop Player Error: $error');
      // Attempt to recover from network errors
      if (_currentUrl != null && _title.isNotEmpty) {
        debugPrint('Attempting to recover from network error...');
        Future.delayed(const Duration(seconds: 2), () {
          if (!_isPlaying && _currentUrl != null) {
            playFromUrl(
              url: _currentUrl!,
              title: _title,
              thumbnail: _thumbnail.isEmpty ? null : _thumbnail,
              isQueueItem: true,
            );
          }
        });
      }
      _isLoading = false;
      notifyListeners();
    }));
    
    _subs.add(_desktopPlayer!.stream.log.listen((log) {
       // Filter out TLS noise
       final logText = log.text.toLowerCase();
       if (!logText.contains('tls') && !logText.contains('pull function')) {
         debugPrint('Desktop Player Log: $log');
       }
    }));
  }

  void _initMobilePlayer() {
    _mobilePlayer = AudioPlayer();
    
    // Listen to mobile streams
    _subs.add(_mobilePlayer!.onPositionChanged.listen((pos) {
      _position = pos;
      notifyListeners();
    }));
    
    _subs.add(_mobilePlayer!.onDurationChanged.listen((dur) {
      _duration = dur;
      notifyListeners();
    }));
    
    _subs.add(_mobilePlayer!.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      if (state == PlayerState.playing || state == PlayerState.paused) {
        _isLoading = false;
      }
      notifyListeners();
    }));
    
    _subs.add(_mobilePlayer!.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _position = Duration.zero;
      notifyListeners();
      
      if (!_stoppedManually) {
         playNext();
      }
    }));
  }

  // Queue state
  final List<Map<String, dynamic>> _queue = [];
  int _queueIndex = -1;
  
  List<Map<String, dynamic>> get queue => _queue;
  int get queueIndex => _queueIndex;
  
  // Logic to determine if we should auto-play next
  bool _stoppedManually = false;

  /// Add to queue
  void addToQueue({
    required String url,
    required String title,
    String? thumbnail,
    int? duration,
  }) {
     _queue.add({
       'url': url,
       'title': title,
       'thumbnail': thumbnail,
       'duration': duration,
     });
     notifyListeners();
  }
  
  /// Play next song in queue
  Future<void> playNext({bool autoPlay = true}) async {
    if (_queue.isEmpty) return;
    
    if (_repeatMode == RepeatMode.one && autoPlay) {
      // Repeat current song
      final track = _queue[_queueIndex.clamp(0, _queue.length - 1)];
      await playFromUrl(
        url: track['url'],
        title: track['title'],
        thumbnail: track['thumbnail'],
        duration: track['duration'],
        isQueueItem: true,
      );
      return;
    }

    int nextIndex = _queueIndex + 1;
    if (nextIndex < _queue.length) {
      _queueIndex = nextIndex;
      final track = _queue[nextIndex];
      await playFromUrl(
         url: track['url'],
         title: track['title'],
         thumbnail: track['thumbnail'],
         duration: track['duration'],
         isQueueItem: true, 
      );
    } else if (_repeatMode == RepeatMode.all) {
      // Wrap around to start
      _queueIndex = 0;
      final track = _queue[0];
      await playFromUrl(
         url: track['url'],
         title: track['title'],
         thumbnail: track['thumbnail'],
         duration: track['duration'],
         isQueueItem: true,
      );
    } else {
      stop(); // End of queue
    }
  }

  /// Play previous song
  Future<void> playPrevious() async {
    if (_queueIndex > 0) {
      _queueIndex--;
      final track = _queue[_queueIndex];
      await playFromUrl(
         url: track['url'],
         title: track['title'],
         thumbnail: track['thumbnail'],
         duration: track['duration'],
         isQueueItem: true,
      );
    }
  }

  /// Play music from URL with metadata
  Future<void> playFromUrl({
    required String url,
    required String title,
    String? thumbnail,
    int? duration,
    Duration? startTime,
    bool isQueueItem = false,
  }) async {
    debugPrint('MusicPlayerProvider: playFromUrl called for $title ($url)');
    try {
      if (!isQueueItem) {
          _queue.clear();
          _queue.add({
             'url': url,
             'title': title,
             'thumbnail': thumbnail,
             'duration': duration,
          });
          _queueIndex = 0;
      }
      
      _stoppedManually = false;
      _isLoading = true;
      _isVisible = true; // Make visible immediately
      _title = title;
      _thumbnail = thumbnail ?? '';
      _currentUrl = url;
      // Optimistic duration set (will be updated by stream)
      _duration = Duration(seconds: duration ?? 0);
      notifyListeners();

      if (_isDesktop && _desktopPlayer != null) {
        // MediaKit playback
        await _desktopPlayer!.open(Media(url), play: true);
        if (startTime != null) {
          await _desktopPlayer!.seek(startTime);
        }
      } else if (_mobilePlayer != null) {
        // AudioPlayers playback
        await _mobilePlayer?.stop();
        await _mobilePlayer?.play(UrlSource(url));
        if (startTime != null) {
          await _mobilePlayer?.seek(startTime);
        }
      }
      
    } catch (e) {
      debugPrint('Error playing music: $e');
      _isLoading = false;
      _isPlaying = false;
      notifyListeners();
    }
  }

  /// Toggle play/pause
  Future<void> toggle() async {
    if (_isDesktop && _desktopPlayer != null) {
      await _desktopPlayer!.playOrPause();
    } else if (_mobilePlayer != null) {
      if (_isPlaying) {
        await _mobilePlayer!.pause();
      } else {
        await _mobilePlayer!.resume();
      }
    }
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    if (_isDesktop && _desktopPlayer != null) {
      await _desktopPlayer!.seek(position);
    } else if (_mobilePlayer != null) {
      await _mobilePlayer!.seek(position);
    }
  }

  /// Stop playback
  Future<void> stop({bool clearQueue = false}) async {
    debugPrint('MusicPlayerProvider: stop called');
    _stoppedManually = true;
    
    try {
      if (_isDesktop && _desktopPlayer != null) {
        await _desktopPlayer!.stop();
      } else if (_mobilePlayer != null) {
        await _mobilePlayer!.stop();
      }
    } catch (e) {
      debugPrint('Error in stop execution: $e');
    }
    
    _isPlaying = false;
    _position = Duration.zero;
        
    if (clearQueue) {
      _queue.clear();
      _queueIndex = -1;
    }

    notifyListeners();
  }
  
  /// Handle control actions
  void handleControl(String action) {
    if (action == 'next_music') playNext(autoPlay: false); // Manual trigger
    if (action == 'previous_music') playPrevious();
    if (action == 'pause_music' || action == 'resume_music') toggle();
    if (action == 'stop_music') stop(clearQueue: true);
  }

  /// Toggle repeat mode
  void toggleRepeatMode() {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.one;
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.all;
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.off;
        break;
    }
    notifyListeners();
  }
  
  /// Hide the player (just hide UI, keep track info for restore)
  void hide() {
    _isVisible = false;
    // Don't call stop() to preserve track info
    notifyListeners();
  }

  /// Hide and stop the player completely
  void hideAndStop() {
    _isVisible = false;
    stop();
    notifyListeners();
  }

  /// Show the player (restore visibility)
  void show() {
    _isVisible = true;
    notifyListeners();
  }

  /// Check if there's a track loaded
  bool get hasTrack => _currentUrl != null && _title.isNotEmpty;

  /// Update floating position
  void updatePosition(double x, double y) {
    _posX = x;
    _posY = y;
    notifyListeners();
  }
  
  /// Toggle expanded mode
  void toggleExpanded() {
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  @override
  void dispose() {
    for (var sub in _subs) {
      sub.cancel();
    }
    _desktopPlayer?.dispose();
    _mobilePlayer?.dispose();
    super.dispose();
  }
}
