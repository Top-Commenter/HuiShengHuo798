import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class DeviceScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  const DeviceScreen({super.key, required this.deviceId, required this.deviceName});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  Map<String, dynamic>? _home;
  Map<String, dynamic>? _status;
  bool _loading = true;
  String? _error;

  double _outTotal = 0;
  double _outAtStart = 0;
  bool _running = false;
  bool _skipDetect = false;
  int _ptype = 21;
  List<Map<String, dynamic>> _payItems = [];
  Timer? _timer;
  double? _unitPrice; // 从本设备历史账单反推的单价（元/升）
  DateTime? _startedAt; // 本次启动时间，用于给服务端状态延迟留宽限期
  int _stoppedHit = 0; // 连续检测到“已停止”的次数

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AuthProvider>().api;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final home = await api.getDeviceHome(widget.deviceId);
      final status = await api.getDeviceStatus(widget.deviceId);
      if (!mounted) return;
      if (!home.isSuccess || !status.isSuccess) {
        setState(() {
          _loading = false;
          _error = '加载失败 (code: ${home.code}/${status.code})';
        });
        return;
      }
      setState(() {
        _home = home.dataMap;
        _status = status.dataMap;
        _loading = false;
      });
      _parse();
      await _deriveUnitPrice();
      if (mounted) setState(() {});
      if (_running) _startPolling();
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = '网络异常: $e';
      });
    }
  }

  void _parse() {
    final device = _status?['device'] as Map<String, dynamic>?;
    final gene = device?['gene'] as Map<String, dynamic>?;
    if (gene != null) {
      _outTotal = (gene['out'] as num?)?.toDouble() ?? _outTotal;
      final st = gene['status'] as int? ?? 99;
      if (!_skipDetect) {
        _running = st == 1;
        // 未运行（含刚进入页面）时把基线对齐当前读数，本次接水显示 0
        _outAtStart = _outTotal;
      }
    }
    final raw = _home?['payItems'] as List?;
    if (raw != null) {
      _payItems = raw.cast<Map<String, dynamic>>();
      _payItems.sort((a, b) => (b['seq'] as int? ?? 0).compareTo(a['seq'] as int? ?? 0));
      // 接水只有“按量”（type=21）计费，不再让用户在界面上选。
      // 万一某台设备没开通按量，才退回到它唯一支持的计费方式。
      if (_payItems.any((p) => (p['type'] as int?) == 21)) {
        _ptype = 21;
      } else if (_payItems.isNotEmpty) {
        _ptype = _payItems.first['type'] as int? ?? 21;
      }
    }
  }

  /// 从本设备的历史账单反推单价（元/升）：
  /// 账单详情里 `dev.subs[].out` 是本次出水升数，`bill.payment` 是本次金额。
  Future<void> _deriveUnitPrice() async {
    final api = context.read<AuthProvider>().api;
    try {
      final bills = await api.getBillList(size: 20);
      final list = bills.dataList ?? [];
      for (final raw in list) {
        if (raw is! Map) continue;
        // 列表里的 dev 只有 bm，没有设备 id，所以用 msg 里的设备名先粗筛
        final msg = raw['msg'] as String? ?? '';
        if (widget.deviceName.isNotEmpty && !msg.contains(widget.deviceName)) continue;
        if ((raw['type'] as int?) != _ptype) continue;
        final id = raw['id']?.toString();
        if (id == null) continue;
        final detail = await api.getBillDetail(id);
        if (!mounted) return;
        final bill = detail.dataMap?['bill'];
        if (bill is! Map) continue;
        final billDev = bill['dev'];
        if (billDev is! Map) continue;
        final devId = billDev['id']?.toString();
        if (devId != null && devId != widget.deviceId) continue;
        final subs = billDev['subs'];
        var liters = 0.0;
        if (subs is List) {
          for (final s in subs) {
            if (s is Map) liters += (s['out'] as num?)?.toDouble() ?? 0;
          }
        }
        final payment = (bill['payment'] as num?)?.toDouble() ?? 0;
        if (liters > 0 && payment > 0) {
          _unitPrice = payment / liters;
          debugPrint('[dev] unitPrice=$_unitPrice (payment=$payment liters=$liters)');
          return;
        }
      }
    } catch (e) {
      debugPrint('[dev] deriveUnitPrice failed: $e');
    }
  }

  /// 从 payItems 中尽力解析当前计费单价（元/升）。
  double? get _pricePerLiter {
    for (final p in _payItems) {
      if ((p['type'] as int?) != _ptype) continue;
      for (final k in ['price', 'amt', 'amount', 'unitPrice', 'fee', 'prc', 'pricePerLiter']) {
        final v = p[k];
        if (v is num && v > 0) {
          // 接口可能以"分"或"元"存储；>10 视为分转元
          return v > 10 ? v / 100 : v.toDouble();
        }
      }
    }
    return null;
  }

  /// 按次计费时的固定费用。
  double? get _fixedFee {
    for (final p in _payItems) {
      if ((p['type'] as int?) != _ptype) continue;
      for (final k in ['fee', 'price', 'amt']) {
        final v = p[k];
        if (v is num && v > 0) return v > 10 ? v / 100 : v.toDouble();
      }
    }
    return null;
  }

  double get _used => (_outTotal - _outAtStart).clamp(0, double.infinity);

  double? get _liveCost {
    if (!_running) return null;
    // 单价来自本设备历史账单反推；用量 × 单价 即本次实时费用
    final p = _unitPrice ?? _pricePerLiter;
    if (p != null) return _used * p;
    // 按次计费的固定费用
    if (_ptype == 91) return _fixedFee;
    return null;
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> _poll() async {
    if (!mounted) return;
    final api = context.read<AuthProvider>().api;
    try {
      final r = await api.getDeviceStatus(widget.deviceId);
      if (!mounted || !r.isSuccess) return;
      final gene = r.dataMap?['device']?['gene'] as Map<String, dynamic>?;
      final prevOut = _outTotal;
      if (gene != null) {
        _outTotal = (gene['out'] as num?)?.toDouble() ?? _outTotal;
      }
      setState(() {
        _status = r.dataMap;
      });
      // 服务端状态有延迟：刚启动时可能还是「已停止」，不能一票否决，
      // 否则刚点完“开始”就把“停止”按钮又置灰了。
      // 判据：status==1 或 出水读数在涨，都算在出水。
      final st = (gene?['status'] as int?) ?? 0;
      final grew = _outTotal > prevOut + 0.0001;
      if (st == 1 || grew) {
        _stoppedHit = 0;
      } else if (_running) {
        final grace = _startedAt != null &&
            DateTime.now().difference(_startedAt!).inSeconds < 15;
        if (!grace) {
          _stoppedHit++;
          if (_stoppedHit >= 5) {
            setState(() => _running = false);
            _timer?.cancel();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _start() async {
    final api = context.read<AuthProvider>().api;
    try {
      final r = await api.startDevice(widget.deviceId, ptype: _ptype);
      if (!mounted) return;
      if (r.isSuccess) {
        setState(() {
          _running = true;
          _outAtStart = _outTotal;
          _startedAt = DateTime.now();
          _stoppedHit = 0;
        });
        _startPolling();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设备已启动')));
      } else {
        // 把服务端给的失败原因一起显示出来，否则只看到一个 code 无从排查
        debugPrint('[dev] start 失败: code=${r.code} msg=${r.msg}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.msg != null ? '启动失败(${r.code})：${r.msg}' : '启动失败 (${r.code})'),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('异常: $e')));
    }
  }

  Future<void> _stop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('停止'),
        content: const Text('确定要停止当前设备吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = context.read<AuthProvider>().api;
    try {
      await api.stopDevice(widget.deviceId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _running = false;
      _skipDetect = true;
      _timer?.cancel();
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _skipDetect = false;
        _load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallet = _home?['wallet'] as Map<String, dynamic>?;
    final balance = (wallet?['olCash'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(widget.deviceName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _load, child: const Text('重试')),
                ]))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    // 主状态卡
                    Card(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: _running
                              ? LinearGradient(colors: [theme.colorScheme.primaryContainer, theme.colorScheme.secondaryContainer])
                              : null,
                        ),
                        child: Column(
                          children: [
                            Icon(_running ? Icons.water_drop : Icons.water_drop_outlined,
                                size: 56, color: _running ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text(_running ? '运行中' : '已停止',
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _stat(theme, '累计出水', '${_outTotal.toStringAsFixed(1)} L'),
                                _stat(theme, '本次接水', '${_used.toStringAsFixed(1)} L'),
                                _stat(theme, '实时费用', _liveCost != null ? '¥${_liveCost!.toStringAsFixed(2)}' : '—', highlight: true),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 余额卡
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('钱包余额', style: theme.textTheme.bodyMedium),
                            Text('¥${balance.toStringAsFixed(2)}',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _running ? null : _start,
                      child: const Text('开始'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _running ? _stop : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.errorContainer,
                        foregroundColor: theme.colorScheme.onErrorContainer,
                      ),
                      child: const Text('停止'),
                    ),
                  ],
                ),
    );
  }

  Widget _stat(ThemeData theme, String label, String value, {bool highlight = false}) {
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: highlight ? theme.colorScheme.primary : null,
            )),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
