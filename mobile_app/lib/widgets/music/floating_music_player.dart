import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/music_player_provider.dart';

/// Beautiful floating music player widget
/// Draggable, glassmorphism design, mini/expanded modes
class FloatingMusicPlayer extends StatefulWidget {
  const FloatingMusicPlayer({super.key});

  @override
  State<FloatingMusicPlayer> createState() => _FloatingMusicPlayerState();
}

class _FloatingMusicPlayerState extends State<FloatingMusicPlayer> {
  @override
  Widget build(BuildContext context) {
    return Consumer<MusicPlayerProvider>(
      builder: (context, player, _) {
        if (!player.isVisible) return const SizedBox.shrink();
        
        // Initialize position to top-right if not set
        if (player.posX == -1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final size = MediaQuery.of(context).size;
            // Default to top-right: specific padding from right
            final initialX = size.width - 220; // 200 width + 20 padding
            player.updatePosition(initialX, 100);
          });
          // Return hidden while setting position to avoid jump
          return const SizedBox.shrink();
        }
        
        return Positioned(
          left: player.posX,
          top: player.posY,
          child: GestureDetector(
            onPanUpdate: (details) {
              final size = MediaQuery.of(context).size;
              // Adjust clamp based on current width (mini or expanded)
              final width = player.isExpanded ? 280.0 : 200.0;
              final newX = (player.posX + details.delta.dx).clamp(0.0, size.width - width);
              final newY = (player.posY + details.delta.dy).clamp(0.0, size.height - 100);
              player.updatePosition(newX, newY);
            },
            child: Material(
              type: MaterialType.transparency,
              child: player.isExpanded 
                  ? _buildExpandedPlayer(context, player)
                  : _buildMiniPlayer(context, player),
            ),
          ),
        );
      },
    );
  }

  void _handleToggleExpand(BuildContext context, MusicPlayerProvider player) {
    if (!player.isExpanded) {
      // Going to expand
      final size = MediaQuery.of(context).size;
      const expandedWidth = 280.0;
      const padding = 16.0;
      
      // Check if current X + expanded width > screen width
      if (player.posX + expandedWidth > size.width) {
         // Shift left to fit, keeping some padding
         final newX = size.width - expandedWidth - padding;
         // Ensure we don't go off-screen left
         player.updatePosition(newX < 0 ? padding : newX, player.posY);
      }
    }
    player.toggleExpanded();
  }

  Widget _buildMiniPlayer(BuildContext context, MusicPlayerProvider player) {
    final theme = Theme.of(context);
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(50),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: 200,
          height: 56,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.8),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            children: [
              // Thumbnail / Album art
              GestureDetector(
                onTap: () => _handleToggleExpand(context, player),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.secondary,
                      ],
                    ),
                  ),
                  child: player.thumbnail.isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: player.thumbnail,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _buildMusicIcon(theme),
                            errorWidget: (_, __, ___) => _buildMusicIcon(theme),
                          ),
                        )
                      : _buildMusicIcon(theme),
                ),
              ),
              const SizedBox(width: 8),
              // Title
              Expanded(
                child: Text(
                  player.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              // Play/Pause button
              IconButton(
                onPressed: player.isLoading ? null : () => player.toggle(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: player.isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(
                        player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: theme.colorScheme.primary,
                      ),
              ),
              const SizedBox(width: 8),
              // Close button
              IconButton(
                onPressed: () => player.hide(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedPlayer(BuildContext context, MusicPlayerProvider player) {
    final theme = Theme.of(context);
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with minimize button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => _handleToggleExpand(context, player),
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        color: theme.colorScheme.primary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  Text(
                    'Now Playing',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  IconButton(
                    onPressed: () => player.hide(),
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Album art
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: player.thumbnail.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: player.thumbnail,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _buildLargeMusicIcon(theme),
                          errorWidget: (_, __, ___) => _buildLargeMusicIcon(theme),
                        )
                      : _buildLargeMusicIcon(theme),
                ),
              ),
              const SizedBox(height: 16),
              // Title
              Text(
                player.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 12),
              // Progress bar
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: theme.colorScheme.primary,
                  inactiveTrackColor: theme.colorScheme.onSurface.withOpacity(0.2),
                  thumbColor: theme.colorScheme.primary,
                ),
                child: Slider(
                  value: player.position.inSeconds.toDouble(),
                  max: player.duration.inSeconds.toDouble().clamp(1, double.infinity),
                  onChanged: (value) => player.seek(Duration(seconds: value.toInt())),
                ),
              ),
              // Time labels
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(player.position),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                        decoration: TextDecoration.none,
                      ),
                    ),
                    Text(
                      _formatDuration(player.duration),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => player.seek(
                      Duration(seconds: (player.position.inSeconds - 10).clamp(0, 999999)),
                    ),
                    icon: Icon(Icons.replay_10_rounded, color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(width: 8),
                  // Play/Pause button
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.secondary,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: player.isLoading ? null : () => player.toggle(),
                      icon: player.isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              player.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => player.seek(
                      Duration(seconds: player.position.inSeconds + 10),
                    ),
                    icon: Icon(Icons.forward_10_rounded, color: theme.colorScheme.onSurface),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMusicIcon(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white.withOpacity(0.9),
        size: 28,
      ),
    );
  }

  Widget _buildLargeMusicIcon(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white.withOpacity(0.9),
        size: 48,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
