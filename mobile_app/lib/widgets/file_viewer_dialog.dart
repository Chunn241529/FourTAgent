import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/cloud_file_service.dart';
import '../services/storage_service.dart';
import '../config/api_config.dart';

class FileViewerDialog extends StatefulWidget {
  final CloudFile file;

  const FileViewerDialog({super.key, required this.file});

  static Future<void> show(BuildContext context, CloudFile file) {
    return showDialog(
      context: context,
      builder: (_) => FileViewerDialog(file: file),
    );
  }

  @override
  State<FileViewerDialog> createState() => _FileViewerDialogState();
}

class _FileViewerDialogState extends State<FileViewerDialog> {
  String? _content;
  bool _isLoading = true;
  String? _error;
  String? _token;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final token = await StorageService.getToken();
      if (mounted) {
        setState(() => _token = token);
      }
      
      if (_isImageFile(widget.file.name)) {
        // For images, we just need the token to build the URL headers
        if (mounted) setState(() => _isLoading = false);
      } else {
        // For text/code, download content
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
    final isImage = _isImageFile(widget.file.name);
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Icon(isImage ? Icons.image : Icons.description, color: theme.colorScheme.primary),
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
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 48),
                              const SizedBox(height: 16),
                              Text('Error loading file: $_error'),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() => _isLoading = true);
                                  if (isImage) {
                                     _init(); 
                                  } else {
                                     _loadFileContent();
                                  }
                                },
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : isImage 
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

  Widget _buildImage(ThemeData theme) {
      if (_token == null) return const Center(child: Text('Unauthorized'));
      
      final imageUrl = '${ApiConfig.baseUrl}/cloud/files/content?path=${Uri.encodeComponent(widget.file.path)}';
      
      return Center(
        child: Image.network(
          imageUrl,
          headers: {'Authorization': 'Bearer $_token'},
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
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

    // Simple extension check for Markdown
    final isMarkdown = widget.file.name.toLowerCase().endsWith('.md');
    
    if (isMarkdown) {
      return MarkdownBody(data: _content!);
    }
    
    // For code or text files, wrap in a SelectableText with monospaced font
    return SelectableText(
      _content!,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: theme.colorScheme.onSurface,
      ),
    );
  }
  
  bool _isImageFile(String filename) {
      final ext = filename.split('.').last.toLowerCase();
      return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }
}
