import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/sign_utils.dart';

class ScoreScreen extends StatefulWidget {
  const ScoreScreen({super.key});

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  Map<String, dynamic>? _missionData;
  List<dynamic> _history = [];
  bool _loading = true;
  String? _error;
  bool _autoClaiming = false;
  int _localTs = 0, _serverTs = 0;

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
      _localTs = DateTime.now().millisecondsSinceEpoch;
      final results = await Future.wait([api.getMissionList(), api.getScoreList()]);
      if (!mounted) return;
      setState(() {
        if (results[0].isSuccess) {
          _missionData = results[0].dataMap;
          _serverTs = results[0].time ?? _localTs;
        }
        if (results[1].isSuccess) _history = results[1].dataList ?? [];
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = '网络异常';
      });
    }
  }

  Set<String> get _exhausted {
    final limits = _missionData?['accScoreRsp']?['limits'] as List? ?? [];
    final s = <String>{};
    for (final l in limits) {
      final m = l as Map<String, dynamic>;
      if ((m['limit'] as int? ?? 0) <= 0) s.add(m['refId'] as String? ?? '');
    }
    return s;
  }

  Future<bool> _claim(Map<String, dynamic> m, {bool silent = false}) async {
    final api = context.read<AuthProvider>().api;
    final refId = m['refId'] as String?;
    final score = m['score'] as int?;
    final token = api.token;
    final uid = api.uid;
    if (refId == null || score == null || token == null || uid == null) return false;
    try {
      for (var i = 0; i < 3; i++) {
        final sign = SignUtils.generateScoreSign(
          adId: refId, token: token, uid: uid, localTs: _localTs, serverTs: _serverTs,
        );
        final r = await api.sendScore(adId: refId, score: score, sign: sign);
        if (!mounted) return false;
        if (r.isSuccess) return true;
        if (r.code != -98) return false;
        await Future.delayed(Duration(seconds: 8 + i * 5));
      }
    } catch (_) {}
    return false;
  }

  Future<void> _claimAll() async {
    final api = context.read<AuthProvider>().api;
    final missions = (_missionData?['missions'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((m) => (m['score'] as int? ?? 0) > 0 && !_exhausted.contains(m['refId']))
        .toList();
    if (missions.isEmpty) return;
    setState(() => _autoClaiming = true);
    var claimed = 0;
    for (final m in missions) {
      if (!mounted) break;
      if (await _claim(m, silent: true)) claimed++;
      if (missions.indexOf(m) < missions.length - 1) {
        _localTs = DateTime.now().millisecondsSinceEpoch;
        final ml = await api.getMissionList();
        if (ml.isSuccess && mounted) {
          _missionData = ml.dataMap;
          _serverTs = ml.time ?? _localTs;
        }
        await Future.delayed(const Duration(seconds: 10));
      }
    }
    if (mounted) {
      setState(() => _autoClaiming = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('完成：领取 $claimed 个任务')));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoreInfo = _missionData?['accScoreRsp'] as Map<String, dynamic>?;
    final score = scoreInfo?['score'] as String? ?? '0';
    final total = scoreInfo?['totalScore'] as String? ?? '0';

    return Scaffold(
      appBar: AppBar(
        title: const Text('积分中心'),
        bottom: TabBar(controller: _tab, tabs: const [Tab(text: '赚积分'), Tab(text: '明细')]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)))
              : Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(children: [
                            Text(score, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
                            Text('可用积分', style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer)),
                          ]),
                          Column(children: [
                            Text(total, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
                            Text('累计获得', style: TextStyle(fontSize: 12, color: theme.colorScheme.onPrimaryContainer)),
                          ]),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tab,
                        children: [_missionsTab(), _historyTab()],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _missionsTab() {
    final missions = (_missionData?['missions'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((m) => (m['score'] as int? ?? 0) > 0)
        .toList();
    final exh = _exhausted;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (missions.any((m) => !exh.contains(m['refId']))) ...[
            FilledButton.icon(
              onPressed: _autoClaiming ? null : _claimAll,
              icon: _autoClaiming
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.stars),
              label: Text(_autoClaiming ? '领取中…' : '一键领取'),
            ),
            const SizedBox(height: 12),
          ],
          if (missions.isEmpty)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('暂无任务')))
          else
            ...missions.map((m) {
              final refId = m['refId'] as String? ?? '';
              final done = exh.contains(refId);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: done ? Colors.grey[200] : Colors.orange[50],
                          child: Text('+${m['score']}', style: TextStyle(color: done ? Colors.grey : Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              Text(m['desc'] as String? ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        done
                            ? const Text('已领完', style: TextStyle(fontSize: 12, color: Colors.grey))
                            : TextButton(
                                onPressed: () async {
                                  await _claim(m);
                                  _load();
                                },
                                child: const Text('领取'),
                              ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _historyTab() {
    if (_history.isEmpty) return const Center(child: Text('暂无积分记录'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _history.length,
        itemBuilder: (_, i) {
          final item = _history[i] as Map<String, dynamic>;
          final data = item['data'] as Map<String, dynamic>?;
          final src = item['src'] as int? ?? 0;
          final income = src != 105;
          final score = int.tryParse(data?['score'] as String? ?? '0') ?? 0;
          final title = data?['adName'] as String? ?? item['msg'] as String? ?? '';
          final ctime = item['ctime'] as int?;
          final time = ctime != null ? DateTime.fromMillisecondsSinceEpoch(ctime).toString().substring(0, 16) : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                leading: Icon(income ? Icons.add_circle_outline : Icons.remove_circle_outline, color: income ? Colors.green : Colors.red),
                title: Text(title, style: const TextStyle(fontSize: 14)),
                subtitle: Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                trailing: Text('${income ? "+" : "-"}$score', style: TextStyle(fontWeight: FontWeight.bold, color: income ? Colors.green : Colors.red)),
              ),
            ),
          );
        },
      ),
    );
  }
}
