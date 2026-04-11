import 'package:flutter/material.dart';
import 'theme/affiliate_theme.dart';
import 'widgets/tool_card.dart';
import 'widgets/affiliate_animations.dart';
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
    if (providers.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: providers.map<Widget>((p) {
        final enabled = p['enabled'] == true && p['has_key'] == true;
        final name = p['name'].toString().toUpperCase();
        
        return Tooltip(
          message: '${p['name']}: ${p['model']}\n${enabled ? "Running" : "Offline / Missing Key"}',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: enabled ? Colors.green.withOpacity(0.08) : Colors.red.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: enabled ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: enabled ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                    boxShadow: enabled ? [
                      BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 3)
                    ] : null,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: enabled ? Colors.green.shade700 : Colors.red.shade300,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBody(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        
        if (isWide) {
          return Row(
            children: [
              _buildSidebar(theme),
              const VerticalDivider(width: 1),
              Expanded(
                child: _activeTool == null 
                  ? _buildToolDashboard(theme, isWide: true) 
                  : _buildExpandedTool(theme),
              ),
            ],
          );
        }
        
        return Column(
          children: [
             Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _activeTool == null 
                    ? _buildToolDashboard(theme, isWide: false) 
                    : _buildExpandedTool(theme),
                ),
             ),
          ],
        );
      },
    );
  }

  Widget _buildSidebar(ThemeData theme) {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 24),
            child: Text('STUDIO TOOLS', style: AffiliateTheme.subtitleStyle(context).copyWith(letterSpacing: 1.5, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          // _buildSidebarItem('scrape', Icons.search, 'Scrape Products', theme),
          _buildSidebarItem('script', Icons.edit_note, 'Viral Scripts', theme),
          // _buildSidebarItem('render', Icons.movie_creation, 'Video Render', theme),
          _buildSidebarItem('smart_reup_douyin', Icons.smart_display, 'Smart Reup', theme),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: AffiliateTheme.glassDecoration(context, borderRadius: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SYSTEM ENGINE', 
                  style: TextStyle(
                    fontWeight: FontWeight.w900, 
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: theme.colorScheme.primary.withOpacity(0.5),
                  )
                ),
                const SizedBox(height: 16),
                _buildProviderChips(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(String id, IconData icon, String label, ThemeData theme) {
    final active = _activeTool == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _activeTool = id),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: active ? AffiliateTheme.primary.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: active ? AffiliateTheme.primary : theme.iconTheme.color?.withOpacity(0.5)),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? AffiliateTheme.primary : theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolDashboard(ThemeData theme, {required bool isWide}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.scaffoldBackgroundColor,
            AffiliateTheme.primary.withOpacity(0.05),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FadeInTranslate(
              child: Text('Welcome to\nAffiliate Studio', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1)),
            ),
            const SizedBox(height: 12),
            FadeInTranslate(
              delay: const Duration(milliseconds: 100),
              child: Text('Automate your workflow with powerful AI tools.', style: AffiliateTheme.subtitleStyle(context).copyWith(fontSize: 16)),
            ),
            const SizedBox(height: 48),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 3 : 1,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
                mainAxisExtent: 200,
              ),
              itemCount: 4,
              itemBuilder: (context, index) {
                switch(index) {
                  // case 0: return ModernToolCard(
                  //   index: index, icon: Icons.search, title: 'Scrape', subtitle: 'Find viral products', 
                  //   isActive: _activeTool == 'scrape', onTap: () => setState(() => _activeTool = 'scrape')
                  // );
                  case 0: return ModernToolCard(
                    index: index, icon: Icons.edit_note, title: 'Script', subtitle: 'AI Viral copywriting', 
                    isActive: _activeTool == 'script', onTap: () => setState(() => _activeTool = 'script'), color: AffiliateTheme.secondary
                  );
                  // case 2: return ModernToolCard(
                  //   index: index, icon: Icons.movie_creation, title: 'Render', subtitle: 'Bulk video generation', 
                  //   isActive: _activeTool == 'render', onTap: () => setState(() => _activeTool = 'render'), color: AffiliateTheme.accent
                  // );
                  case 1: return ModernToolCard(
                    index: index, icon: Icons.smart_display, title: 'Smart Reup', subtitle: 'Douyin transformation', 
                    isActive: _activeTool == 'smart_reup_douyin', onTap: () => setState(() => _activeTool = 'smart_reup_douyin'), color: AffiliateTheme.warning
                  );
                  default: return const SizedBox.shrink();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedTool(ThemeData theme) {
    return Column(
      children: [
        if (MediaQuery.of(context).size.width <= 900)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _activeTool = null),
                ),
                Text('Tool Studio', style: AffiliateTheme.titleStyle(context).copyWith(fontSize: 16)),
              ],
            ),
          ),
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
