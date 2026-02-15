import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ai_studio_provider.dart';

class AiSubtitleScreen extends StatelessWidget {
  const AiSubtitleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AiStudioProvider(),
      child: const _TranslatorScreenContent(),
    );
  }
}

class _TranslatorScreenContent extends StatefulWidget {
  const _TranslatorScreenContent();

  @override
  State<_TranslatorScreenContent> createState() =>
      _TranslatorScreenContentState();
}

class _TranslatorScreenContentState extends State<_TranslatorScreenContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index != _selectedIndex) {
        setState(() {
          _selectedIndex = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const SizedBox(height: 16),
          _buildHeader(theme, isDark),
          const SizedBox(height: 20),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [TranslatorTab(), ReviewScriptTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
              : [const Color(0xFF667EEA), const Color(0xFF764BA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isDark ? const Color(0xFF667EEA) : const Color(0xFF667EEA))
                .withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.translate,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Translator",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      "Dịch phụ đề & Tạo kịch bản đánh giá",
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTabBar(theme),
        ],
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildTabButton(0, Icons.subtitles, "Subtitle Translator"),
          const SizedBox(width: 4),
          _buildTabButton(1, Icons.description, "Review Script"),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    final theme = Theme.of(context);

    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? (theme.brightness == Brightness.dark
                          ? const Color(0xFF667EEA)
                          : const Color(0xFF764BA2))
                    : Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? (theme.brightness == Brightness.dark
                            ? const Color(0xFF667EEA)
                            : const Color(0xFF764BA2))
                      : Colors.white70,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TranslatorTab extends StatefulWidget {
  const TranslatorTab({super.key});

  @override
  State<TranslatorTab> createState() => _TranslatorTabState();
}

class _TranslatorTabState extends State<TranslatorTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<AiStudioProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_outputController.text != provider.translatedText &&
        provider.isTranslating) {
      _outputController.text = provider.translatedText;
    } else if (_outputController.text != provider.translatedText &&
        !provider.isTranslating &&
        provider.translatedText.isNotEmpty) {
      _outputController.text = provider.translatedText;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          _buildActionBar(provider, theme),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildInputPanel(theme, isDark)),
                const SizedBox(width: 12),
                _buildArrowIndicator(theme),
                const SizedBox(width: 12),
                Expanded(child: _buildOutputPanel(theme, isDark)),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildActionBar(AiStudioProvider provider, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildActionButton(
            icon: Icons.upload_file,
            label: "Import",
            onTap: () async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['srt', 'txt'],
              );
              if (result != null && result.files.single.path != null) {
                final content = await File(
                  result.files.single.path!,
                ).readAsString();
                _inputController.text = content;
                if (mounted)
                  context.read<AiStudioProvider>().setInputText(content);
              }
            },
            theme: theme,
          ),
          const SizedBox(width: 12),
          _buildActionButton(
            icon: provider.isTranslating
                ? Icons.hourglass_empty
                : Icons.translate,
            label: provider.isTranslating ? "Translating..." : "Translate",
            isPrimary: true,
            isLoading: provider.isTranslating,
            onTap: provider.isTranslating
                ? null
                : () {
                    context.read<AiStudioProvider>().setInputText(
                      _inputController.text,
                    );
                    context.read<AiStudioProvider>().translate();
                  },
            theme: theme,
          ),
          const Spacer(),
          _buildActionButton(
            icon: Icons.download,
            label: "Download",
            onTap: provider.translatedText.isEmpty
                ? null
                : () async {
                    String? outputFile = await FilePicker.platform.saveFile(
                      fileName: 'translated.srt',
                    );
                    if (outputFile != null)
                      await File(
                        outputFile,
                      ).writeAsString(provider.translatedText);
                  },
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required ThemeData theme,
    bool isPrimary = false,
    bool isLoading = false,
  }) {
    if (isPrimary) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }

  Widget _buildInputPanel(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.input, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  "Input",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TextField(
              controller: _inputController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
                hintText: "Paste or import subtitle content...",
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              onChanged: (val) =>
                  context.read<AiStudioProvider>().setInputText(val),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArrowIndicator(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.arrow_forward,
        color: theme.colorScheme.primary,
        size: 20,
      ),
    );
  }

  Widget _buildOutputPanel(ThemeData theme, bool isDark) {
    final provider = context.watch<AiStudioProvider>();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withOpacity(0.3),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.output,
                  size: 18,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  "Output",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const Spacer(),
                if (provider.translatedText.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "${provider.translatedText.length} chars",
                      style: const TextStyle(fontSize: 11, color: Colors.green),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TextField(
              controller: _outputController,
              maxLines: null,
              expands: true,
              readOnly: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
                hintText: "Translation will appear here...",
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewScriptTab extends StatefulWidget {
  const ReviewScriptTab({super.key});

  @override
  State<ReviewScriptTab> createState() => _ReviewScriptTabState();
}

class _ReviewScriptTabState extends State<ReviewScriptTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _scriptController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<AiStudioProvider>();
    final theme = Theme.of(context);

    if (_scriptController.text != provider.scriptText) {
      _scriptController.text = provider.scriptText;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          _buildInfoCard(provider, theme),
          const SizedBox(height: 16),
          Expanded(child: _buildScriptOutput(theme)),
          const SizedBox(height: 8),
          _buildSaveButton(provider, theme),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoCard(AiStudioProvider provider, ThemeData theme) {
    final hasContent =
        provider.translatedText.isNotEmpty || provider.inputText.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: theme.brightness == Brightness.dark
              ? [const Color(0xFF1E3A5F), const Color(0xFF0D253F)]
              : [const Color(0xFFE8F4FD), const Color(0xFFD1E8FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Review Script Generator",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Tạo kịch bản đánh giá/tóm tắt từ nội dung đã dịch",
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  hasContent ? Icons.check_circle : Icons.warning,
                  size: 16,
                  color: hasContent ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasContent
                        ? "Sẵn sàng tạo script từ ${provider.translatedText.isNotEmpty ? provider.translatedText.length : provider.inputText.length} ký tự"
                        : "Chưa có nội dung để tạo script",
                    style: TextStyle(
                      fontSize: 12,
                      color: hasContent ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !hasContent || provider.isGeneratingScript
                  ? null
                  : () =>
                        context.read<AiStudioProvider>().generateReviewScript(),
              icon: provider.isGeneratingScript
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_fix_high),
              label: Text(
                provider.isGeneratingScript
                    ? "Đang tạo..."
                    : "Tạo Review Script",
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptOutput(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer.withOpacity(0.3),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.article,
                  size: 18,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  "Generated Script",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TextField(
              controller: _scriptController,
              maxLines: null,
              expands: true,
              readOnly: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
                hintText: "Script will appear here after generation...",
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(AiStudioProvider provider, ThemeData theme) {
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: provider.scriptText.isEmpty
            ? null
            : () async {
                String? outputFile = await FilePicker.platform.saveFile(
                  fileName: 'review_script.txt',
                );
                if (outputFile != null)
                  await File(outputFile).writeAsString(provider.scriptText);
              },
        icon: const Icon(Icons.save),
        label: const Text("Save Script"),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
    );
  }
}
