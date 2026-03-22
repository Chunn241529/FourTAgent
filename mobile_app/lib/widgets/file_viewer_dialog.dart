import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/cloud_file_service.dart';
import '../services/storage_service.dart';
import '../config/api_config.dart';

class FileViewerDialog extends StatefulWidget {
  final CloudFile file;

  const FileViewerDialog({super.key, required this.file});

  /// Show the dialog for a cloud file
  static Future<void> show(BuildContext context, CloudFile file) {
    return showDialog(
      context: context,
      builder: (_) => FileViewerDialog(file: file),
    );
  }

  /// Show the dialog for a cloud path (e.g., from SmartReup output)
  static Future<void> showByPath(BuildContext context, String cloudPath) {
    final name = cloudPath.split('/').last;
    final file = CloudFile(name: name, type: 'file', size: 0, path: cloudPath);
    return show(context, file);
  }

  @override
  State<FileViewerDialog> createState() => _FileViewerDialogState();
}

class _FileViewerDialogState extends State<FileViewerDialog> {
  String? _content;
  bool _isLoading = true;
  String? _error;
  String? _token;

  // Video (media_kit)
  Player? _player;
  VideoController? _videoController;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  bool get _isVideo => CloudFileService.isVideoFile(widget.file.name);
  bool get _isImage => CloudFileService.isImageFile(widget.file.name);

  Future<void> _init() async {
    try {
      final token = await StorageService.getToken();
      if (mounted) {
        setState(() => _token = token);
      }

      if (_isVideo) {
        await _initVideo();
      } else if (_isImage) {
        if (mounted) setState(() => _isLoading = false);
      } else {
        _loadFileContent();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initVideo() async {
    try {
      final streamUrl = CloudFileService.getStreamUrl(widget.file.path);

      _player = Player();
      _videoController = VideoController(_player!);

      // Open the media with auth headers
      await _player!.open(
        Media(
          streamUrl,
          httpHeaders: {
            if (_token != null) 'Authorization': 'Bearer $_token',
          },
        ),
      );

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Không thể phát video: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFileContent() async {
    try {
      final content = await CloudFileService.downloadFile(widget.file.path);
      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Icon(
                  _isVideo
                      ? Icons.videocam
                      : _isImage
                          ? Icons.image
                          : Icons.description,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.file.name,
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError(theme)
                      : _isVideo
                          ? _buildVideo(theme)
                          : _isImage
                              ? _buildImage(theme)
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.all(8),
                                  child: _buildContent(theme),
                                ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text('Error: $_error'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _init();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildVideo(ThemeData theme) {
    if (_videoController == null) {
      return const Center(child: Text('Video not available'));
    }

    // media_kit Video widget handles all controls natively
    return Video(
      controller: _videoController!,
      controls: MaterialVideoControls,
    );
  }

  Widget _buildImage(ThemeData theme) {
    if (_token == null) return const Center(child: Text('Unauthorized'));

    final imageUrl = CloudFileService.getStreamUrl(widget.file.path);

    return Center(
      child: Image.network(
        imageUrl,
        headers: {'Authorization': 'Bearer $_token'},
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broken_image, size: 48, color: Colors.grey),
              Text('Failed to load image: $error'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_content == null) return const SizedBox.shrink();

    final isMarkdown = widget.file.name.toLowerCase().endsWith('.md');

    if (isMarkdown) {
      return MarkdownBody(data: _content!);
    }

    return SelectableText(
      _content!,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}
