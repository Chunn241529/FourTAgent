import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/canvas_provider.dart';
import 'package:intl/intl.dart';
import 'canvas_view.dart';

class CanvasPanel extends StatelessWidget {
  const CanvasPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Consumer<CanvasProvider>(
            builder: (context, provider, child) {
              // Show loading state when LLM is creating canvas
              if (provider.isPendingCanvas) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Đang tạo Canvas...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (provider.currentCanvas != null) {
                return CanvasView(
                  canvas: provider.currentCanvas!,
                  onClose: () => provider.selectCanvas(null),
                );
              }
              return _CanvasPanelContent(provider: provider);
            },
          ),
        ),
      ),
    );
  }
}

class _CanvasPanelContent extends StatefulWidget {
  final CanvasProvider provider;

  const _CanvasPanelContent({required this.provider});

  @override
  State<_CanvasPanelContent> createState() => _CanvasPanelContentState();
}

class _CanvasPanelContentState extends State<_CanvasPanelContent> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => widget.provider.loadCanvases());
  }

  String _formatDate(DateTime date) {
    return DateFormat('HH:mm dd/MM/yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Using .withValues(alpha: ...) to address deprecation of withOpacity
    final dividerColor = theme.dividerColor.withValues(alpha: 0.1);
    final onSurfaceWithAlpha2 = theme.colorScheme.onSurface.withValues(alpha: 0.2);
    final onSurfaceWithAlpha5 = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final primaryContainerWithAlpha3 = theme.colorScheme.primaryContainer.withValues(alpha: 0.3);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          bottomLeft: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: dividerColor),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.brush_rounded, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Canvases',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 20),
                  onPressed: () => _showCreateDialog(context),
                  tooltip: 'Tạo mới',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: () => widget.provider.loadCanvases(),
                  tooltip: 'Làm mới',
                ),
              ],
            ),
          ),

          // Loading
          if (widget.provider.isLoading && widget.provider.canvases.isEmpty)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),

          // Error
          if (widget.provider.error != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                widget.provider.error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),

          // List
          if (!widget.provider.isLoading || widget.provider.canvases.isNotEmpty)
            Expanded(
              child: widget.provider.canvases.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.layers_clear_rounded,
                            size: 48,
                            color: onSurfaceWithAlpha2,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Chưa có Canvas nào',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: onSurfaceWithAlpha5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => _showCreateDialog(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Tạo mới ngay'),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: widget.provider.canvases.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final canvas = widget.provider.canvases[index];
                        final isSelected = widget.provider.currentCanvas?.id == canvas.id;

                        return Material(
                          color: isSelected
                              ? primaryContainerWithAlpha3
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: () => widget.provider.selectCanvas(canvas),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: (canvas.type == 'code'
                                              ? Colors.blue
                                              : Colors.orange)
                                          .withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      canvas.type == 'code'
                                          ? Icons.code_rounded
                                          : Icons.description_rounded,
                                      size: 16,
                                      color: canvas.type == 'code'
                                          ? Colors.blue
                                          : Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          canvas.title,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          _formatDate(canvas.updatedAt),
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            fontSize: 10,
                                            color: onSurfaceWithAlpha5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 16),
                                    onSelected: (value) async {
                                      if (value == 'delete') {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Xác nhận xóa'),
                                            content: Text(
                                                'Bạn có chắc muốn xóa canvas "${canvas.title}"?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context, false),
                                                child: const Text('Hủy'),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context, true),
                                                style: TextButton.styleFrom(
                                                    foregroundColor: Colors.red),
                                                child: const Text('Xóa'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          await widget.provider.deleteCanvas(canvas.id);
                                        }
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline,
                                                color: Colors.red, size: 20),
                                            SizedBox(width: 8),
                                            Text('Xóa',
                                                style: TextStyle(color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final titleController = TextEditingController();
    String type = 'markdown';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Tạo Canvas mới'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Tiêu đề',
                    hintText: 'Nhập tiêu đề...',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: type, // Using initialValue instead of value (deprecated)
                  decoration: const InputDecoration(labelText: 'Loại'),
                  items: const [
                    DropdownMenuItem(
                        value: 'markdown', child: Text('Markdown / Text')),
                    DropdownMenuItem(value: 'code', child: Text('Code')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => type = value);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () {
                  if (titleController.text.trim().isNotEmpty) {
                    widget.provider.createCanvas(
                      title: titleController.text.trim(),
                      content: '',
                      type: type,
                    );
                    Navigator.pop(context);
                  }
                },
                child: const Text('Tạo'),
              ),
            ],
          );
        },
      ),
    );
  }
}
