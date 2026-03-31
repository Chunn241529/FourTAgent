import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
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
            debugPrint('FloatingMusicPlayer init: screen size=$size');
            // Default to top-right: specific padding from right
            double initialX = size.width - 220; // 200 width + 20 padding
            // Safety check
            if (initialX < 0) initialX = 20; 
            
            // debugPrint('FloatingMusicPlayer: Setting initial position to $initialX, 100');
            player.updatePosition(initialX, 100);
          });
          // Return hidden while setting position to avoid jump
          return const SizedBox.shrink();
        }
        
        // debugPrint('FloatingMusicPlayer: building at ${player.posX}, ${player.posY}, visible=${player.isVisible}');
        
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
            color: theme.colorScheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
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
                            placeholder: (_, ___) => _buildMusicIcon(theme),
                            errorWidget: (_, ___, ____) => _buildMusicIcon(theme),
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
              // Repeat indicator (mini) - to the right of pause button
              if (player.repeatMode != RepeatMode.off)
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4),
                  child: Icon(
                    player.repeatMode == RepeatMode.all ? Icons.repeat_rounded : Icons.repeat_one_rounded,
                    size: 14,
                    color: theme.colorScheme.primary.withValues(alpha: 0.8),
                  ),
                ),
              const SizedBox(width: 8),
              // Close button
              IconButton(
                onPressed: () => player.hideAndStop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 8),
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
            color: theme.colorScheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  IconButton(
                    onPressed: () => player.hideAndStop(),
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Album art
              Container(
                width: 100,
                height: 100,
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
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
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
              const SizedBox(height: 12),
              // Title
              Text(
                player.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: theme.colorScheme.onSurface,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              // Progress bar
              Row(
                children: [
                  // Time current
                  Text(
                    _formatDuration(player.position),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Slider
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: theme.colorScheme.primary,
                        inactiveTrackColor: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                        thumbColor: theme.colorScheme.primary,
                      ),
                      child: Slider(
                        value: player.position.inSeconds.toDouble().clamp(0, player.duration.inSeconds.toDouble().clamp(1, double.infinity)),
                        max: player.duration.inSeconds.toDouble().clamp(1, double.infinity),
                        onChanged: (value) => player.seek(Duration(seconds: value.toInt())),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Time total
                  Text(
                    _formatDuration(player.duration),
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   // Repeat Toggle - Far Left
                   IconButton(
                     onPressed: () => player.toggleRepeatMode(),
                     icon: Icon(
                       _getRepeatIcon(player.repeatMode),
                       color: player.repeatMode == RepeatMode.off 
                           ? theme.colorScheme.onSurface.withValues(alpha: 0.4) 
                           : theme.colorScheme.primary,
                       size: 22,
                     ),
                     padding: EdgeInsets.zero,
                     constraints: const BoxConstraints(),
                     tooltip: 'Repeat Mode',
                   ),
                   const SizedBox(width: 20),
                   
                   // PREV Button
                   IconButton(
                     onPressed: (player.queueIndex > 0) ? () => player.playPrevious() : null,
                     icon: Icon(Icons.skip_previous_rounded, 
                       color: (player.queueIndex > 0) ? theme.colorScheme.primary : theme.disabledColor),
                     iconSize: 32,
                     padding: EdgeInsets.zero,
                     constraints: const BoxConstraints(),
                   ),
                   const SizedBox(width: 16),
                  
                  // Play/pause button
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary,
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: player.isLoading ? null : () => player.toggle(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
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

                   const SizedBox(width: 16),
                   // NEXT Button
                   IconButton(
                     onPressed: (player.queue.isNotEmpty) ? () => player.playNext() : null,
                     icon: Icon(Icons.skip_next_rounded, 
                        color: (player.queue.isNotEmpty) ? theme.colorScheme.primary : theme.disabledColor),
                     iconSize: 32,
                     padding: EdgeInsets.zero,
                     constraints: const BoxConstraints(),
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
        color: Colors.white.withValues(alpha: 0.9),
        size: 28,
      ),
    );
  }

  Widget _buildLargeMusicIcon(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white.withValues(alpha: 0.9),
        size: 48,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  IconData _getRepeatIcon(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return Icons.repeat_rounded;
      case RepeatMode.one:
        return Icons.repeat_one_rounded;
      case RepeatMode.all:
        return Icons.repeat_rounded;
    }
  }
}
