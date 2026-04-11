import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../screens/affiliate/theme/affiliate_theme.dart';
import '../../../services/affiliate_service.dart';
import 'dart:io';

/// Section widget for Logo Removal with visual crop editor.
class LogoCropEditorSection extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onToggled;
  final Map<String, double>? cropSettings;
  final ValueChanged<Map<String, double>> onCropChanged;
  final String? url;
  final File? videoFile;

  const LogoCropEditorSection({
    super.key,
    required this.enabled,
    required this.onToggled,
    required this.cropSettings,
    required this.onCropChanged,
    this.url,
    this.videoFile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AffiliateTheme.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.crop, color: AffiliateTheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Logo Removal (Crop)',
                  style: AffiliateTheme.titleStyle(context),
                ),
              ),
              Transform.scale(
                scale: 0.85,
                child: Switch.adaptive(
                  value: enabled,
                  onChanged: onToggled,
                  activeColor: AffiliateTheme.primary,
                ),
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 16),
            if (cropSettings != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(
                      'Đã chọn vùng crop',
                      style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (url != null || videoFile != null) ? () => _openCropEditor(context) : null,
                icon: Icon(cropSettings != null ? Icons.edit : Icons.crop_free, size: 18),
                label: Text(cropSettings != null ? 'Chỉnh sửa vùng crop' : 'Chọn vùng crop'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AffiliateTheme.primary.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (url == null && videoFile == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Vui lòng nhập URL hoặc chọn video trước',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.error.withOpacity(0.7)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _openCropEditor(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      Map<String, dynamic> result;
      if (videoFile != null) {
        result = await AffiliateService.extractFrame(videoFile: videoFile);
      } else {
        result = await AffiliateService.extractFrame(videoUrl: url);
      }

      if (!context.mounted) return;
      Navigator.of(context).pop();

      final frameData = result['image'] as String?;
      final videoWidth = result['video_width'] as int? ?? 1920;
      final videoHeight = result['video_height'] as int? ?? 1080;

      if (frameData == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể trích xuất frame từ video')),
          );
        }
        return;
      }

      final newCrop = await showDialog<Map<String, double>>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _LogoCropDialog(
          frameDataUrl: frameData,
          videoWidth: videoWidth,
          videoHeight: videoHeight,
          initialCrop: cropSettings,
        ),
      );

      if (newCrop != null) {
        onCropChanged(newCrop);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi trích xuất frame: $e')),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
//  Crop Dialog
// ─────────────────────────────────────────────────────────────────────

class _LogoCropDialog extends StatefulWidget {
  final String frameDataUrl;
  final int videoWidth;
  final int videoHeight;
  final Map<String, double>? initialCrop;

  const _LogoCropDialog({
    required this.frameDataUrl,
    required this.videoWidth,
    required this.videoHeight,
    this.initialCrop,
  });

  @override
  State<_LogoCropDialog> createState() => _LogoCropDialogState();
}

class _LogoCropDialogState extends State<_LogoCropDialog>
    with SingleTickerProviderStateMixin {
  /// Crop in normalized (0..1) coords — the KEPT region.
  /// _left/_top = top-left corner, _right/_bottom = bottom-right corner.
  late double _left;
  late double _top;
  late double _right;
  late double _bottom;

  late final AnimationController _fadeController;
  late final MemoryImage _imageProvider;

  // Current image metrics (updated every layout)
  double _imgX = 0, _imgY = 0, _imgW = 1, _imgH = 1;

  // Drag state
  _DragHandle? _activeHandle;
  Offset _dragStartLocal = Offset.zero;
  late double _dsL, _dsT, _dsR, _dsB; // drag-start values

  static const double _handleHitRadius = 24.0;
  static const double _minCropFraction = 0.05;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..forward();

    final raw = widget.frameDataUrl.contains(',')
        ? widget.frameDataUrl.split(',').last
        : widget.frameDataUrl;
    _imageProvider = MemoryImage(base64Decode(raw));

    if (widget.initialCrop != null) {
      final c = widget.initialCrop!;
      _left = (c['left'] ?? 0) / 100.0;
      _top = (c['top'] ?? 0) / 100.0;
      _right = 1.0 - (c['right'] ?? 0) / 100.0;
      _bottom = 1.0 - (c['bottom'] ?? 0) / 100.0;
    } else {
      // Default: crop 15% right, 8% bottom (Douyin watermark typical position)
      _left = 0.0;
      _top = 0.0;
      _right = 0.85;
      _bottom = 0.92;
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Map<String, double> _toPercentSettings() {
    return {
      'top': double.parse((_top * 100).clamp(0.0, 50.0).toStringAsFixed(1)),
      'right': double.parse(((1.0 - _right) * 100).clamp(0.0, 50.0).toStringAsFixed(1)),
      'bottom': double.parse(((1.0 - _bottom) * 100).clamp(0.0, 50.0).toStringAsFixed(1)),
      'left': double.parse((_left * 100).clamp(0.0, 50.0).toStringAsFixed(1)),
    };
  }

  /// Crop rect in display (pixel) coordinates
  Rect get _cropDisplay => Rect.fromLTRB(
        _imgX + _left * _imgW,
        _imgY + _top * _imgH,
        _imgX + _right * _imgW,
        _imgY + _bottom * _imgH,
      );

  // ── Hit test ──────────────────────────────────────────────────────

  _DragHandle? _hitTest(Offset local) {
    final c = _cropDisplay;
    final r = _handleHitRadius;

    // Corners first
    if ((local - c.topLeft).distance <= r) return _DragHandle.topLeft;
    if ((local - c.topRight).distance <= r) return _DragHandle.topRight;
    if ((local - c.bottomLeft).distance <= r) return _DragHandle.bottomLeft;
    if ((local - c.bottomRight).distance <= r) return _DragHandle.bottomRight;

    // Edge midpoints
    if ((local - c.topCenter).distance <= r) return _DragHandle.top;
    if ((local - c.centerRight).distance <= r) return _DragHandle.right;
    if ((local - c.bottomCenter).distance <= r) return _DragHandle.bottom;
    if ((local - c.centerLeft).distance <= r) return _DragHandle.left;

    // Interior → move
    if (c.inflate(4).contains(local)) return _DragHandle.move;

    return null;
  }

  // ── Drag ───────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    final handle = _hitTest(d.localPosition);
    if (handle == null) return;

    _activeHandle = handle;
    _dragStartLocal = d.localPosition;
    _dsL = _left;
    _dsT = _top;
    _dsR = _right;
    _dsB = _bottom;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_activeHandle == null) return;

    final delta = d.localPosition - _dragStartLocal;
    final dx = delta.dx / _imgW;
    final dy = delta.dy / _imgH;

    setState(() {
      switch (_activeHandle!) {
        case _DragHandle.topLeft:
          _left = (_dsL + dx).clamp(0.0, _right - _minCropFraction);
          _top = (_dsT + dy).clamp(0.0, _bottom - _minCropFraction);
        case _DragHandle.topRight:
          _right = (_dsR + dx).clamp(_left + _minCropFraction, 1.0);
          _top = (_dsT + dy).clamp(0.0, _bottom - _minCropFraction);
        case _DragHandle.bottomLeft:
          _left = (_dsL + dx).clamp(0.0, _right - _minCropFraction);
          _bottom = (_dsB + dy).clamp(_top + _minCropFraction, 1.0);
        case _DragHandle.bottomRight:
          _right = (_dsR + dx).clamp(_left + _minCropFraction, 1.0);
          _bottom = (_dsB + dy).clamp(_top + _minCropFraction, 1.0);
        case _DragHandle.top:
          _top = (_dsT + dy).clamp(0.0, _bottom - _minCropFraction);
        case _DragHandle.bottom:
          _bottom = (_dsB + dy).clamp(_top + _minCropFraction, 1.0);
        case _DragHandle.left:
          _left = (_dsL + dx).clamp(0.0, _right - _minCropFraction);
        case _DragHandle.right:
          _right = (_dsR + dx).clamp(_left + _minCropFraction, 1.0);
        case _DragHandle.move:
          final w = _dsR - _dsL;
          final h = _dsB - _dsT;
          final nl = (_dsL + dx).clamp(0.0, 1.0 - w);
          final nt = (_dsT + dy).clamp(0.0, 1.0 - h);
          _left = nl;
          _top = nt;
          _right = nl + w;
          _bottom = nt + h;
      }
    });
  }

  void _onPanEnd(DragEndDetails _) => _activeHandle = null;

  void _resetCrop() {
    setState(() {
      _left = 0.0;
      _top = 0.0;
      _right = 1.0;
      _bottom = 1.0;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screen = MediaQuery.of(context).size;
    final dw = min(screen.width * 0.85, 800.0);
    final dh = min(screen.height * 0.82, 720.0);

    return FadeTransition(
      opacity: _fadeController,
      child: Dialog(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: dw,
          height: dh,
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.crop, color: AffiliateTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Chọn vùng giữ lại (vùng sáng)',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      onPressed: _resetCrop,
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: 'Reset',
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.dividerColor.withOpacity(0.15)),

              // Crop canvas
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: Colors.black,
                      child: LayoutBuilder(builder: (ctx, box) {
                        // Compute image position & size
                        final aspect = widget.videoWidth / widget.videoHeight;
                        final cAspect = box.maxWidth / box.maxHeight;

                        if (aspect > cAspect) {
                          _imgW = box.maxWidth;
                          _imgH = box.maxWidth / aspect;
                        } else {
                          _imgH = box.maxHeight;
                          _imgW = box.maxHeight * aspect;
                        }
                        _imgX = (box.maxWidth - _imgW) / 2;
                        _imgY = (box.maxHeight - _imgH) / 2;

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: _onPanStart,
                          onPanUpdate: _onPanUpdate,
                          onPanEnd: _onPanEnd,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Image
                              Positioned(
                                left: _imgX,
                                top: _imgY,
                                width: _imgW,
                                height: _imgH,
                                child: Image(
                                  image: _imageProvider,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                ),
                              ),
                              // Overlay + handles
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _CropOverlayPainter(
                                    cropRect: _cropDisplay,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),

              // Help
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Kéo góc / cạnh để điều chỉnh  •  Kéo giữa để di chuyển',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.35)),
                  textAlign: TextAlign.center,
                ),
              ),

              // Buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Hủy'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, _toPercentSettings()),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Xác nhận'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AffiliateTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DragHandle {
  topLeft, topRight, bottomLeft, bottomRight,
  top, bottom, left, right,
  move,
}

// ─────────────────────────────────────────────────────────────────────
//  Custom Painter
// ─────────────────────────────────────────────────────────────────────

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;

  _CropOverlayPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    // ── Dark overlay (outside the crop / kept region) ──
    final full = Path()..addRect(Offset.zero & size);
    final kept = Path()..addRect(cropRect);
    final dark = Path.combine(PathOperation.difference, full, kept);
    canvas.drawPath(dark, Paint()..color = Colors.black.withOpacity(0.65));

    // ── White border around kept area ──
    canvas.drawRect(
      cropRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // ── Rule-of-thirds grid ──
    final gridP = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 0.5;
    final tw = cropRect.width / 3;
    final th = cropRect.height / 3;
    for (int i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(cropRect.left + tw * i, cropRect.top),
        Offset(cropRect.left + tw * i, cropRect.bottom),
        gridP,
      );
      canvas.drawLine(
        Offset(cropRect.left, cropRect.top + th * i),
        Offset(cropRect.right, cropRect.top + th * i),
        gridP,
      );
    }

    // ── Corner L-brackets (thick white lines) ──
    final cp = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.square;
    const arm = 24.0;

    void drawCorner(Offset o, double dx, double dy) {
      canvas.drawLine(o, Offset(o.dx + arm * dx, o.dy), cp);
      canvas.drawLine(o, Offset(o.dx, o.dy + arm * dy), cp);
    }

    drawCorner(cropRect.topLeft, 1, 1);
    drawCorner(cropRect.topRight, -1, 1);
    drawCorner(cropRect.bottomLeft, 1, -1);
    drawCorner(cropRect.bottomRight, -1, -1);

    // ── Edge midpoint bars ──
    final ep = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    const bar = 16.0;

    // Top & Bottom
    canvas.drawLine(
      Offset(cropRect.center.dx - bar, cropRect.top),
      Offset(cropRect.center.dx + bar, cropRect.top),
      ep,
    );
    canvas.drawLine(
      Offset(cropRect.center.dx - bar, cropRect.bottom),
      Offset(cropRect.center.dx + bar, cropRect.bottom),
      ep,
    );
    // Left & Right
    canvas.drawLine(
      Offset(cropRect.left, cropRect.center.dy - bar),
      Offset(cropRect.left, cropRect.center.dy + bar),
      ep,
    );
    canvas.drawLine(
      Offset(cropRect.right, cropRect.center.dy - bar),
      Offset(cropRect.right, cropRect.center.dy + bar),
      ep,
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter old) => old.cropRect != cropRect;
}
