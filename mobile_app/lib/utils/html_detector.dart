/// Utility class to detect and handle HTML/CSS/JS content
class HtmlDetector {
  /// List of HTML tags to detect
  static final _htmlTagPattern = RegExp(
    r'<(!DOCTYPE|html|head|body|div|span|p|h[1-6]|script|style|link|img|a|ul|ol|li|table|form|input|button|nav|header|footer|main|section|article)',
    caseSensitive: false,
  );

  /// Pattern for CSS content
  static final _cssPattern = RegExp(
    r'[\w\-\.#\[\]]+\s*\{[^}]+\}',
    multiLine: true,
  );

  /// Pattern for JS content
  static final _jsPattern = RegExp(
    r'(function\s+\w+|const\s+\w+\s*=|let\s+\w+\s*=|var\s+\w+\s*=|=>\s*\{|document\.|window\.|addEventListener)',
  );

  /// Pattern for markdown code blocks with frontend languages
  static final _markdownFrontendPattern = RegExp(
    r'```(html|css|javascript|js|htm|jsx|tsx|vue|svelte)',
    caseSensitive: false,
  );

  /// Check if content contains HTML tags
  static bool isHtmlContent(String content) {
    return _htmlTagPattern.hasMatch(content);
  }

  /// Check if content is CSS
  static bool isCssContent(String content) {
    return _cssPattern.hasMatch(content) && !isHtmlContent(content);
  }

  /// Check if content is JavaScript
  static bool isJsContent(String content) {
    return _jsPattern.hasMatch(content) && !isHtmlContent(content);
  }

  /// Check if content is any frontend code (HTML/CSS/JS)
  static bool isFrontendCode(String content) {
    if (content.isEmpty) return false;
    
    // Check for explicit HTML structure
    if (isHtmlContent(content)) return true;
    
    // Check for embedded style/script tags
    if (content.contains('<style>') || content.contains('<script>')) return true;
    
    // Check for markdown code blocks with frontend languages
    if (_markdownFrontendPattern.hasMatch(content)) return true;
    
    // Check for standalone CSS or JS
    if (isCssContent(content) || isJsContent(content)) return true;
    
    return false;
  }

  /// Check if content has JavaScript that needs browser execution
  static bool containsJavaScript(String content) {
    return content.contains('<script') || 
           _jsPattern.hasMatch(content) ||
           RegExp(r'```(javascript|js)', caseSensitive: false).hasMatch(content);
  }

  /// Extract HTML from markdown code block if present
  static String? extractHtmlFromMarkdown(String content) {
    final htmlBlockPattern = RegExp(
      r'```(?:html|htm)\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    final match = htmlBlockPattern.firstMatch(content);
    return match?.group(1)?.trim();
  }

  /// Extract CSS from markdown code block if present
  static String? extractCssFromMarkdown(String content) {
    final cssBlockPattern = RegExp(
      r'```css\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    final match = cssBlockPattern.firstMatch(content);
    return match?.group(1)?.trim();
  }

  /// Extract JS from markdown code block if present
  static String? extractJsFromMarkdown(String content) {
    final jsBlockPattern = RegExp(
      r'```(?:javascript|js)\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    final match = jsBlockPattern.firstMatch(content);
    return match?.group(1)?.trim();
  }

  /// Wrap content in HTML template if needed
  static String wrapAsHtml(String content) {
    // Check if it's a full HTML document wrapped in markdown
    // We strip the markdown wrapper first to get the raw HTML
    if (content.trim().startsWith('```') && (content.contains('<html') || content.contains('<!DOCTYPE'))) {
      return stripMarkdownWrapper(content);
    }

    // Already has HTML structure (and wasn't wrapped, or wrapper was stripped above)
    if (content.contains('<html') || content.contains('<!DOCTYPE')) {
      return content;
    }
    
    // Check for markdown code blocks
    final extractedHtml = extractHtmlFromMarkdown(content);
    final extractedCss = extractCssFromMarkdown(content);
    final extractedJs = extractJsFromMarkdown(content);
    
    // If we have markdown code blocks, combine them
    if (extractedHtml != null || extractedCss != null || extractedJs != null) {
      return _buildHtmlDocument(
        body: extractedHtml ?? '',
        css: extractedCss,
        js: extractedJs,
      );
    }
    
    // Check for <body>, <head>, or standalone tags
    if (content.contains('<body') || content.contains('<head')) {
      return '''<!DOCTYPE html>
<html>
$content
</html>''';
    }
    
    // Pure CSS content
    if (isCssContent(content)) {
      return _buildHtmlDocument(
        body: '<div class="preview">CSS Preview - Add HTML elements to see styles</div>',
        css: content,
      );
    }
    
    // Pure JS content
    if (isJsContent(content)) {
      return _buildHtmlDocument(
        body: '<div id="output"></div>',
        js: content,
      );
    }
    
    // Wrap as body content
    // Try to strip markdown wrapper if present, as fallback
    final strippedContent = stripMarkdownWrapper(content);
    return _buildHtmlDocument(body: strippedContent);
  }

  /// Strip markdown code block markers if the content is wrapped in them
  static String stripMarkdownWrapper(String content) {
    content = content.trim();
    
    // Check and remove starting ```tag
    if (content.startsWith('```')) {
      // Find the end of the first line or first whitespace group to determine lang tag end
      final newlineIndex = content.indexOf('\n');
      if (newlineIndex != -1) {
        // Remove everything up to the first newline
        content = content.substring(newlineIndex + 1);
      } else {
        // Single line? Just remove the ``` and optional word
        content = content.replaceFirst(RegExp(r'^```\w*\s*'), '');
      }
    }
    
    // Check and remove ending ```
    if (content.endsWith('```')) {
       content = content.substring(0, content.length - 3);
    }
    
    return content.trim();
  }

  /// Build a complete HTML document
  static String _buildHtmlDocument({
    required String body,
    String? css,
    String? js,
  }) {
    final styleBlock = css != null ? '<style>\n$css\n</style>' : '';
    final scriptBlock = js != null ? '<script>\n$js\n</script>' : '';
    
    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  $styleBlock
</head>
<body>
$body
$scriptBlock
</body>
</html>''';
  }
}
