import 'package:flutter/material.dart';
import '../../services/affiliate_service.dart';
import '../../widgets/affiliate/scrape_tool.dart';
import '../../widgets/affiliate/script_tool.dart';
import '../../widgets/affiliate/render_tool.dart';
import '../../widgets/affiliate/reup_tool.dart';
import '../../widgets/affiliate/smart_reup_screen.dart';

/// Main Affiliate Automation screen with independent tool-based workflow.
class AffiliateScreen extends StatefulWidget {
  const AffiliateScreen({super.key});

  @override
  State<AffiliateScreen> createState() => _AffiliateScreenState();
}

class _AffiliateScreenState extends State<AffiliateScreen> {
  // Status
  bool _loading = true;
  Map<String, dynamic> _status = {};
  String? _error;

  // Tool state - shared across tools
  String? _activeTool;
  List<dynamic> _products = [];
  Map<String, String> _transforms = {};
  String? _selectedProductId;
  Map<String, dynamic>? _generatedScript;
  Map<String, dynamic>? _jobStatus;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    try {
      final status = await AffiliateService.getStatus();
      final transforms = await AffiliateService.getTransforms();
      final products = await AffiliateService.listProducts();
      if (mounted) {
        setState(() {
          _status = status;
          _transforms = transforms;
          _products = products;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadProducts() async {
    try {
      final products = await AffiliateService.listProducts();
      if (mounted) {
        setState(() => _products = products);
      }
    } catch (_) {}
  }

  void _onProductSelected(String? productId) {
    setState(() {
      _selectedProductId = productId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Affiliate Auto'),
          ],
        ),
        actions: [
          // LLM Status indicator
          if (_status['llm_providers'] != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _buildProviderChips(),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStatus,
            tooltip: 'Refresh Status',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadStatus, child: const Text('Retry')),
                    ],
                  ),
                )
              : _buildBody(theme),
    );
  }

  Widget _buildProviderChips() {
    final providers = _status['llm_providers'] as List? ?? [];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: providers.map<Widget>((p) {
        final enabled = p['enabled'] == true && p['has_key'] == true;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Tooltip(
            message: '${p['name']}: ${p['model']}\n${enabled ? "Active" : "Disabled"}',
            child: CircleAvatar(
              radius: 6,
              backgroundColor: enabled ? Colors.green : Colors.grey,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_activeTool == null) {
      return _buildToolDashboard(theme);
    }
    return _buildExpandedTool(theme);
  }

  Widget _buildToolDashboard(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chọn công cụ', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 1.2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                _buildToolCard(
                  'scrape',
                  Icons.search,
                  'Scrape',
                  'Cào sản phẩm',
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.onPrimaryContainer,
                ),
                _buildToolCard(
                  'script',
                  Icons.edit_note,
                  'Script',
                  'Tạo kịch bản',
                  theme.colorScheme.secondaryContainer,
                  theme.colorScheme.onSecondaryContainer,
                ),
                _buildToolCard(
                  'render',
                  Icons.movie_creation,
                  'Render',
                  'Render video',
                  theme.colorScheme.tertiaryContainer,
                  theme.colorScheme.onTertiaryContainer,
                ),
                _buildToolCard(
                  'reup',
                  Icons.transform,
                  'Smart Reup',
                  'Transform video',
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
                  theme.colorScheme.onPrimaryContainer,
                ),
                _buildToolCard(
                  'smart_reup_douyin',
                  Icons.smart_display,
                  'Smart Reup Douyin',
                  'Reup video tu Douyin',
                  theme.colorScheme.secondaryContainer,
                  theme.colorScheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolCard(
    String toolId,
    IconData icon,
    String title,
    String subtitle,
    Color backgroundColor,
    Color foregroundColor,
  ) {
    return Card(
      color: backgroundColor,
      elevation: 2,
      child: InkWell(
        onTap: () => setState(() => _activeTool = toolId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: foregroundColor),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: foregroundColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: foregroundColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedTool(ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: _getToolWidget()!,
        ),
      ],
    );
  }

  Widget? _getToolWidget() {
    switch (_activeTool) {
      case 'scrape':
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ScrapeTool(
            products: _products,
            selectedProductId: _selectedProductId,
            onProductSelected: _onProductSelected,
            onProductsUpdated: _loadProducts,
            onBack: () => setState(() => _activeTool = null),
          ),
        );
      case 'script':
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ScriptTool(
            products: _products,
            selectedProductId: _selectedProductId,
            generatedScript: _generatedScript,
            onScriptGenerated: (script) => setState(() => _generatedScript = script),
            onBack: () => setState(() => _activeTool = null),
          ),
        );
      case 'render':
        return Padding(
          padding: const EdgeInsets.all(16),
          child: RenderTool(
            products: _products,
            selectedProductId: _selectedProductId,
            generatedScript: _generatedScript,
            jobStatus: _jobStatus,
            onBack: () => setState(() => _activeTool = null),
          ),
        );
      case 'reup':
        return Padding(
          padding: const EdgeInsets.all(16),
          child: ReupTool(
            transforms: _transforms,
            products: _products,
            selectedProductId: _selectedProductId,
            jobStatus: _jobStatus,
            onBack: () => setState(() => _activeTool = null),
          ),
        );
      case 'smart_reup_douyin':
        return Padding(
          padding: const EdgeInsets.all(16),
          child: SmartReupScreen(
            onBack: () => setState(() => _activeTool = null),
          ),
        );
      default:
        return null;
    }
  }
}
