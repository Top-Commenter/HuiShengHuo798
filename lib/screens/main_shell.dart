import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'home_screen.dart';
import 'bill_screen.dart';
import 'score_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  /// 逻辑标签页：0=设备 1=账单 2=积分 3=我的。
  /// 用逻辑下标而不是可见下标，这样“显示积分模块”开关一动，
  /// 当前所在页面不会跟着错位跳到别的页。
  static const _tabScore = 2;
  static const _tabProfile = 3;

  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    // 积分模块可以在“我的 → 设置”里关掉，关掉后底部不再出现该标签页
    final showScore = context.watch<SettingsProvider>().showScore;

    final visible = <int>[0, 1, if (showScore) _tabScore, _tabProfile];
    final pages = <Widget>[
      const HomeScreen(),
      const BillScreen(),
      if (showScore) const ScoreScreen(),
      const ProfileScreen(),
    ];
    final found = visible.indexOf(_tab);
    // 当前页被关掉时（例如正停在“积分”），退回“我的”
    final index = found >= 0 ? found : visible.length - 1;

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _tab = visible[i]),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop),
            label: '设备',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '账单',
          ),
          if (showScore)
            const NavigationDestination(
              icon: Icon(Icons.stars_outlined),
              selectedIcon: Icon(Icons.stars),
              label: '积分',
            ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
