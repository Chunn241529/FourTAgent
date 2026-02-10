import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import '../../utils/html_detector.dart';

/// Widget to preview HTML content
/// Uses flutter_widget_from_html for stability on all platforms
/// Includes "Open in Browser" button for full JavaScript/CSS support
class HtmlPreviewWidget extends StatefulWidget {
  final String content;
  final bool isDark;

  const HtmlPreviewWidget({
    super.key,
    required this.content,
    this.isDark = false,
  });

  @override
  State<HtmlPreviewWidget> createState() => _HtmlPreviewWidgetState();
}

class _HtmlPreviewWidgetState extends State<HtmlPreviewWidget> {
  String? _preparedHtml;
  bool _isLoading = true;
  String? _errorMessage;
  bool _hasJs = false;

  @override
  void initState() {
    super.initState();
    _prepareContent();
  }

  @override
  void didUpdateWidget(covariant HtmlPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != oldWidget.content) {
      _prepareContent();
    }
  }

  void _prepareContent() {
    setState(() => _isLoading = true);
    
    try {
      final html = HtmlDetector.wrapAsHtml(widget.content);
      // Check for JS using our detector
      _hasJs = HtmlDetector.containsJavaScript(widget.content);
      _preparedHtml = html;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Lỗi xử lý HTML: $e';
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _openInBrowser() async {
    if (_preparedHtml == null) return;
    
    try {
      // Use Downloads directory for better accessibility by browsers (Snap/Flatpak)
      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (e) {
        debugPrint('Could not get downloads dir: $e');
      }
      
      // Fallback to documents or temp if downloads fails
      dir ??= await getApplicationDocumentsDirectory();
      
      final file = File('${dir.path}/lumina_preview_${DateTime.now().millisecondsSinceEpoch}.html');
      await file.writeAsString(_preparedHtml!);
      
      debugPrint('Saved preview to: ${file.path}');
      
      final uri = Uri.file(file.path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        setState(() => _errorMessage = 'Không thể mở trình duyệt với path: ${file.path}');
      }
    } catch (e) {
      debugPrint('Error opening in browser: $e');
      setState(() => _errorMessage = 'Lỗi mở trình duyệt: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Preview info banner with browser button
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            border: Border(
              bottom: BorderSide(color: theme.dividerColor.withOpacity(0.3)),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _hasJs 
                    ? 'Chứa JavaScript - Mở trình duyệt để xem đầy đủ'
                    : 'Bản xem trước cơ bản',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                ),
              ),
              TextButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_browser, size: 16),
                label: const Text('Mở trình duyệt'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        // HTML content using lightweight widget
        Expanded(
          child: Container(
            color: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: HtmlWidget(
                _preparedHtml ?? '',
                textStyle: TextStyle(
                  color: widget.isDark ? Colors.white : Colors.black,
                  fontFamily: 'monospace',
                ),
                onErrorBuilder: (context, element, error) => Text('Error: $error'),
                onLoadingBuilder: (context, element, loadingProgress) => const CircularProgressIndicator(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
