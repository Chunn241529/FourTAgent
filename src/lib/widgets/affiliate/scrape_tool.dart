import 'package:flutter/material.dart';
import '../../services/affiliate_service.dart';

/// Scrape tool panel - independent product scraping.
class ScrapeTool extends StatefulWidget {
  final List<dynamic> products;
  final String? selectedProductId;
  final Function(String?) onProductSelected;
  final VoidCallback? onProductsUpdated;
  final VoidCallback? onBack;

  const ScrapeTool({
    super.key,
    required this.products,
    this.selectedProductId,
    required this.onProductSelected,
    this.onProductsUpdated,
    this.onBack,
  });

  @override
  State<ScrapeTool> createState() => _ScrapeToolState();
}

class _ScrapeToolState extends State<ScrapeTool> {
  final _keywordController = TextEditingController();
  final _urlController = TextEditingController();
  String _platform = 'shopee';
  bool _scraping = false;

  @override
  void dispose() {
    _keywordController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _scrapeProducts() async {
    if (_scraping) return;
    setState(() => _scraping = true);
    try {
      final result = await AffiliateService.scrapeProducts(
        platform: _platform,
        keyword: _keywordController.text.isNotEmpty ? _keywordController.text : null,
        url: _urlController.text.isNotEmpty ? _urlController.text : null,
      );
      final newProducts = result['products'] as List? ?? [];
      if (newProducts.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã cào ${newProducts.length} sản phẩm')),
        );
      }
      widget.onProductsUpdated?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scrape error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _scraping = false);
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
            const Icon(Icons.search, size: 20),
            const SizedBox(width: 8),
            Text('Scrape', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),

        // Platform selector
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Shopee'),
              selected: _platform == 'shopee',
              onSelected: (_) => setState(() => _platform = 'shopee'),
            ),
            ChoiceChip(
              label: const Text('TikTok'),
              selected: _platform == 'tiktok',
              onSelected: (_) => setState(() => _platform = 'tiktok'),
            ),
            ChoiceChip(
              label: const Text('Link Video'),
              selected: _platform == 'generic',
              onSelected: (_) => setState(() => _platform = 'generic'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Keyword input
        if (_platform != 'generic')
          TextField(
            controller: _keywordController,
            decoration: InputDecoration(
              labelText: 'Keyword (VD: áo thun nam)',
              border: const OutlineInputBorder(),
              suffixIcon: _scraping
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _scrapeProducts,
                    ),
            ),
            onSubmitted: (_) => _scrapeProducts(),
          ),
        if (_platform != 'generic') const SizedBox(height: 8),

        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            labelText: _platform == 'generic'
                ? 'Dán link video Douyin, Facebook, YouTube...'
                : 'Hoặc dán link sản phẩm trực tiếp',
            border: const OutlineInputBorder(),
            suffixIcon: _platform == 'generic'
                ? (_scraping
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.download),
                        onPressed: _scrapeProducts,
                      ))
                : null,
          ),
        ),
        const SizedBox(height: 16),

        // Product list
        Text('Sản phẩm đã cào (${widget.products.length})', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Expanded(
          child: widget.products.isEmpty
              ? Center(
                  child: Text(
                    'Chưa có sản phẩm nào.\nNhập keyword hoặc link để bắt đầu cào dữ liệu.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                  ),
                )
              : ListView.builder(
                  itemCount: widget.products.length,
                  itemBuilder: (context, index) {
                    final p = widget.products[index];
                    final isSelected = widget.selectedProductId == p['product_id'];
                    return Card(
                      color: isSelected ? theme.colorScheme.primaryContainer : null,
                      child: ListTile(
                        leading: p['image_urls'] != null && (p['image_urls'] as List).isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  p['image_urls'][0],
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(Icons.image),
                                ),
                              )
                            : const Icon(Icons.shopping_bag),
                        title: Text(p['name'] ?? 'Unknown', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${p['platform']} • ${_formatPrice(p['price'])}'),
                            if (p['video_urls'] != null && (p['video_urls'] as List).isNotEmpty)
                              const Row(
                                children: [
                                  Icon(Icons.video_library, size: 12, color: Colors.blue),
                                  SizedBox(width: 4),
                                  Text('Có Video Source', style: TextStyle(fontSize: 11, color: Colors.blue)),
                                ],
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) const Icon(Icons.check_circle),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Xóa hồ sơ',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Xác nhận xóa'),
                                    content: const Text('Thông tin đã cào cùng thư mục liên quan sẽ bị xóa vĩnh viễn.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
                                      TextButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Xóa', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  try {
                                    await AffiliateService.deleteProduct(p['platform'], p['product_id']);
                                    widget.onProductsUpdated?.call();
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Xóa thất bại: $e')),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                        onTap: () => widget.onProductSelected(p['product_id']),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'N/A';
    final p = price is num ? price : double.tryParse(price.toString()) ?? 0;
    return '${p.toStringAsFixed(0)}đ';
  }
}
