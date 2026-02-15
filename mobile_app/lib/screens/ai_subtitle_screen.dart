import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ai_studio_provider.dart';
import '../widgets/common/custom_tab_selector.dart';

class AiSubtitleScreen extends StatelessWidget {
  const AiSubtitleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AiStudioProvider(),
      child: const _AiSubtitleScreenContent(),
    );
  }
}

class _AiSubtitleScreenContent extends StatefulWidget {
  const _AiSubtitleScreenContent();

  @override
  State<_AiSubtitleScreenContent> createState() => _AiSubtitleScreenContentState();
}

class _AiSubtitleScreenContentState extends State<_AiSubtitleScreenContent> with SingleTickerProviderStateMixin {
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const SizedBox(height: 16),
          // Header & Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Image.asset('assets/icon/icon.png'),
                ),
                const SizedBox(width: 12),
                const Text("Studio", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(width: 32),
                Expanded(
                  child: CustomTabSelector(
                    tabs: const ["Subtitle Translator", "Review Script Generator"],
                    selectedIndex: _selectedIndex,
                    onTabSelected: (index) {
                      _tabController.animateTo(index);
                    },
                  ),
                ),
                // Add some empty space to balance title if needed, or just let it be centered
                const SizedBox(width: 100), 
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                SubtitleTranslatorTab(),
                ReviewScriptTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SubtitleTranslatorTab extends StatefulWidget {
  const SubtitleTranslatorTab({super.key});

  @override
  State<SubtitleTranslatorTab> createState() => _SubtitleTranslatorTabState();
}

class _SubtitleTranslatorTabState extends State<SubtitleTranslatorTab> with AutomaticKeepAliveClientMixin {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _outputController = TextEditingController();

  @override
  bool get wantKeepAlive => true; 

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<AiStudioProvider>();

    if (_outputController.text != provider.translatedText && provider.isTranslating) {
         _outputController.text = provider.translatedText;
    } else if (_outputController.text != provider.translatedText && !provider.isTranslating && provider.translatedText.isNotEmpty) {
         _outputController.text = provider.translatedText;
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                   final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['srt', 'txt']);
                   if (result != null && result.files.single.path != null) {
                      final content = await File(result.files.single.path!).readAsString();
                      _inputController.text = content;
                      context.read<AiStudioProvider>().setInputText(content);
                   }
                },
                icon: const Icon(Icons.upload_file),
                label: const Text("Import"),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: provider.isTranslating 
                   ? null 
                   : () {
                      context.read<AiStudioProvider>().setInputText(_inputController.text);
                      context.read<AiStudioProvider>().translate();
                   }, 
                icon: provider.isTranslating 
                   ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                   : const Icon(Icons.translate), 
                label: const Text("Translate"),
              ),
              const Spacer(),
              OutlinedButton.icon(
                 onPressed: () async {
                    if (provider.translatedText.isEmpty) return;
                    String? outputFile = await FilePicker.platform.saveFile(fileName: 'translated.srt');
                    if (outputFile != null) await File(outputFile).writeAsString(provider.translatedText);
                 }, 
                 icon: const Icon(Icons.download), 
                 label: const Text("Download")
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    maxLines: null, expands: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Input or Import Subtitle..."),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    onChanged: (val) => context.read<AiStudioProvider>().setInputText(val),
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.arrow_forward),
                const SizedBox(width: 16),
                Expanded(
                   child: TextField(
                    controller: _outputController,
                    maxLines: null, expands: true,
                    readOnly: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "Translation Result...", filled: true),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ],
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

class _ReviewScriptTabState extends State<ReviewScriptTab> with AutomaticKeepAliveClientMixin {
  final TextEditingController _scriptController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = context.watch<AiStudioProvider>();
    
    if (_scriptController.text != provider.scriptText) {
       _scriptController.text = provider.scriptText;
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
           Card(
             color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2),
             child: Padding(
               padding: const EdgeInsets.all(16.0),
               child: Column(
                 children: [
                   const Text("Generate a review/summary script based on the current translation.", style: TextStyle(fontWeight: FontWeight.bold)),
                   const SizedBox(height: 8),
                   Text(provider.translatedText.isEmpty 
                      ? "Warning: No translation available yet. Will use input text if available."
                      : "Source: Using ${provider.translatedText.length} characters of translated text.",
                      style: TextStyle(color: provider.translatedText.isEmpty && provider.inputText.isEmpty ? Colors.red : Colors.green),
                   ),
                   const SizedBox(height: 16),
                   FilledButton.icon(
                      onPressed: (provider.translatedText.isEmpty && provider.inputText.isEmpty) || provider.isGeneratingScript
                        ? null 
                        : () => context.read<AiStudioProvider>().generateReviewScript(),
                      icon: provider.isGeneratingScript 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_fix_high),
                      label: const Text("Generate Review Script"),
                   ),
                 ],
               ),
             ),
           ),
           const SizedBox(height: 16),
           Expanded(
             child: TextField(
               controller: _scriptController,
               maxLines: null,
               expands: true,
               readOnly: true,
               decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: "Script will appear here...",
                  filled: true,
               ),
             ),
           ),
           const SizedBox(height: 8),
           Align(
             alignment: Alignment.centerRight,
             child: OutlinedButton.icon(
                onPressed: () async {
                    if (provider.scriptText.isEmpty) return;
                    String? outputFile = await FilePicker.platform.saveFile(fileName: 'review_script.txt');
                    if (outputFile != null) await File(outputFile).writeAsString(provider.scriptText);
                },
                icon: const Icon(Icons.save),
                label: const Text("Save Script"),
             ),
           ),
        ],
      ),
    );
  }
}
