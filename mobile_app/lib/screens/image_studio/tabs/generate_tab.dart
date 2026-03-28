import 'package:flutter/material.dart';
import '../../../services/image_service.dart';

class GenerateTab extends StatefulWidget {
  const GenerateTab({super.key});

  @override
  State<GenerateTab> createState() => _GenerateTabState();
}

class _GenerateTabState extends State<GenerateTab> {
  final TextEditingController _promptController = TextEditingController();
  bool _isLoading = false;
  String? _generatedImageUrl;
  String? _generatedPrompt;
  String _selectedSize = '768x768';
  final _focusNode = FocusNode();

  final List<Map<String, String>> _sizes = [
    {'value': '512x512', 'label': '1:1  512'},
    {'value': '768x768', 'label': '1:1  768'},
    {'value': '1024x1024', 'label': '1:1  1K'},
    {'value': '768x1024', 'label': '3:4'},
    {'value': '1024x768', 'label': '4:3'},
    {'value': '1080x1920', 'label': '9:16'},
  ];

  @override
  void dispose() {
    _promptController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleGenerate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _isLoading = true;
      _generatedImageUrl = null;
      _generatedPrompt = null;
    });

    try {
      final result =
          await ImageService.generateImage(prompt, size: _selectedSize);
      if (mounted) {
        setState(() {
          _generatedPrompt = result['generated_prompt'] as String?;
          final filename =
              result['image_filename'] ?? result['image_path'] ?? '';
          if (filename.toString().isNotEmpty) {
            _generatedImageUrl = ImageService.getImageUrl(filename);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
      child: Column(
        children: [
          // ── Canvas area ──
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _isLoading
                  ? _buildLoadingState(theme, isDark)
                  : _generatedImageUrl != null
                      ? _buildResultView(theme, isDark)
                      : _buildEmptyState(theme, isDark),
            ),
          ),

          const SizedBox(height: 16),

          // ── Prompt bar ──
          _buildPromptBar(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    return Container(
      key: const ValueKey('empty'),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.03)
            : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome,
                  size: 48,
                  color: theme.colorScheme.primary.withOpacity(0.5)),
            ),
            const SizedBox(height: 20),
            Text(
              'Nhập ý tưởng để tạo ảnh AI',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hỗ trợ tiếng Việt & tiếng Anh — Lumina × FLUX-2',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme, bool isDark) {
    return Container(
      key: const ValueKey('loading'),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.03)
            : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text('Đang tạo ảnh...', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Lumina đang sáng tạo cho bạn',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5))),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView(ThemeData theme, bool isDark) {
    return Container(
      key: const ValueKey('result'),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.03)
            : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Image
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Image.network(
                _generatedImageUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image,
                        size: 48, color: Colors.grey)),
              ),
            ),
          ),

          // Prompt overlay pill (top-left)
          if (_generatedPrompt != null)
            Positioned(
              left: 12,
              top: 12,
              right: 80,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _generatedPrompt!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPromptBar(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF2F2F2F)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _promptController,
              focusNode: _focusNode,
              maxLines: 2,
              minLines: 1,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Mô tả ảnh bạn muốn tạo...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.35)),
              ),
              onSubmitted: (_) => _handleGenerate(),
            ),
          ),

          const SizedBox(width: 8),

          // Size chips
          PopupMenuButton<String>(
            initialValue: _selectedSize,
            onSelected: (v) => setState(() => _selectedSize = v),
            itemBuilder: (_) => _sizes
                .map((s) => PopupMenuItem(
                    value: s['value'], child: Text(s['label']!)))
                .toList(),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.aspect_ratio,
                      size: 16,
                      color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  const SizedBox(width: 6),
                  Text(
                    _sizes.firstWhere(
                        (s) => s['value'] == _selectedSize)['label']!,
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withOpacity(0.6)),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Generate button
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _handleGenerate,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white70))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Generate'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
