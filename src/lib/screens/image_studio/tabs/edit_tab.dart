import 'dart:io';
import 'dart:ui';
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
  final _focusNode = FocusNode();

  bool _isLoading = false;
  File? _image1;
  File? _image2;
  String? _resultImageUrl;
  String? _resultPrompt;

  bool _enableTryOn = false;
  bool _enableDetail = false;
  bool _enablePixel = false;

  String? _coerceToString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is List && value.isNotEmpty) return value.first.toString();
    return value.toString();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickImage(int slot) async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không thể chọn ảnh: $e')));
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

  Future<void> _handleEdit([String? customPrompt]) async {
    if (_image1 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ảnh gốc (Image 1)')),
      );
      return;
    }
    final promptToUse = customPrompt ?? _promptController.text.trim();
    if (promptToUse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập mô tả yêu cầu chỉnh sửa')),
      );
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
        prompt: promptToUse,
        tryon: _enableTryOn,
        detail: _enableDetail,
        pixel: _enablePixel,
      );
      if (mounted) {
        setState(() {
          _resultPrompt =
              _coerceToString(result['generated_prompt']) ?? promptToUse;
          final filename =
              _coerceToString(result['image_filename']) ??
              _coerceToString(result['image_path']) ??
              '';
          if (filename.isNotEmpty) {
            _resultImageUrl = ImageService.getImageUrl(filename);
            if (_promptController.text.isEmpty) {
              _promptController.text = _resultPrompt!;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
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
                        flex: 5,
                        child: _buildImageSlot(
                          theme: theme,
                          isDark: isDark,
                          slot: 1,
                          label: 'Upload Source Image',
                          sublabel: 'Required • Reference Image',
                          file: _image1,
                          required_: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Image 2 (optional)
                      Expanded(
                        flex: 4,
                        child: _buildImageSlot(
                          theme: theme,
                          isDark: isDark,
                          slot: 2,
                          label: 'Secondary Image',
                          sublabel: 'Optional • Mask or Style',
                          file: _image2,
                          required_: false,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 20),

                // ── Right: Result ──
                Expanded(child: _buildResultArea(theme, isDark)),
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
    final hasFile = file != null;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.02)
            : Colors.black.withOpacity(0.01),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: hasFile
              ? theme.colorScheme.primary.withOpacity(0.4)
              : (isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.05)),
          width: hasFile ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasFile
          ? _buildImagePreview(theme, isDark, file, slot)
          : _buildImagePlaceholder(
              theme,
              isDark,
              slot,
              label,
              sublabel,
              required_,
            ),
    );
  }

  Widget _buildImagePlaceholder(
    ThemeData theme,
    bool isDark,
    int slot,
    String label,
    String sublabel,
    bool required_,
  ) {
    return InkWell(
      onTap: () => _pickImage(slot),
      borderRadius: BorderRadius.circular(24),
      hoverColor: theme.colorScheme.primary.withOpacity(0.05),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: required_
                    ? theme.colorScheme.primary.withOpacity(0.1)
                    : (isDark
                          ? Colors.white.withOpacity(0.04)
                          : Colors.black.withOpacity(0.04)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                size: 32,
                color: required_
                    ? theme.colorScheme.primary.withOpacity(0.8)
                    : theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              sublabel,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(ThemeData theme, bool isDark, File file, int slot) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(file, fit: BoxFit.cover),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 80,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
          ),
        ),
        // Slot label
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text(
              slot == 1 ? 'Source Image' : 'Mask/Style',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        // Actions row
        Positioned(
          top: 10,
          right: 10,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniButton(Icons.sync, 'Đổi ảnh', () => _pickImage(slot)),
              const SizedBox(width: 8),
              _miniButton(Icons.close, 'Huỷ bỏ', () => _removeImage(slot)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Material(
            color: Colors.black.withOpacity(0.4),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(icon, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────── Result Area ───────────────────

  Widget _buildResultArea(ThemeData theme, bool isDark) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _isLoading
          ? _buildLoadingState(theme, isDark)
          : _resultImageUrl != null
          ? _buildResultView(theme, isDark)
          : _buildEmptyState(theme, isDark),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    return Container(
      key: const ValueKey('empty'),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.02)
            : Colors.black.withOpacity(0.01),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.compare_rounded,
                size: 56,
                color: theme.colorScheme.onSurface.withOpacity(0.2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Advanced Image Editing',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Upload an image and describe what you want to change.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.4),
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
            ? Colors.white.withOpacity(0.02)
            : Colors.black.withOpacity(0.01),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.05),
            blurRadius: 40,
            spreadRadius: -10,
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary.withOpacity(0.3),
                  ),
                ),
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Icon(
                  Icons.auto_fix_high,
                  color: theme.colorScheme.primary.withOpacity(0.8),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Processing Edit...',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Analyzing structure and applying edits',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
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
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
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
                  return Center(
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.primary,
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
                ),
              ),
            ),
          ),

          // Glassmorphism Prompt pill (bottom-left)
          if (_resultPrompt != null)
            Positioned(
              left: 16,
              bottom: 16,
              right: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Text(
                      _resultPrompt!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Actions (top-right)
          Positioned(
            top: 16,
            right: 16,
            child: Row(
              children: [
                _buildActionButton(
                  icon: Icons.refresh,
                  tooltip: 'Chỉnh sửa lại',
                  onTap: () => _handleEdit(),
                ),
                const SizedBox(width: 8),
                _buildActionButton(
                  icon: Icons.download_rounded,
                  tooltip: 'Tải ảnh',
                  onTap: _handleDownload,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Material(
            color: Colors.black.withOpacity(0.4),
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
            ),
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
      final defaultName = segments.isNotEmpty
          ? segments.last
          : 'lumina_edit.png';

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu ảnh',
        fileName: defaultName,
        type: FileType.image,
      );
      if (savePath == null) return;

      final response = await HttpClient()
          .getUrl(uri)
          .then((req) => req.close());
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
          SnackBar(
            content: Text('Lỗi tải ảnh: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────── Prompt Bar ───────────────────

  Widget _buildPromptBar(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _promptController,
                  focusNode: _focusNode,
                  maxLines: 4,
                  minLines: 1,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Mô tả yêu cầu chỉnh sửa (VD: Đổi màu áo sang đỏ, thêm nón...)',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  onSubmitted: (_) => _handleEdit(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _handleEdit,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white70,
                          ),
                        )
                      : const Icon(Icons.brush, size: 18),
                  label: const Text(
                    'Edit Image',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!_isLoading) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.black.withOpacity(0.04),
              ),
            ),
            SizedBox(
              height: 40,
              child: _buildOptionsRow(theme, isDark),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────── Lora Options ───────────────────

  Widget _buildOptionsRow(ThemeData theme, bool isDark) {
    const tryOnPrompt = 'Attach the outfit in Image 2 to the person in Image 1';
    const detailPrompt = 'Transform the image to realistic photograph. add realistic details to the corrupted image. restore high frequence details from the corrupted image.';
    const pixelPrompt = 'Create a pixel art spritesheet of the character in the image. The spritesheet is a 4 by 4 grid of four rows of frames - first row is 3 walking frames facing down and 1 frame both arms raised, second row is 3 walking frames facing left and 1 frame jumping left, third row is 3 walking frames facing right and 1 frame jumping right, fourth row is 3 walking frames back view facing up and 1 frame lying on floor.';

    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _buildLoraChip(
            theme: theme,
            isDark: isDark,
            icon: Icons.checkroom,
            label: 'Try-on Clothes',
            value: _enableTryOn,
            onChanged: (val) {
              setState(() {
                _enableTryOn = val;
                if (val) {
                  _enableDetail = false;
                  _enablePixel = false;
                  _promptController.text = tryOnPrompt;
                } else if (_promptController.text == tryOnPrompt) {
                  _promptController.text = '';
                }
              });
            },
          ),
          const SizedBox(width: 8),
          _buildLoraChip(
            theme: theme,
            isDark: isDark,
            icon: Icons.high_quality,
            label: 'Realistic Detail',
            value: _enableDetail,
            onChanged: (val) {
              setState(() {
                _enableDetail = val;
                if (val) {
                  _enableTryOn = false;
                  _enablePixel = false;
                  _promptController.text = detailPrompt;
                } else if (_promptController.text == detailPrompt) {
                  _promptController.text = '';
                }
              });
            },
          ),
          const SizedBox(width: 8),
          _buildLoraChip(
            theme: theme,
            isDark: isDark,
            icon: Icons.grid_3x3,
            label: 'Pixel Spritesheet',
            value: _enablePixel,
            onChanged: (val) {
              setState(() {
                _enablePixel = val;
                if (val) {
                  _enableTryOn = false;
                  _enableDetail = false;
                  _promptController.text = pixelPrompt;
                } else if (_promptController.text == pixelPrompt) {
                  _promptController.text = '';
                }
              });
            },
          ),
        ],
      ),
    ));
  }

  Widget _buildLoraChip({
    required ThemeData theme,
    required bool isDark,
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(!value),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: value
                ? theme.colorScheme.primary.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: value
                  ? theme.colorScheme.primary.withOpacity(0.3)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: value
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.4),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  icon,
                  size: 13,
                  color: value
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: value ? FontWeight.w600 : FontWeight.w500,
                  color: value
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
