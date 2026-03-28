import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/image_service.dart';

class EditTab extends StatefulWidget {
  const EditTab({super.key});

  @override
  State<EditTab> createState() => _EditTabState();
}

class _EditTabState extends State<EditTab> {
  final TextEditingController _promptController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = false;
  File? _image1;
  File? _image2;
  String? _resultImageUrl;
  String? _resultPrompt;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(int slot) async {
    try {
      final XFile? image =
          await _picker.pickImage(source: ImageSource.gallery);
      if (image != null && mounted) {
        setState(() {
          if (slot == 1) {
            _image1 = File(image.path);
          } else {
            _image2 = File(image.path);
          }
          _resultImageUrl = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Không thể chọn ảnh: $e')));
      }
    }
  }

  void _removeImage(int slot) {
    setState(() {
      if (slot == 1) {
        _image1 = null;
      } else {
        _image2 = null;
      }
    });
  }

  Future<void> _handleEdit() async {
    if (_image1 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chọn ít nhất 1 ảnh (Image 1)')));
      return;
    }
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nhập mô tả yêu cầu chỉnh sửa')));
      return;
    }

    setState(() {
      _isLoading = true;
      _resultImageUrl = null;
      _resultPrompt = null;
    });

    try {
      final result = await ImageService.editImage(
        image1: _image1!,
        image2: _image2,
        prompt: prompt,
      );
      if (mounted) {
        setState(() {
          _resultPrompt = result['generated_prompt'] as String?;
          final filename =
              result['image_filename'] ?? result['image_path'] ?? '';
          if (filename.toString().isNotEmpty) {
            _resultImageUrl = ImageService.getImageUrl(filename);
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

  // ─────────────────────── BUILD ───────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
      child: Column(
        children: [
          // ── Main content area ──
          Expanded(
            child: Row(
              children: [
                // ── Left: Image inputs ──
                SizedBox(
                  width: 320,
                  child: Column(
                    children: [
                      // Image 1 (required)
                      Expanded(
                        child: _buildImageSlot(
                          theme: theme,
                          isDark: isDark,
                          slot: 1,
                          label: 'Image 1',
                          sublabel: 'Bắt buộc',
                          file: _image1,
                          required_: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Image 2 (optional)
                      Expanded(
                        child: _buildImageSlot(
                          theme: theme,
                          isDark: isDark,
                          slot: 2,
                          label: 'Image 2',
                          sublabel: 'Tuỳ chọn',
                          file: _image2,
                          required_: false,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 20),

                // ── Right: Result ──
                Expanded(
                  child: _buildResultArea(theme, isDark),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Prompt bar ──
          _buildPromptBar(theme, isDark),
        ],
      ),
    );
  }

  // ─────────────────── Image Slot ───────────────────

  Widget _buildImageSlot({
    required ThemeData theme,
    required bool isDark,
    required int slot,
    required String label,
    required String sublabel,
    required File? file,
    required bool required_,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.03)
            : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: file != null
              ? theme.colorScheme.primary.withOpacity(0.3)
              : (isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.black.withOpacity(0.06)),
          width: file != null ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: file != null
          ? _buildImagePreview(theme, isDark, file, slot)
          : _buildImagePlaceholder(theme, isDark, slot, label, sublabel, required_),
    );
  }

  Widget _buildImagePlaceholder(ThemeData theme, bool isDark, int slot,
      String label, String sublabel, bool required_) {
    return InkWell(
      onTap: () => _pickImage(slot),
      borderRadius: BorderRadius.circular(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: required_
                    ? theme.colorScheme.primary.withOpacity(0.08)
                    : (isDark
                        ? Colors.white.withOpacity(0.04)
                        : Colors.black.withOpacity(0.04)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                size: 28,
                color: required_
                    ? theme.colorScheme.primary.withOpacity(0.6)
                    : theme.colorScheme.onSurface.withOpacity(0.3),
              ),
            ),
            const SizedBox(height: 12),
            Text(label,
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(sublabel,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.4))),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(
      ThemeData theme, bool isDark, File file, int slot) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(file, fit: BoxFit.cover),
        // Gradient scrim at top
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 48,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
          ),
        ),
        // Actions row
        Positioned(
          top: 6,
          right: 6,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniButton(Icons.refresh, 'Đổi ảnh', () => _pickImage(slot)),
              const SizedBox(width: 4),
              _miniButton(Icons.close, 'Xoá', () => _removeImage(slot)),
            ],
          ),
        ),
        // Slot label
        Positioned(
          top: 8,
          left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              slot == 1 ? 'Image 1' : 'Image 2',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _miniButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child:
              Padding(padding: const EdgeInsets.all(5), child: Icon(icon, size: 14, color: Colors.white70)),
        ),
      ),
    );
  }

  // ─────────────────── Result Area ───────────────────

  Widget _buildResultArea(ThemeData theme, bool isDark) {
    return Container(
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
      child: _isLoading
          ? _buildLoading(theme)
          : _resultImageUrl != null
              ? _buildResult(theme)
              : _buildResultEmpty(theme, isDark),
    );
  }

  Widget _buildResultEmpty(ThemeData theme, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.image_outlined,
                size: 48,
                color: theme.colorScheme.onSurface.withOpacity(0.25)),
          ),
          const SizedBox(height: 16),
          Text('Kết quả chỉnh sửa',
              style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.4))),
          const SizedBox(height: 6),
          Text(
            'Chọn ảnh → Nhập yêu cầu → Bấm Edit',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.25)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 24),
          Text('Đang chỉnh sửa...', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Quá trình này có thể mất đến 1 phút',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.5))),
        ],
      ),
    );
  }

  Widget _buildResult(ThemeData theme) {
    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.network(
              _resultImageUrl!,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
              errorBuilder: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image, size: 48)),
            ),
          ),
        ),
        // Prompt overlay
        if (_resultPrompt != null)
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
              child: Text(_resultPrompt!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11)),
            ),
          ),
        // Download button (top-right)
        Positioned(
          top: 10,
          right: 10,
          child: _buildDownloadButton(theme),
        ),
      ],
    );
  }

  Widget _buildDownloadButton(ThemeData theme) {
    return Tooltip(
      message: 'Tải ảnh về',
      child: Material(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: _handleDownload,
          borderRadius: BorderRadius.circular(10),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.download_rounded, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Future<void> _handleDownload() async {
    if (_resultImageUrl == null) return;
    try {
      final uri = Uri.parse(_resultImageUrl!);
      final segments = uri.pathSegments;
      final defaultName = segments.isNotEmpty ? segments.last : 'lumina_edit.png';

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu ảnh',
        fileName: defaultName,
        type: FileType.image,
      );
      if (savePath == null) return;

      final response = await HttpClient().getUrl(uri).then((req) => req.close());
      final bytes = await consolidateHttpClientResponseBytes(response);
      final file = File(savePath);
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã lưu ảnh tại: ${file.path}'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải ảnh: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─────────────────── Prompt Bar ───────────────────

  Widget _buildPromptBar(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2F2F2F) : Colors.white,
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
              maxLines: 2,
              minLines: 1,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText:
                    'Mô tả yêu cầu chỉnh sửa (VD: Đổi màu áo sang đỏ, thêm nón...)',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.35)),
              ),
              onSubmitted: (_) => _handleEdit(),
            ),
          ),

          const SizedBox(width: 8),

          // Edit button
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _handleEdit,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white70))
                  : const Icon(Icons.brush, size: 18),
              label: const Text('Edit'),
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
