import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class BillScreen extends StatefulWidget {
  const BillScreen({super.key});

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen> {
  List<dynamic> _bills = [];
  bool _loading = true;
  String? _error;
  int? _statusFilter;

  double _totalAmount = 0;
  int _totalCount = 0;
  bool _calculatingTotal = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await api.getBillList(status: _statusFilter, size: 50);
      if (!mounted) return;
      if (resp.isSuccess) {
        setState(() {
          _bills = resp.dataList ?? [];
          _loading = false;
        });
        _calcTotal();
      } else {
        setState(() {
          _loading = false;
          _error = '加载失败 (${resp.code})';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = '网络异常';
      });
    }
  }

  /// 拉取全部分页累计总额（最多 10 页 = 500 条）。
  Future<void> _calcTotal() async {
    final api = context.read<AuthProvider>().api;
    setState(() => _calculatingTotal = true);
    double sum = 0;
    int count = 0;
    try {
      for (var page = 0; page < 10; page++) {
        final resp = await api.getBillList(status: _statusFilter, page: page, size: 50);
        if (!resp.isSuccess) break;
        final list = resp.dataList ?? [];
        if (list.isEmpty) break;
        for (final b in list) {
          final m = b as Map<String, dynamic>;
          // 只统计已付款（status=3）的实际支出
          if ((m['status'] as int?) == 3) {
            sum += (m['payment'] as num?)?.toDouble() ?? 0;
            count++;
          }
        }
        if (list.length < 50) break;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _totalAmount = sum;
      _totalCount = count;
      _calculatingTotal = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const filters = <MapEntry<int?, String>>[
      MapEntry(null, '全部'),
      MapEntry(3, '已付款'),
      MapEntry(2, '待确认'),
      MapEntry(1, '未付款'),
      MapEntry(4, '失败'),
      MapEntry(9, '已取消'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('消费记录')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // 总额卡
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('累计支出', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          _calculatingTotal
                              ? const SizedBox(height: 26, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                              : Text('¥${_totalAmount.toStringAsFixed(2)}',
                                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('已付款笔数', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text('$_totalCount 笔', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 状态筛选
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filters.map((f) {
                  final selected = _statusFilter == f.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.value),
                      selected: selected,
                      onSelected: (_) {
                        _statusFilter = f.key;
                        _load();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(padding: const EdgeInsets.all(20), child: Center(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))))
            else if (_bills.isEmpty)
              const Padding(padding: EdgeInsets.all(60), child: Center(child: Text('暂无记录')))
            else
              ..._bills.map((b) => _billCard(b as Map<String, dynamic>)),
          ],
        ),
      ),
    );
  }

  Widget _billCard(Map<String, dynamic> b) {
    final theme = Theme.of(context);
    final payment = (b['payment'] as num?)?.toDouble() ?? 0;
    final ctime = b['ctime'] as int?;
    final timeStr = ctime != null
        ? DateTime.fromMillisecondsSinceEpoch(ctime).toString().substring(0, 16)
        : '';
    final type = b['type'] as int? ?? 0;
    final status = b['status'] as int? ?? 0;
    final msg = b['msg'] as String? ?? '消费';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.water_drop, color: theme.colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(msg, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 3),
                    Text('${type == 21 ? "按量" : type == 91 ? "按次" : ""} · $timeStr',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('-¥${payment.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(_statusText(status), style: TextStyle(fontSize: 11, color: _statusColor(status))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(int s) => switch (s) {
        1 => '未付款', 2 => '待确认', 3 => '已付款', 4 => '失败', 9 => '已取消', _ => '未知',
      };

  Color? _statusColor(int s) => switch (s) {
        3 => Colors.green, 2 => Colors.blue, 1 => Colors.orange, 4 => Colors.red, 9 => Colors.grey, _ => null,
      };
}
