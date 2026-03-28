import 'dart:ui';
import 'package:flutter/material.dart';
import 'tabs/generate_tab.dart';
import 'tabs/edit_tab.dart';

class ImageStudioScreen extends StatefulWidget {
  const ImageStudioScreen({super.key});

  @override
  State<ImageStudioScreen> createState() => _ImageStudioScreenState();
}

class _ImageStudioScreenState extends State<ImageStudioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _currentIndex = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // ── Top bar ──
          Container(
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
            child: Row(
              children: [
                // Logo & title
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary.withOpacity(0.15),
                        theme.colorScheme.secondary.withOpacity(0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.palette_outlined,
                      color: theme.colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Text('Image Studio',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),

                const Spacer(),

                // ── Segmented tab selector ──
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicator: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.10)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              )
                            ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: isDark ? Colors.white : Colors.black87,
                    unselectedLabelColor:
                        isDark ? Colors.white54 : Colors.black45,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    labelPadding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    tabs: const [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome, size: 16),
                            SizedBox(width: 8),
                            Text('Generate'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.brush_outlined, size: 16),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),
                // balance the row
                const SizedBox(width: 180),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // ── Content: IndexedStack keeps both tabs alive ──
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                GenerateTab(),
                EditTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
