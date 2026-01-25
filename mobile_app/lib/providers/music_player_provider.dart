import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

/// Music Player Provider - Global state for music playback
/// Cross-platform: mpv for Desktop, audioplayers for Mobile
class MusicPlayerProvider extends ChangeNotifier {
  // Desktop: mpv process
  Process? _mpvProcess;
  
  // Mobile: audioplayers
  AudioPlayer? _audioPlayer;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;
  
  // Current track info
  String? _currentUrl;
  String _title = '';
  String _thumbnail = '';
  int _totalDuration = 0;
  
  // Player state
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _isVisible = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  
  // Floating player position
  double _posX = -1;
  double _posY = 100;
  bool _isExpanded = false;
  
  // Position timer (for desktop)
  Timer? _positionTimer;

  // Platform check
  bool get _isDesktop => !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // Getters
  String get title => _title;
  String get thumbnail => _thumbnail;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get isVisible => _isVisible;
  Duration get position => _position;
  Duration get duration => _duration;
  double get posX => _posX;
  double get posY => _posY;
  bool get isExpanded => _isExpanded;

  MusicPlayerProvider() {
    if (_isMobile) {
      _initMobilePlayer();
    }
  }

  void _initMobilePlayer() {
    _audioPlayer = AudioPlayer();
    
    _positionSub = _audioPlayer!.onPositionChanged.listen((pos) {
      _position = pos;
      notifyListeners();
    });
    
    _durationSub = _audioPlayer!.onDurationChanged.listen((dur) {
      _duration = dur;
      notifyListeners();
    });
    
    _stateSub = _audioPlayer!.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      _isLoading = false;
      notifyListeners();
    });
    
    _completeSub = _audioPlayer!.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _position = Duration.zero;
      notifyListeners();
    });
  }

  /// Play music from URL with metadata
  Future<void> playFromUrl({
    required String url,
    required String title,
    String? thumbnail,
    int? duration,
    Duration? startTime,
  }) async {
    try {
      await stop();
      
      _isLoading = true;
      _isVisible = true;
      _title = title;
      _thumbnail = thumbnail ?? '';
      _totalDuration = duration ?? 0;
      _currentUrl = url;
      _duration = Duration(seconds: duration ?? 0);
      notifyListeners();

      if (_isDesktop) {
        await _playDesktop(url, startTime: startTime);
      } else if (_isMobile) {
        await _playMobile(url);
        // Mobile seek if needed - wait for load?
        // Simplifying for now
      }
      
    } catch (e) {
      debugPrint('Error playing music: $e');
      _isLoading = false;
      _isPlaying = false;
      notifyListeners();
    }
  }

  // Track mpv process generation to avoid race condition on exit callback
  int _mpvGeneration = 0;

  /// Desktop playback using mpv
  Future<void> _playDesktop(String url, {Duration? startTime}) async {
    debugPrint('Starting mpv (Desktop) with URL... Start: $startTime');
    
    // Increment generation to invalidate old exit callbacks
    _mpvGeneration++;
    final currentGen = _mpvGeneration;
    
    // Use keep-open and idle to prevent premature exit
    List<String> args = ['--no-video', '--keep-open=yes', '--idle', '--really-quiet', url];
    if (startTime != null) {
      args.add('--start=${startTime.inSeconds}');
    }

    _mpvProcess = await Process.start(
      'mpv',
      args,
      mode: ProcessStartMode.normal,
    );
    
    // Capture stderr for debugging
    _mpvProcess?.stderr.transform(const SystemEncoding().decoder).listen((data) {
      debugPrint('mpv stderr: $data');
    });
    
    // Capture stdout
    _mpvProcess?.stdout.transform(const SystemEncoding().decoder).listen((data) {
      debugPrint('mpv stdout: $data');
    });
    
    _isPlaying = true;
    _isLoading = false;
    _position = startTime ?? Duration.zero;
    notifyListeners();
    
    // Simulated position timer
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPlaying && _totalDuration > 0) {
        _position += const Duration(seconds: 1);
        if (_position.inSeconds >= _totalDuration) {
          _isPlaying = false;
          _position = Duration.zero;
          timer.cancel();
        }
        notifyListeners();
      }
    });
    
    _mpvProcess?.exitCode.then((exitCode) {
      debugPrint('mpv exited with code: $exitCode (gen=$currentGen, current=$_mpvGeneration)');
      // Only update state if this is still the current process (not an old killed one)
      if (currentGen == _mpvGeneration && _isPlaying) { 
          _isPlaying = false;
          _positionTimer?.cancel();
          notifyListeners();
      }
    });
    
    debugPrint('mpv started successfully for: $_title (gen=$currentGen)');
  }

  /// Mobile playback using audioplayers
  Future<void> _playMobile(String url) async {
    debugPrint('Starting audioplayers (Mobile) with URL...');
    
    await _audioPlayer?.stop();
    await _audioPlayer?.play(UrlSource(url));
    
    _isPlaying = true;
    _isLoading = false;
    notifyListeners();
    
    debugPrint('audioplayers started successfully for: $_title');
  }

  /// Toggle play/pause
  Future<void> toggle() async {
    if (_isDesktop) {
      // Desktop: restart since mpv simple mode doesn't support pause
      if (_isPlaying) {
        _isPlaying = false;
        _positionTimer?.cancel();
        _mpvProcess?.kill();
        notifyListeners();
      } else if (_currentUrl != null) {
        await playFromUrl(
          url: _currentUrl!,
          title: _title,
          thumbnail: _thumbnail,
          duration: _totalDuration,
          startTime: _position, // Resume from current position
        );
      }
    } else if (_isMobile && _audioPlayer != null) {
      if (_isPlaying) {
        await _audioPlayer!.pause();
      } else {
        await _audioPlayer!.resume();
      }
    }
  }

  // Seek debounce timer (for desktop)
  Timer? _seekDebounceTimer;
  Duration? _pendingSeekPosition;

  /// Seek to position
  Future<void> seek(Duration position) async {
    if (_isMobile && _audioPlayer != null) {
      await _audioPlayer!.seek(position);
    } else if (_isDesktop) {
      // Debounce seek for desktop to avoid rapid mpv restarts
      _pendingSeekPosition = position;
      _position = position; // Update UI immediately
      notifyListeners();
      
      _seekDebounceTimer?.cancel();
      _seekDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
        if (_pendingSeekPosition != null && _currentUrl != null) {
          debugPrint('Seeking on desktop (restart mpv at ${_pendingSeekPosition!.inSeconds}s)');
          // Kill current process
          _mpvProcess?.kill();
          _positionTimer?.cancel();
          
          // Restart at new position
          await _playDesktop(_currentUrl!, startTime: _pendingSeekPosition);
          _pendingSeekPosition = null;
        }
      });
    }
  }

  /// Stop playback
  Future<void> stop() async {
    _positionTimer?.cancel();
    
    if (_isDesktop && _mpvProcess != null) {
      _mpvProcess!.kill(ProcessSignal.sigkill); // Force kill
      _mpvProcess = null;
    }
    
    if (_isMobile && _audioPlayer != null) {
      await _audioPlayer!.stop();
    }
    
    _isPlaying = false;
    _position = Duration.zero;
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

  /// Show the player (restore visibility without changing track)
  void show() {
    if (_currentUrl != null && _title.isNotEmpty) {
      _isVisible = true;
      notifyListeners();
    }
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
    _positionTimer?.cancel();
    _seekDebounceTimer?.cancel();
    _mpvProcess?.kill();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }
}

