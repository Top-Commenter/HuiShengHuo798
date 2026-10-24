import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import 'wallet_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _account;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final cached = await api.loadCachedMaster();
    if (cached != null && mounted) {
      setState(() => _account = cached['account'] as Map<String, dynamic>?);
    }
    final r = await api.getMaster();
    if (r.isSuccess && mounted) {
      setState(() => _account = r.dataMap?['account'] as Map<String, dynamic>?);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<SettingsProvider>();
    final name = _account?['name'] as String? ?? '未登录';
    final pn = _account?['pn'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primary,
                    child: const Icon(Icons.person, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(pn, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 钱包入口
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet, color: Colors.amber),
                  title: const Text('钱包'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 设置卡
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(settings.isDark ? Icons.dark_mode : Icons.light_mode, color: theme.colorScheme.primary),
                  title: const Text('深色模式'),
                  value: settings.isDark,
                  onChanged: (_) => settings.toggleTheme(),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: Icon(Icons.stars, color: settings.showScore ? theme.colorScheme.primary : Colors.grey),
                  title: const Text('显示积分模块'),
                  subtitle: Text(settings.showScore ? '底部标签页显示“积分”' : '已隐藏，积分功能仍可正常使用'),
                  value: settings.showScore,
                  onChanged: (v) => settings.setShowScore(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 退出登录
          Card(
            child: ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text('退出登录', style: TextStyle(color: theme.colorScheme.error)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('退出登录'),
                    content: const Text('确定退出当前账号吗？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
                    ],
                  ),
                );
                if (ok == true && mounted) {
                  await context.read<AuthProvider>().logout();
                  if (mounted) Navigator.of(context).pushReplacementNamed('/login');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
