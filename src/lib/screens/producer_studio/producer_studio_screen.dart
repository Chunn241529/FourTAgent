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
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      body: IndexedStack(
        index: _currentIndex,
        children: [
          GenerateTab(taskType: 'text2music', tabController: _tabController),
          GenerateTab(taskType: 'cover', tabController: _tabController),
          GenerateTab(taskType: 'repaint', tabController: _tabController),
        ],
      ),
    );
  }
}
