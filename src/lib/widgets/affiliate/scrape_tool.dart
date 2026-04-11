import 'package:flutter/material.dart';
import '../../screens/affiliate/theme/affiliate_theme.dart';
import '../../screens/affiliate/widgets/affiliate_animations.dart';
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
          FadeInTranslate(
            delay: const Duration(milliseconds: 100),
            child: TextField(
              controller: _keywordController,
              decoration: AffiliateTheme.inputDecoration('Keyword (VD: áo thun nam)', icon: Icons.search).copyWith(
                suffixIcon: _scraping
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.send_rounded, color: AffiliateTheme.primary),
                        onPressed: _scrapeProducts,
                      ),
              ),
              onSubmitted: (_) => _scrapeProducts(),
            ),
          ),
        if (_platform != 'generic') const SizedBox(height: 12),

        FadeInTranslate(
          delay: const Duration(milliseconds: 200),
          child: TextField(
            controller: _urlController,
            decoration: AffiliateTheme.inputDecoration(
              _platform == 'generic'
                  ? 'Dán link video Douyin, Facebook, YouTube...'
                  : 'Hoặc dán link sản phẩm trực tiếp',
              icon: Icons.link,
            ).copyWith(
              suffixIcon: _platform == 'generic'
                  ? (_scraping
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.download_rounded, color: AffiliateTheme.primary),
                          onPressed: _scrapeProducts,
                        ))
                  : null,
            ),
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
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    final p = widget.products[index];
                    final isSelected = widget.selectedProductId == p['product_id'];
                    return FadeInTranslate(
                      delay: Duration(milliseconds: 50 * index),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: AffiliateTheme.cardDecoration(context).copyWith(
                          color: isSelected ? AffiliateTheme.primary.withOpacity(0.05) : null,
                          border: Border.all(
                            color: isSelected ? AffiliateTheme.primary.withOpacity(0.3) : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: p['image_urls'] != null && (p['image_urls'] as List).isNotEmpty
                              ? Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      p['image_urls'][0],
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(Icons.image, size: 32),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: AffiliateTheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.shopping_bag, color: AffiliateTheme.primary),
                                ),
                          title: Text(
                            p['name'] ?? 'Unknown Product',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AffiliateTheme.titleStyle(context).copyWith(fontSize: 14),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AffiliateTheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _formatPrice(p['price']),
                                    style: const TextStyle(color: AffiliateTheme.primary, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  p['platform']?.toString().toUpperCase() ?? 'WEB',
                                  style: AffiliateTheme.subtitleStyle(context).copyWith(fontSize: 10, letterSpacing: 0.5),
                                ),
                                if (p['video_urls'] != null && (p['video_urls'] as List).isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.play_circle_fill, size: 14, color: Colors.blue),
                                ],
                              ],
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            onPressed: () => _deleteProduct(p),
                          ),
                          onTap: () => widget.onProductSelected(p['product_id']),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _deleteProduct(Map<String, dynamic> p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this product and all associated files?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await AffiliateService.deleteProduct(p['platform'], p['product_id']);
        widget.onProductsUpdated?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Product deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'N/A';
    final p = price is num ? price : double.tryParse(price.toString()) ?? 0;
    return '${p.toStringAsFixed(0)}đ';
  }
}
