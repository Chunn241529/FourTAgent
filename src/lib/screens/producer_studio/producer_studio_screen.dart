import 'dart:ui';
import 'package:flutter/material.dart';
import 'tabs/generate_tab.dart';

class ProducerStudioScreen extends StatefulWidget {
  const ProducerStudioScreen({super.key});

  @override
  State<ProducerStudioScreen> createState() => _ProducerStudioScreenState();
}

class _ProducerStudioScreenState extends State<ProducerStudioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // Header chứa TabBar
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withOpacity(0.1),
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
            child: TabBar(
              controller: _tabController,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.brightness == Brightness.dark
                  ? Colors.white38
                  : Colors.black45,
              indicatorColor: theme.colorScheme.primary,
              tabs: const [
                Tab(text: 'TEXT2MUSIC'),
                Tab(text: 'COVER'),
                Tab(text: 'REPAINT'),
              ],
            ),
          ),
          // Nội dung tab
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                GenerateTab(taskType: 'text2music'),
                GenerateTab(taskType: 'cover'),
                GenerateTab(taskType: 'repaint'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
