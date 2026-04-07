import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../services/affiliate_service.dart';

/// Script tool panel - independent script generation without Scrape dependency.
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
  bool _uploadingImages = false;

  Map<String, dynamic>? _generatedScript;

  // Manual product form
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _priceController = TextEditingController();
  List<ImportedFile> _productImages = [];
  List<ImportedFile> _referenceFiles = [];

  bool get _hasProductInfo =>
      _nameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _generatedScript = widget.generatedScript;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  // --- Product Image Import ---
  Future<void> _importProductImages() async {
    try {
      final result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.image,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final newImages = <ImportedFile>[];
        for (final file in result.files) {
          if (file.path != null) {
            newImages.add(ImportedFile(
              name: file.name,
              path: file.path!,
              type: ImportFileType.image,
              content: null,
            ));
          }
        }

        setState(() {
          _productImages = [..._productImages, ...newImages];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import ảnh thất bại: $e')),
        );
      }
    }
  }

  void _removeProductImage(int index) {
    setState(() {
      _productImages = List.from(_productImages)..removeAt(index);
    });
  }

  // --- Reference File Import ---
  Future<void> _importReferenceFiles() async {
    try {
      final result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: ['txt', 'md', 'json'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final newFiles = <ImportedFile>[];
        for (final file in result.files) {
          if (file.path != null) {
            final f = File(file.path!);
            final content = await f.readAsString();
            newFiles.add(ImportedFile(
              name: file.name,
              path: file.path!,
              type: ImportFileType.text,
              content: content,
            ));
          }
        }

        setState(() {
          _referenceFiles = [..._referenceFiles, ...newFiles];
        });

        if (mounted && newFiles.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã import ${newFiles.length} file thành công')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import thất bại: $e')),
        );
      }
    }
  }

  void _removeReferenceFile(int index) {
    setState(() {
      _referenceFiles = List.from(_referenceFiles)..removeAt(index);
    });
  }

  // --- Upload images to backend and get URLs ---
  Future<List<String>> _uploadProductImages() async {
    if (_productImages.isEmpty) return [];

    setState(() => _uploadingImages = true);
    final urls = <String>[];

    try {
      for (final img in _productImages) {
        final file = File(img.path);
        if (await file.exists()) {
          final url = await _uploadFile(file, 'image');
          if (url != null) urls.add(url);
        }
      }
    } finally {
      setState(() => _uploadingImages = false);
    }

    return urls;
  }

  Future<String?> _uploadFile(File file, String type) async {
    try {
      final uri = Uri.parse('${AffiliateService.baseUrl}/affiliate/upload');
      final request = http.MultipartRequest('POST', uri);

      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url'] as String?;
      }
    } catch (e) {
      debugPrint('Upload failed: $e');
    }
    return null;
  }

  // --- Generate Script ---
  Future<void> _generateScript() async {
    if (!_hasProductInfo || _generating) return;

    setState(() => _generating = true);
    try {
      // Upload product images first
      List<String> imageUrls = [];
      if (_productImages.isNotEmpty) {
        imageUrls = await _uploadProductImages();
      }

      // Build custom prompt from reference files
      String? customPrompt;
      if (_referenceFiles.isNotEmpty) {
        final buffer = StringBuffer();
        buffer.writeln('=== TÀI LIỆU THAM KHẢO ===');
        for (final file in _referenceFiles) {
          buffer.writeln('\n[${file.name}]');
          if (file.content != null) {
            buffer.writeln(file.content);
          }
        }
        buffer.writeln('\n=======================');
        customPrompt = buffer.toString();
      }

      final result = await AffiliateService.generateScriptManual(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        price: _priceController.text.trim(),
        style: _selectedStyle,
        duration: _selectedDuration,
        customPrompt: customPrompt,
        imageUrls: imageUrls,
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

  // --- Download Script Section ---
  Future<void> _downloadScript(String section) async {
    if (_generatedScript == null) return;
    
    String? content;
    String filename;
    
    if (section == 'caption') {
      content = _generatedScript!['script']?['caption'];
      filename = 'caption.txt';
    } else if (section == 'ai_video_prompt') {
      content = _generatedScript!['script']?['ai_video_prompt'];
      filename = 'ai_video_prompt.txt';
    } else {
      // full_script
      content = _generatedScript!['script']?['full_script'];
      filename = 'script.txt';
    }
    
    if (content == null || content.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không có nội dung để tải')),
        );
      }
      return;
    }

    try {
      // Get downloads directory
      Directory? downloadsDir;
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        downloadsDir = await getDownloadsDirectory();
      }
      downloadsDir ??= Directory.systemTemp;
      
      final localFile = File('${downloadsDir.path}/$filename');
      await localFile.writeAsString(content);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã lưu: ${localFile.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải: $e')),
        );
      }
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

        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Product Info Section ---
                Text('Thông tin sản phẩm', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),

                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên sản phẩm *',
                    border: OutlineInputBorder(),
                    hintText: 'VD: Son môi Cherry',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),

                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả',
                    border: OutlineInputBorder(),
                    hintText: 'VD: Son dưỡng, màu đỏ cherry',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),

                TextField(
                  controller: _priceController,
                  decoration: const InputDecoration(
                    labelText: 'Giá',
                    border: OutlineInputBorder(),
                    hintText: 'VD: 150,000đ',
                  ),
                ),
                const SizedBox(height: 12),

                // Product Images
                Row(
                  children: [
                    const Icon(Icons.image, size: 16),
                    const SizedBox(width: 4),
                    Text('Ảnh sản phẩm (${_productImages.length})',
                        style: theme.textTheme.titleSmall),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _importProductImages,
                      icon: const Icon(Icons.add_photo_alternate, size: 16),
                      label: const Text('Thêm ảnh'),
                    ),
                  ],
                ),
                if (_productImages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _productImages.length,
                      itemBuilder: (context, index) {
                        final img = _productImages[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(img.path),
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 80,
                                    height: 80,
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    child: const Icon(Icons.broken_image),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () => _removeProductImage(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // --- Style & Duration ---
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

                Text('Thời lượng', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: {'15s': '15 giây', '30s': '30 giây', '60s': '60 giây'}
                      .entries
                      .map((e) {
                    return ChoiceChip(
                      label: Text(e.value),
                      selected: _selectedDuration == e.key,
                      onSelected: (_) => setState(() => _selectedDuration = e.key),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // --- Reference Files ---
                Row(
                  children: [
                    const Icon(Icons.attach_file, size: 16),
                    const SizedBox(width: 4),
                    Text('Tài liệu tham khảo (${_referenceFiles.length})',
                        style: theme.textTheme.titleSmall),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _importReferenceFiles,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Thêm file'),
                    ),
                  ],
                ),
                if (_referenceFiles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _referenceFiles.asMap().entries.map((e) {
                      final idx = e.key;
                      final file = e.value;
                      return Chip(
                        avatar: const Icon(Icons.description, size: 14),
                        label: Text(file.name, style: const TextStyle(fontSize: 12)),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () => _removeReferenceFile(idx),
                      );
                    }).toList(),
                  ),
                ] else ...[
                  Text(
                    'Hỗ trợ: TXT, MD, JSON (không bắt buộc)',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                ],
                const SizedBox(height: 16),

                // --- Generate Button ---
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_hasProductInfo && !_generating && !_uploadingImages)
                        ? _generateScript
                        : null,
                    icon: _generating || _uploadingImages
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _uploadingImages
                          ? 'Đang upload ảnh...'
                          : _generating
                              ? 'Đang sinh...'
                              : 'Generate Script',
                    ),
                  ),
                ),

                // --- Generated Script Result ---
                if (_generatedScript != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
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
                              const Spacer(),
                              // Download buttons
                              IconButton(
                                icon: const Icon(Icons.download, size: 18),
                                tooltip: 'Tải Script',
                                onPressed: () => _downloadScript('full_script'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.download, size: 18),
                                tooltip: 'Tải Caption',
                                onPressed: () => _downloadScript('caption'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.download, size: 18),
                                tooltip: 'Tải AI Video Prompt',
                                onPressed: () => _downloadScript('ai_video_prompt'),
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
                                    .map((h) => Chip(
                                          label: Text(h, style: const TextStyle(fontSize: 11)),
                                        ))
                                    .toList(),
                              ),
                            // Show image URLs if available for render step
                            if (_generatedScript!['image_urls'] != null &&
                                (_generatedScript!['image_urls'] as List).isNotEmpty) ...[
                              const Divider(),
                              Row(
                                children: [
                                  const Icon(Icons.image, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Ảnh cho Render (${(_generatedScript!['image_urls'] as List).length})',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                children: (_generatedScript!['image_urls'] as List)
                                    .map((url) => Chip(
                                          label: Text(
                                            url.toString().split('/').last,
                                            style: const TextStyle(fontSize: 10),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ],
                          ] else
                            Text(_generatedScript!['raw_text'] ?? 'No output'),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
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

// --- Helper classes ---
enum ImportFileType { text, image, video }

extension ImportFileTypeExtension on ImportFileType {
  IconData get icon {
    switch (this) {
      case ImportFileType.text:
        return Icons.description;
      case ImportFileType.image:
        return Icons.image;
      case ImportFileType.video:
        return Icons.video_file;
    }
  }
}

class ImportedFile {
  final String name;
  final String path;
  final ImportFileType type;
  final String? content;

  ImportedFile({
    required this.name,
    required this.path,
    required this.type,
    this.content,
  });
}
