import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/ai_studio_provider.dart';
import '../widgets/common/animated_blob.dart';

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
      backgroundColor: isDark ? const Color(0xFF0A0A0B) : const Color(0xFFF9FAFB),
      body: Stack(
        children: [
          // ── Background Mesh ──
          _buildMeshBackground(theme, isDark),

          // ── Content ──
          SafeArea(
            child: Column(
              children: [
                _buildFloatingHeader(theme, isDark),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [TranslatorTab(), ReviewScriptTab()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeshBackground(ThemeData theme, bool isDark) {
    return Positioned.fill(
      child: ExcludeSemantics(
        child: Stack(
          children: [
            Positioned(
              top: -50,
              left: -100,
              child: AnimatedBlob(
                color: theme.colorScheme.primary.withOpacity(isDark ? 0.15 : 0.08),
                size: 450,
              ),
            ),
            Positioned(
              bottom: -100,
              right: -50,
              child: AnimatedBlob(
                color: Colors.blueAccent.withOpacity(isDark ? 0.12 : 0.06),
                size: 400,
              ),
            ),
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingHeader(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.colorScheme.primary, Colors.blueAccent],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.translate_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Translate Studio",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  "Workspace chuyên nghiệp",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildCompactTabs(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildCompactTabs(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCompactTab(0, Icons.subtitles_rounded, "Translator", theme, isDark),
          _buildCompactTab(1, Icons.description_rounded, "Script", theme, isDark),
        ],
      ),
    );
  }

  Widget _buildCompactTab(int index, IconData icon, String label, ThemeData theme, bool isDark) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _tabController.animateTo(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuart,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? (isDark ? Colors.white10 : Colors.white) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected && !isDark ? [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
          ] : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.4),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ],
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

    if (_outputController.text != provider.translatedText && provider.isTranslating) {
      _outputController.text = provider.translatedText;
    } else if (_outputController.text != provider.translatedText && !provider.isTranslating && provider.translatedText.isNotEmpty) {
      _outputController.text = provider.translatedText;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          _buildWorkspaceToolbar(provider, theme, isDark),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildPanel(
                  title: "Input",
                  icon: Icons.input_rounded,
                  controller: _inputController,
                  hint: "Dán hoặc kéo srt/txt vào đây...",
                  theme: theme,
                  isDark: isDark,
                  onChanged: (val) => context.read<AiStudioProvider>().setInputText(val),
                )),
                const SizedBox(width: 16),
                Expanded(child: _buildPanel(
                  title: "Output",
                  icon: Icons.auto_awesome_rounded,
                  controller: _outputController,
                  hint: "Bản dịch sẽ xuất hiện tại đây...",
                  theme: theme,
                  isDark: isDark,
                  readOnly: true,
                  showCharCount: true,
                  charCount: provider.translatedText.length,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceToolbar(AiStudioProvider provider, ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          _buildToolbarButton(
            onTap: () async {
              final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['srt', 'txt']);
              if (result != null && result.files.single.path != null) {
                final content = await File(result.files.single.path!).readAsString();
                _inputController.text = content;
                if (mounted) context.read<AiStudioProvider>().setInputText(content);
              }
            },
            icon: Icons.file_upload_outlined,
            label: "Import",
            theme: theme,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_rounded, size: 18, color: theme.colorScheme.primary.withOpacity(0.7)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      onChanged: (val) => provider.setContextPrompt(val),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "Nhập bối cảnh (Ví dụ: phim cổ trang, hài hước...)",
                        hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3)),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildToolbarButton(
            onTap: provider.isTranslating ? null : () {
              context.read<AiStudioProvider>().setInputText(_inputController.text);
              context.read<AiStudioProvider>().translate(withContext: provider.contextPrompt.isNotEmpty);
            },
            icon: Icons.translate_rounded,
            label: provider.isTranslating ? "Dịch..." : "Dịch ngay",
            isPrimary: true,
            isLoading: provider.isTranslating,
            theme: theme,
          ),
          const SizedBox(width: 12),
          _buildToolbarButton(
            onTap: provider.translatedText.isEmpty ? null : () async {
              String? outputFile = await FilePicker.platform.saveFile(fileName: 'translated.srt');
              if (outputFile != null) await File(outputFile).writeAsString(provider.translatedText);
            },
            icon: Icons.download_rounded,
            label: "Lưu",
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required VoidCallback? onTap,
    required IconData icon,
    required String label,
    required ThemeData theme,
    bool isPrimary = false,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isPrimary ? null : Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            if (isLoading)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else
              Icon(icon, size: 18, color: isPrimary ? Colors.white : theme.colorScheme.onSurface),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isPrimary ? Colors.white : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel({
    required String title,
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    required ThemeData theme,
    required bool isDark,
    bool readOnly = false,
    bool showCharCount = false,
    int charCount = 0,
    Function(String)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.02) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (showCharCount)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text("$charCount chars", style: TextStyle(fontSize: 10, color: theme.colorScheme.primary)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey.withOpacity(0.03),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: controller,
                maxLines: null,
                expands: true,
                readOnly: readOnly,
                onChanged: onChanged,
                style: GoogleFonts.beVietnamPro(fontSize: 14, height: 1.6),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(24),
                ),
              ),
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
    final isDark = theme.brightness == Brightness.dark;

    if (_scriptController.text != provider.scriptText) {
      _scriptController.text = provider.scriptText;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          _buildScriptHeader(provider, theme, isDark),
          const SizedBox(height: 20),
          Expanded(child: _buildScriptWorkspace(provider, theme, isDark)),
        ],
      ),
    );
  }

  Widget _buildScriptHeader(AiStudioProvider provider, ThemeData theme, bool isDark) {
    final hasContent = provider.translatedText.isNotEmpty || provider.inputText.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.auto_awesome_rounded, color: theme.colorScheme.primary, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Review Script Generator",
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  hasContent 
                    ? "Sẵn sàng tạo kịch bản từ ${provider.translatedText.isNotEmpty ? provider.translatedText.length : provider.inputText.length} ký tự nội dung."
                    : "Vui lòng nhập nội dung ở tab Translator trước.",
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.4)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _buildScriptToolbarAction(
            onTap: !hasContent || provider.isGeneratingScript
              ? null
              : () => context.read<AiStudioProvider>().generateReviewScript(),
            isLoading: provider.isGeneratingScript,
            label: "Tạo Script",
            icon: Icons.auto_awesome_rounded,
            isPrimary: true,
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildScriptWorkspace(AiStudioProvider provider, ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.02) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.article_rounded, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text("Kịch bản Review", style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (provider.scriptText.isNotEmpty)
                  _buildScriptToolbarAction(
                    onTap: () async {
                      String? outputFile = await FilePicker.platform.saveFile(fileName: 'script.txt');
                      if (outputFile != null) await File(outputFile).writeAsString(provider.scriptText);
                    },
                    label: "Lưu file",
                    icon: Icons.download_rounded,
                    theme: theme,
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey.withOpacity(0.03),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _scriptController,
                maxLines: null,
                expands: true,
                readOnly: true,
                style: GoogleFonts.beVietnamPro(fontSize: 14, height: 1.6),
                decoration: InputDecoration(
                  hintText: "Script sẽ xuất hiện tại đây sau khi bạn nhấn 'Tạo Script'...",
                  hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptToolbarAction({
    required VoidCallback? onTap,
    required String label,
    required IconData icon,
    required ThemeData theme,
    bool isPrimary = false,
    bool isLoading = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: isLoading 
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? theme.colorScheme.primary : theme.colorScheme.surface,
        foregroundColor: isPrimary ? Colors.white : theme.colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: isPrimary ? 4 : 0,
      ),
    );
  }
}
