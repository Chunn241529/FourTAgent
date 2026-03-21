import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../services/affiliate_service.dart';

/// Main Affiliate Automation screen with tabs for each workflow step.
class AffiliateScreen extends StatefulWidget {
  const AffiliateScreen({super.key});

  @override
  State<AffiliateScreen> createState() => _AffiliateScreenState();
}

class _AffiliateScreenState extends State<AffiliateScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Status
  bool _loading = true;
  Map<String, dynamic> _status = {};
  String? _error;

  // Scrape tab
  final _keywordController = TextEditingController();
  final _urlController = TextEditingController();
  String _platform = 'shopee';
  List<dynamic> _products = [];
  bool _scraping = false;

  // Generate tab
  String _selectedStyle = 'genz';
  String _selectedDuration = '30s';
  Map<String, dynamic>? _generatedScript;
  bool _generating = false;
  String? _selectedProductId;

  // Render tab
  bool _useTts = false;
  String? _activeJobId;
  Map<String, dynamic>? _jobStatus;
  Timer? _pollTimer;

  // Smart Reup tab
  Map<String, bool> _selectedTransforms = {};
  Map<String, String> _transforms = {};
  bool _reupProcessing = false;
  Map<String, dynamic>? _reupResult;
  String? _selectedVideoName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _keywordController.dispose();
    _urlController.dispose();
    _pollTimer?.cancel();
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
          _selectedTransforms = {
            for (var key in transforms.keys) key: ['metadata', 'mirror', 'crop', 'speed', 'pitch'].contains(key),
          };
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
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.search), text: 'Scrape'),
            Tab(icon: Icon(Icons.edit_note), text: 'Script'),
            Tab(icon: Icon(Icons.movie_creation), text: 'Render'),
            Tab(icon: Icon(Icons.transform), text: 'Smart Reup'),
          ],
        ),
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
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildScrapeTab(theme),
                    _buildScriptTab(theme),
                    _buildRenderTab(theme),
                    _buildReupTab(theme),
                  ],
                ),
    );
  }

  // --- Provider status chips ---
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

  // --- Tab 1: Scrape ---
  Widget _buildScrapeTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Platform selector
          Row(
            children: [
              ChoiceChip(
                label: const Text('Shopee'),
                selected: _platform == 'shopee',
                onSelected: (_) => setState(() => _platform = 'shopee'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('TikTok'),
                selected: _platform == 'tiktok',
                onSelected: (_) => setState(() => _platform = 'tiktok'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Keyword input
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
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Hoặc dán link sản phẩm trực tiếp',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // Product list
          Text('Sản phẩm đã cào (${_products.length})', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Expanded(
            child: _products.isEmpty
                ? Center(
                    child: Text(
                      'Chưa có sản phẩm nào.\nNhập keyword hoặc link để bắt đầu cào dữ liệu.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                    ),
                  )
                : ListView.builder(
                    itemCount: _products.length,
                    itemBuilder: (context, index) {
                      final p = _products[index];
                      final isSelected = _selectedProductId == p['product_id'];
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
                                    errorBuilder: (_, __, ___) => const Icon(Icons.image),
                                  ),
                                )
                              : const Icon(Icons.shopping_bag),
                          title: Text(p['name'] ?? 'Unknown', maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${p['platform']} • ${_formatPrice(p['price'])}'),
                          trailing: isSelected ? const Icon(Icons.check_circle) : null,
                          onTap: () {
                            setState(() => _selectedProductId = p['product_id']);
                            _tabController.animateTo(1); // Go to Script tab
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
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
      setState(() {
        _products.addAll(newProducts);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scrape error: $e')));
      }
    } finally {
      if (mounted) setState(() => _scraping = false);
    }
  }

  // --- Tab 2: Script Generation ---
  Widget _buildScriptTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedProductId == null)
            Expanded(
              child: Center(
                child: Text(
                  'Chọn một sản phẩm ở tab Scrape trước',
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor),
                ),
              ),
            )
          else ...[
            // Style selector
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
            // Duration selector
            Text('Thời lượng', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: {'15s': '15 giây', '30s': '30 giây', '60s': '60 giây'}.entries.map((e) {
                return ChoiceChip(
                  label: Text(e.value),
                  selected: _selectedDuration == e.key,
                  onSelected: (_) => setState(() => _selectedDuration = e.key),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Generate button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generating ? null : _generateScript,
                icon: _generating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome),
                label: Text(_generating ? 'Đang sinh...' : 'Generate Script'),
              ),
            ),
            const SizedBox(height: 16),
            // Generated script result
            if (_generatedScript != null)
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
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
                          ],
                        ),
                        const Divider(),
                        if (_generatedScript!['script'] != null) ...[
                          _buildScriptSection('🎣 Hook', _generatedScript!['script']['hook']),
                          _buildScriptSection('📝 Nội dung', _generatedScript!['script']['body']),
                          _buildScriptSection('📢 CTA', _generatedScript!['script']['cta']),
                          const Divider(),
                          _buildScriptSection('📜 Full Script', _generatedScript!['script']['full_script']),
                          _buildScriptSection('📱 Caption', _generatedScript!['script']['caption']),
                          if (_generatedScript!['script']['hashtags'] != null)
                            Wrap(
                              spacing: 4,
                              children: (_generatedScript!['script']['hashtags'] as List)
                                  .map((h) => Chip(label: Text(h, style: const TextStyle(fontSize: 11))))
                                  .toList(),
                            ),
                        ] else
                          Text(_generatedScript!['raw_text'] ?? 'No output'),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            _tabController.animateTo(2); // Go to Render tab
                          },
                          icon: const Icon(Icons.movie_creation),
                          label: const Text('Qua bước Render Video →'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
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

  Future<void> _generateScript() async {
    if (_selectedProductId == null || _generating) return;
    setState(() => _generating = true);
    try {
      final result = await AffiliateService.generateScript(
        productId: _selectedProductId!,
        style: _selectedStyle,
        duration: _selectedDuration,
      );
      setState(() => _generatedScript = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generate error: $e')));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // --- Tab 3: Render Video ---
  Widget _buildRenderTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TTS Toggle
          SwitchListTile(
            title: const Text('Sử dụng Voice (TTS)'),
            subtitle: const Text('Bật để thêm giọng đọc vào video'),
            value: _useTts,
            onChanged: (v) => setState(() => _useTts = v),
          ),
          const Divider(),
          const SizedBox(height: 8),
          // Render button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _selectedProductId == null || _generatedScript == null
                  ? null
                  : _startRender,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Bắt đầu Render Video'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
            ),
          ),
          if (_selectedProductId == null || _generatedScript == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Cần chọn sản phẩm và tạo script trước',
                style: TextStyle(color: theme.hintColor, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          // Job status
          if (_jobStatus != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildStatusIcon(_jobStatus!['status']),
                        const SizedBox(width: 8),
                        Text(
                          'Job: $_activeJobId',
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (_jobStatus!['progress'] ?? 0) / 100,
                    ),
                    const SizedBox(height: 4),
                    Text('${_jobStatus!['progress'] ?? 0}% • ${_jobStatus!['status']}'),
                    if (_jobStatus!['error'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _jobStatus!['error'],
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon(String? status) {
    switch (status) {
      case 'done':
        return const Icon(Icons.check_circle, color: Colors.green);
      case 'failed':
        return const Icon(Icons.error, color: Colors.red);
      case 'processing':
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      default:
        return const Icon(Icons.schedule, color: Colors.orange);
    }
  }

  Future<void> _startRender() async {
    final scriptText = _generatedScript?['script']?['full_script'] ??
        _generatedScript?['raw_text'] ??
        '';
    try {
      final jobId = await AffiliateService.startRenderVideo(
        productId: _selectedProductId!,
        scriptText: scriptText,
        useTts: _useTts,
      );
      setState(() {
        _activeJobId = jobId;
        _jobStatus = {'status': 'pending', 'progress': 0};
      });
      _startPolling(jobId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Render error: $e')));
      }
    }
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final status = await AffiliateService.getJobStatus(jobId);
        if (mounted) {
          setState(() => _jobStatus = status);
          if (status['status'] == 'done' || status['status'] == 'failed') {
            timer.cancel();
          }
        }
      } catch (_) {}
    });
  }

  // --- Tab 4: Smart Reup ---
  Widget _buildReupTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chọn transforms để áp dụng:', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: _transforms.entries.map((e) {
                return CheckboxListTile(
                  title: Text(e.key),
                  subtitle: Text(e.value, style: const TextStyle(fontSize: 12)),
                  value: _selectedTransforms[e.key] ?? false,
                  onChanged: (v) => setState(() => _selectedTransforms[e.key] = v ?? false),
                );
              }).toList(),
            ),
          ),
          const Divider(),
          // ComfyUI status
          Row(
            children: [
              Icon(
                _status['comfyui_available'] == true ? Icons.check_circle : Icons.cancel,
                color: _status['comfyui_available'] == true ? Colors.green : Colors.grey,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                'ComfyUI: ${_status['comfyui_available'] == true ? "Online" : "Offline"}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Selected video display
          if (_selectedVideoName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.video_file, size: 18),
                  const SizedBox(width: 4),
                  Expanded(child: Text(_selectedVideoName!, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _selectedVideoName = null),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _reupProcessing ? null : _pickAndReupVideo,
              icon: _reupProcessing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file),
              label: Text(_reupProcessing ? 'Đang xử lý...' : 'Chọn Video để Smart Reup'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
            ),
          ),
          // Reup result
          if (_reupResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                color: _reupResult!['error'] != null
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _reupResult!['error'] != null ? '❌ Lỗi' : '✅ Hoàn tất!',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      if (_reupResult!['error'] != null)
                        Text(_reupResult!['error'])
                      else ...[
                        Text('Output: ${_reupResult!['output_path'] ?? 'N/A'}'),
                        if (_reupResult!['transforms_applied'] != null)
                          Text('Applied: ${(_reupResult!['transforms_applied'] as List).join(', ')}'),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAndReupVideo() async {
    // Step 1: Pick video file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.first.path;
    if (filePath == null) return;

    setState(() {
      _selectedVideoName = result.files.first.name;
      _reupProcessing = true;
      _reupResult = null;
    });

    // Step 2: Get selected transforms
    final activeTransforms = _selectedTransforms.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (activeTransforms.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hãy chọn ít nhất 1 transform')),
        );
        setState(() => _reupProcessing = false);
      }
      return;
    }

    // Step 3: Upload and process
    try {
      final uploadResult = await AffiliateService.smartReupVideo(
        videoFile: File(filePath),
        transforms: activeTransforms,
      );
      if (mounted) setState(() => _reupResult = uploadResult);
    } catch (e) {
      if (mounted) {
        setState(() => _reupResult = {'error': e.toString()});
      }
    } finally {
      if (mounted) setState(() => _reupProcessing = false);
    }
  }

  // --- Helpers ---
  String _formatPrice(dynamic price) {
    if (price == null) return 'N/A';
    final p = price is num ? price : double.tryParse(price.toString()) ?? 0;
    return '${p.toStringAsFixed(0)}đ';
  }
}
