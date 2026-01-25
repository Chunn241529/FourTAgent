import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Professional Voice Agent UI with animated orb
class VoiceAgentOverlay extends StatefulWidget {
  final bool isActive;
  final bool isPlaying;
  final bool isProcessing;
  final bool isRecording;
  final VoidCallback? onClose;
  final VoidCallback? onMicPressed;
  final VoidCallback? onMicReleased;
  final VoidCallback? onVoiceSwitch;
  final String? currentSentence;
  final String? currentVoice;

  const VoiceAgentOverlay({
    super.key,
    required this.isActive,
    required this.isPlaying,
    required this.isProcessing,
    this.isRecording = false,
    this.onClose,
    this.onMicPressed,
    this.onMicReleased,
    this.onVoiceSwitch,
    this.currentSentence,
    this.currentVoice,
  });

  @override
  State<VoiceAgentOverlay> createState() => _VoiceAgentOverlayState();
}

class _VoiceAgentOverlayState extends State<VoiceAgentOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _glowController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    
    // Pulse animation for the orb
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Wave animation for sound visualization
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat();

    // Glow animation
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      color: isDark ? Colors.black.withOpacity(0.95) : Colors.white.withOpacity(0.98),
      child: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: isDark
                    ? [
                        const Color(0xFF1a1a2e),
                        const Color(0xFF0f0f1a),
                      ]
                    : [
                        Colors.white,
                        Colors.grey.shade100,
                      ],
              ),
            ),
          ),
          

          
          // Main orb in center
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Orb
                AnimatedBuilder(
                  animation: Listenable.merge([_pulseController, _glowController]),
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer glow rings
                        if (widget.isPlaying) ...[
                          _buildGlowRing(180, _glowAnimation.value * 0.3, isDark),
                          _buildGlowRing(160, _glowAnimation.value * 0.5, isDark),
                          _buildGlowRing(140, _glowAnimation.value * 0.7, isDark),
                        ],
                        
                        // Wave visualization
                        if (widget.isPlaying)
                          AnimatedBuilder(
                            animation: _waveController,
                            builder: (context, child) {
                              return CustomPaint(
                                size: const Size(200, 200),
                                painter: WaveformPainter(
                                  progress: _waveController.value,
                                  color: isDark 
                                      ? const Color(0xFF00D9FF) 
                                      : const Color(0xFF0066CC),
                                  isPlaying: widget.isPlaying,
                                ),
                              );
                            },
                          ),
                        
                        // Main orb
                        Transform.scale(
                          scale: widget.isPlaying ? _pulseAnimation.value : 1.0,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: widget.isPlaying
                                    ? [
                                        const Color(0xFF00D9FF),
                                        const Color(0xFF00B4D8),
                                        const Color(0xFF0077B6),
                                      ]
                                    : isDark
                                        ? [
                                            Colors.grey.shade700,
                                            Colors.grey.shade800,
                                          ]
                                        : [
                                            Colors.grey.shade300,
                                            Colors.grey.shade400,
                                          ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.isPlaying
                                      ? const Color(0xFF00D9FF).withOpacity(_glowAnimation.value)
                                      : Colors.transparent,
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: Icon(
                              widget.isPlaying 
                                  ? Icons.graphic_eq 
                                  : Icons.mic_none,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                
                const SizedBox(height: 40),
                
                // Status text logic
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    widget.isPlaying 
                        ? 'Đang nói...' 
                        : widget.isProcessing 
                            ? 'Đang suy nghĩ...' 
                            : 'Đang lắng nghe...',
                    key: ValueKey('${widget.isPlaying}${widget.isProcessing}'),
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Current sentence display
                if (widget.currentSentence != null && widget.currentSentence!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      widget.currentSentence!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black45,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),

          // Bottom Control Bar (Floating & Compact)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black12,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Back
                    _buildControlButton(
                      context,
                      icon: Icons.close, // Used Close icon as in typical floating bars, or use arrow_back
                      onTap: widget.onClose,
                      tooltip: 'Thoát',
                      isDark: isDark,
                    ),
                    
                    const SizedBox(width: 24),
                    
                    // Mic (Center) - Hold to Talk
                    GestureDetector(
                      onTapDown: (_) => widget.onMicPressed?.call(),
                      onTapUp: (_) => widget.onMicReleased?.call(),
                      onTapCancel: () => widget.onMicReleased?.call(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(16), // Larger touch area
                        decoration: BoxDecoration(
                          color: widget.isRecording 
                              ? Colors.red 
                              : (isDark ? const Color(0xFF00D9FF) : const Color(0xFF0066CC)),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (widget.isRecording 
                                  ? Colors.red 
                                  : (isDark ? const Color(0xFF00D9FF) : const Color(0xFF0066CC)))
                                  .withOpacity(0.4),
                              blurRadius: widget.isRecording ? 25 : 8,
                              spreadRadius: widget.isRecording ? 6 : 1,
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.isRecording ? Icons.mic : Icons.mic_none, // Icon stays mic but changes style
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),

                    const SizedBox(width: 24),
                    
                    // Voice Switch
                    _buildControlButton(
                      context,
                      icon: Icons.record_voice_over_outlined,
                      onTap: widget.onVoiceSwitch,
                      tooltip: 'Đổi giọng: ${widget.currentVoice ?? "Default"}',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowRing(double size, double opacity, bool isDark) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: (isDark ? const Color(0xFF00D9FF) : const Color(0xFF0066CC))
              .withOpacity(opacity),
          width: 2,
        ),
      ),
    );
  }

  Widget _buildControlButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback? onTap,
    required String tooltip,
    required bool isDark,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      color: isDark ? Colors.white70 : Colors.black54,
      iconSize: 24,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        padding: const EdgeInsets.all(12),
      ),
    );
  }
}

/// Custom painter for waveform visualization
class WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isPlaying;

  WaveformPainter({
    required this.progress,
    required this.color,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isPlaying) return;

    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Draw multiple wave circles
    for (int i = 0; i < 3; i++) {
      final waveProgress = (progress + i * 0.33) % 1.0;
      final radius = 60 + (waveProgress * 40);
      final opacity = (1 - waveProgress) * 0.6;
      
      paint.color = color.withOpacity(opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }



  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isPlaying != isPlaying;
  }
}

