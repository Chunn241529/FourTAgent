import 'package:flutter/material.dart';
import '../../services/affiliate_service.dart';

/// Script tool panel - independent script generation.
class ScriptTool extends StatefulWidget {
  final List<dynamic> products;
  final String? selectedProductId;
  final Map<String, dynamic>? generatedScript;
  final Function(Map<String, dynamic>?)? onScriptGenerated;
  final VoidCallback? onBack;

  const ScriptTool({
    super.key,
    required this.products,
    this.selectedProductId,
    this.generatedScript,
    this.onScriptGenerated,
    this.onBack,
  });

  @override
  State<ScriptTool> createState() => _ScriptToolState();
}

class _ScriptToolState extends State<ScriptTool> {
  String _selectedStyle = 'genz';
  String _selectedDuration = '30s';
  bool _generating = false;

  Map<String, dynamic>? _generatedScript;

  @override
  void initState() {
    super.initState();
    _generatedScript = widget.generatedScript;
  }

  @override
  void didUpdateWidget(ScriptTool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.generatedScript != oldWidget.generatedScript) {
      _generatedScript = widget.generatedScript;
    }
  }

  Future<void> _generateScript() async {
    if (widget.selectedProductId == null || _generating) return;
    setState(() => _generating = true);
    try {
      final result = await AffiliateService.generateScript(
        productId: widget.selectedProductId!,
        style: _selectedStyle,
        duration: _selectedDuration,
      );
      setState(() => _generatedScript = result);
      widget.onScriptGenerated?.call(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generate error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            if (widget.onBack != null)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
            const Icon(Icons.edit_note, size: 20),
            const SizedBox(width: 8),
            Text('Script', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),

        if (widget.selectedProductId == null)
          Expanded(
            child: Center(
              child: Text(
                'Chọn một sản phẩm từ Scrape trước',
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor),
              ),
            ),
          )
        else ...[
          // Style selector
          Text('Style kịch bản', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: {
              'genz': 'GenZ 🔥',
              'formal': 'Formal 📋',
              'storytelling': 'Story 📖',
              'comparison': 'Compare ⚖️',
            }.entries.map((e) {
              return ChoiceChip(
                label: Text(e.value),
                selected: _selectedStyle == e.key,
                onSelected: (_) => setState(() => _selectedStyle = e.key),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Duration selector
          Text('Thời lượng', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: {'15s': '15 giây', '30s': '30 giây', '60s': '60 giây'}.entries.map((e) {
              return ChoiceChip(
                label: Text(e.value),
                selected: _selectedDuration == e.key,
                onSelected: (_) => setState(() => _selectedDuration = e.key),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Generate button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generating ? null : _generateScript,
              icon: _generating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(_generating ? 'Đang sinh...' : 'Generate Script'),
            ),
          ),
          const SizedBox(height: 16),

          // Generated script result
          if (_generatedScript != null)
            Expanded(
              child: Card(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.smart_toy, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '${_generatedScript!['provider']} (${_generatedScript!['model']})',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const Divider(),
                      if (_generatedScript!['script'] != null) ...[
                        _buildScriptSection('🎣 Hook', _generatedScript!['script']['hook']),
                        _buildScriptSection('📝 Nội dung', _generatedScript!['script']['body']),
                        _buildScriptSection('📢 CTA', _generatedScript!['script']['cta']),
                        const Divider(),
                        _buildScriptSection('📜 Full Script', _generatedScript!['script']['full_script']),
                        _buildScriptSection('🎬 AI Video Prompt', _generatedScript!['script']['ai_video_prompt']),
                        _buildScriptSection('📱 Caption', _generatedScript!['script']['caption']),
                        if (_generatedScript!['script']['hashtags'] != null)
                          Wrap(
                            spacing: 4,
                            children: (_generatedScript!['script']['hashtags'] as List)
                                .map((h) => Chip(label: Text(h, style: const TextStyle(fontSize: 11))))
                                .toList(),
                          ),
                      ] else
                        Text(_generatedScript!['raw_text'] ?? 'No output'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildScriptSection(String title, String? content) {
    if (content == null || content.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          SelectableText(content),
        ],
      ),
    );
  }
}
