import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String? _eid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    _eid ??= api.eid;
    final eid = _eid;
    if (eid == null) {
      setState(() {
        _loading = false;
        _error = '未获取到企业信息';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.getWalletOwner(eid);
      if (!mounted) return;
      if (r.isSuccess) {
        setState(() {
          _data = r.dataMap;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = '加载失败 (${r.code})';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = '网络异常';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('钱包')), body: const Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('钱包')), body: Center(child: Text(_error!)));

    final aw = _data?['aw'] as Map<String, dynamic>?;
    final total = (aw?['total'] as num?)?.toDouble() ?? 0;
    final cash = (aw?['olCash'] as num?)?.toDouble() ?? 0;
    final gift = (aw?['olGift'] as num?)?.toDouble() ?? 0;
    final eps = (_data?['eps'] as List? ?? []).cast<Map<String, dynamic>>();

    return Scaffold(
      appBar: AppBar(title: const Text('钱包')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [theme.colorScheme.primaryContainer, theme.colorScheme.secondaryContainer]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text('总余额', style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text('¥${total.toStringAsFixed(2)}',
                      style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _chip(theme, '现金 ¥${cash.toStringAsFixed(2)}'),
                      const SizedBox(width: 10),
                      _chip(theme, '赠送 ¥${gift.toStringAsFixed(2)}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (eps.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('全部钱包', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...eps.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: Icon(Icons.account_balance_wallet, color: theme.colorScheme.primary),
                      title: Text(w['name'] as String? ?? ''),
                      trailing: Text('¥${(w['total'] as num?)?.toDouble() ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () {
                        setState(() => _eid = w['ep']?['id'] as String?);
                        _load();
                      },
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(t, style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer)),
      );
}
