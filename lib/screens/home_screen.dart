import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/water_stats.dart';
import '../providers/auth_provider.dart';
import 'device_screen.dart';
import 'qr_scan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _master;
  bool _loading = true;
  String? _error;
  final Set<String> _running = {};

  List<DailyWater>? _water; // null = 加载中
  bool _waterFailed = false;

  /// 本地记住的设备顺序（设备 id 列表），不写回服务端。
  static const _orderKey = 'device_order_v1';
  List<String> _order = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadWater();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_orderKey) ?? [];
    if (mounted) setState(() => _order = saved);
  }

  /// 按本地保存的顺序排列设备，未保存过的新设备排在末尾。
  List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> favos) {
    final pos = {for (var i = 0; i < _order.length; i++) _order[i]: i};
    final list = List<Map<String, dynamic>>.of(favos);
    list.sort((a, b) {
      final ai = pos[a['id']];
      final bi = pos[b['id']];
      if (ai == null && bi == null) return 0;
      if (ai == null) return 1;
      if (bi == null) return -1;
      return ai.compareTo(bi);
    });
    return list;
  }

  Future<void> _onReorder(
      List<Map<String, dynamic>> shown, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final ids = shown.map((f) => f['id'] as String? ?? '').toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    setState(() => _order = ids);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, ids);
  }

  /// 近 7 天直饮机饮水看板，独立加载，不阻塞设备列表。
  Future<void> _loadWater() async {
    final api = context.read<AuthProvider>().api;
    if (mounted) {
      setState(() {
        _water = null;
        _waterFailed = false;
      });
    }
    try {
      final data = await WaterStatsApi(api).last7Days();
      if (!mounted) return;
      setState(() => _water = data);
    } catch (_) {
      if (mounted) setState(() => _waterFailed = true);
    }
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    final cached = await api.loadCachedMaster();
    if (cached != null && mounted) {
      setState(() {
        _master = cached;
        _loading = false;
      });
    }
    try {
      final resp = await api.getMaster();
      if (!mounted) return;
      if (resp.isSuccess) {
        // token 过期时服务端按“未登录”返回 code 0 + 只有 ads 的空数据，
        // 直接采用就会变成“还没有绑定设备”，看起来像设备被解绑了。
        // 这里识别出来，退回登录页让用户重新登录。
        if (resp.dataMap?['account'] == null) {
          await _toLogin();
          return;
        }
        setState(() {
          _master = resp.dataMap;
          _loading = false;
          _error = null;
        });
      } else if (resp.isSessionExpired) {
        await _toLogin();
      } else if (_master == null) {
        setState(() => _error = '加载失败 (code: ${resp.code})');
      }
    } catch (e) {
      if (mounted && _master == null) setState(() => _error = '网络异常');
    }
  }

  /// 会话失效：清掉本地登录态并退回登录页。
  Future<void> _toLogin() async {
    if (!mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(
      '/login',
      arguments: '登录已过期，请重新登录（手机号已帮你填好）',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favos = (_master?['favos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final shown = _sorted(favos);
    final account = _master?['account'] as Map<String, dynamic>?;
    final name = account?['name'] as String? ?? '朋友';

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的设备'),
        actions: [
          IconButton(
            tooltip: '扫码添加设备',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              final added = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const QrScanScreen()),
              );
              if (added == true) {
                _load();
                _loadWater();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_load(), _loadWater()]);
        },
        // 用 CustomScrollView + SliverReorderableList 保持单一滚动上下文：
        // 设备卡若嵌在另一个 ListView 里，父级滚动会吞掉排序手势。
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    // 问候卡
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('你好，$name',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(_greeting(),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            if (_running.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text('${_running.length} 台运行中',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onPrimaryContainer,
                                        fontWeight: FontWeight.w600)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _waterCard(theme),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                    padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              )
            else if (_error != null)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(children: [
                        Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('重试')),
                      ]),
                    ),
                  ),
                ),
              )
            else if (shown.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(children: [
                        Icon(Icons.water_drop_outlined,
                            size: 44, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        const Text('还没有绑定设备'),
                      ]),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverReorderableList(
                  itemCount: shown.length,
                  onReorder: (o, n) => _onReorder(shown, o, n),
                  itemBuilder: (_, i) => _deviceCard(shown[i], i),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  /// 每日饮水看板：今日总量 + 近 7 天柱状图（仅直饮机）。
  Widget _waterCard(ThemeData theme) {
    final data = _water;
    final todayLiters = (data != null && data.isNotEmpty) ? data.last.liters : 0.0;
    final avg = (data == null || data.isEmpty)
        ? 0.0
        : data.fold<double>(0, (a, d) => a + d.liters) / data.length;
    final maxLiters =
        data == null || data.isEmpty ? 0.0 : data.map((d) => d.liters).reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('今日饮水',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text('${todayLiters.toStringAsFixed(1)} L',
                          style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                    ],
                  ),
                ),
                if (data != null)
                  Text('7天日均 ${avg.toStringAsFixed(1)} L',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 16),
            if (_waterFailed)
              Row(
                children: [
                  Text('饮水数据加载失败',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _loadWater,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(56, 28), padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: const Text('重试', style: TextStyle(fontSize: 12)),
                  ),
                ],
              )
            else if (data == null)
              const SizedBox(
                height: 96,
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (maxLiters <= 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('暂无饮水记录', style: TextStyle(fontSize: 12, color: Colors.grey))),
              )
            else
              SizedBox(
                height: 96,
                child: Row(
                  children: [
                    for (var i = 0; i < data.length; i++)
                      _waterBar(theme, data[i], maxLiters, i == data.length - 1),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _waterBar(ThemeData theme, DailyWater d, double maxLiters, bool isToday) {
    final ratio = maxLiters <= 0 ? 0.0 : d.liters / maxLiters;
    final h = d.liters <= 0 ? 0.0 : (ratio * 64).clamp(3.0, 64.0);
    final color = isToday ? theme.colorScheme.primary : theme.colorScheme.primary.withValues(alpha: 0.35);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: h,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _weekday(d.day),
              style: TextStyle(
                fontSize: 11,
                color: isToday ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _weekday(DateTime d) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    return '周${names[d.weekday - 1]}';
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return '夜深了，注意休息';
    if (h < 11) return '早上好，记得喝水';
    if (h < 14) return '中午好，补水时间';
    if (h < 18) return '下午好，来杯水';
    return '晚上好';
  }

  Widget _deviceCard(Map<String, dynamic> f, int index) {
    final theme = Theme.of(context);
    final id = f['id'] as String? ?? '';
    final name = f['name'] as String? ?? '未知设备';
    final addr = f['addr'] as Map<String, dynamic>?;
    final detail = addr?['detail'] as String? ?? '';
    final city = addr?['city'] as String? ?? '';
    final running = _running.contains(id);

    return Padding(
      key: ValueKey(id),
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            final res = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => DeviceScreen(deviceId: id, deviceName: name)),
            );
            if (!mounted) return;
            setState(() {
              if (res == true) {
                _running.add(id);
              } else {
                _running.remove(id);
              }
            });
            _load();
          },
          onLongPress: () => _removeDevice(id, name),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: running ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(running ? Icons.water_drop : Icons.water_drop_outlined,
                      color: running ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                          if (running)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(6)),
                              child: const Text('运行中', style: TextStyle(color: Colors.white, fontSize: 10)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('$city $detail'.trim(),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.drag_handle, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _removeDevice(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除设备'),
        content: Text('确定从列表移除「$name」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('移除', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final resp = await context.read<AuthProvider>().api.favoriteDevice(id, remove: true);
    if (mounted) {
      if (resp.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移除')));
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('失败 (${resp.code})')));
      }
    }
  }
}
