import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../utils/html_detector.dart';

class WebViewPreviewWidget extends StatefulWidget {
  final String content;
  final bool isDark;

  const WebViewPreviewWidget({
    super.key,
    required this.content,
    this.isDark = false,
  });

  @override
  State<WebViewPreviewWidget> createState() => _WebViewPreviewWidgetState();
}

class _WebViewPreviewWidgetState extends State<WebViewPreviewWidget> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(
        widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _errorMessage = 'Lỗi: ${error.description}';
              _isLoading = false;
            });
          },
        ),
      );
    _loadContent();
  }

  void _loadContent() {
    final html = HtmlDetector.wrapAsHtml(widget.content);
    _controller.loadHtmlString(html, baseUrl: null);
  }

  @override
  void didUpdateWidget(covariant WebViewPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != oldWidget.content ||
        widget.isDark != oldWidget.isDark) {
      _loadContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasJs = HtmlDetector.containsJavaScript(widget.content);

    return Column(
      children: [
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
              Icon(
                hasJs ? Icons.code : Icons.html,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasJs ? 'Đang chạy JavaScript' : 'HTML/CSS Preview',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ),
              if (_isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        Expanded(
          child: _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: theme.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : WebViewWidget(controller: _controller),
        ),
      ],
    );
  }
}
