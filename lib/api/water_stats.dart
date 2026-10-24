import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// 某一天的直饮机饮水总量。
class DailyWater {
  final DateTime day; // 本地日期 00:00
  final double liters;

  const DailyWater(this.day, this.liters);
}

/// 每日饮水量统计：只统计「直饮机 / 饮水机」，排除淋浴器（水表）。
/// 升数取自账单明细里 `bill.dev.subs[].out` 之和。
class WaterStatsApi {
  final ApiClient _api;

  WaterStatsApi(this._api);

  static const _keyDetailCache = 'water_detail_cache_v1';

  /// 近 7 天（含今天）每天的直饮机饮水升数，按日期升序，长度固定 7。
  Future<List<DailyWater>> last7Days() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: 6));

    final bills = <Map<String, dynamic>>[];
    for (var page = 0; page < 6; page++) {
      final resp = await _api.getBillList(page: page, size: 50);
      if (!resp.isSuccess) break;
      final list = (resp.dataList ?? []).cast<Map<String, dynamic>>();
      if (list.isEmpty) break;
      var reachedOlder = false;
      for (final b in list) {
        final ctime = b['ctime'] as int?;
        if (ctime == null) continue;
        final day = DateTime.fromMillisecondsSinceEpoch(ctime);
        if (day.isBefore(start)) {
          reachedOlder = true;
          break;
        }
        if (day.isAfter(now)) continue;
        if (!_isDrinkingBill(b)) continue;
        bills.add(b);
      }
      if (reachedOlder || list.length < 50) break;
    }

    // 明细升数：先查本地缓存，未命中的分批并发请求
    final cache = await _loadCache();
    final liters = <String, double>{};
    final missing = <Map<String, dynamic>>[];
    for (final b in bills) {
      final id = b['id']?.toString();
      if (id == null) continue;
      if (cache.containsKey(id)) {
        liters[id] = cache[id]!;
      } else {
        missing.add(b);
      }
    }
    for (var i = 0; i < missing.length; i += 5) {
      final batch = missing.skip(i).take(5).toList();
      final results = await Future.wait(batch.map(_fetchLiters));
      for (var j = 0; j < batch.length; j++) {
        final id = batch[j]['id']?.toString();
        if (id == null) continue;
        liters[id] = results[j];
        cache[id] = results[j];
      }
    }
    if (missing.isNotEmpty) await _saveCache(cache);

    // 按本地日期聚合
    final byDay = <String, double>{};
    for (final b in bills) {
      final ctime = b['ctime'] as int?;
      if (ctime == null) continue;
      final id = b['id']?.toString();
      if (id == null) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(ctime);
      final key = '${d.year}-${d.month}-${d.day}';
      byDay[key] = (byDay[key] ?? 0) + (liters[id] ?? 0);
    }

    return List.generate(7, (i) {
      final d = start.add(Duration(days: i));
      final key = '${d.year}-${d.month}-${d.day}';
      return DailyWater(d, byDay[key] ?? 0);
    });
  }

  /// 账单是否属于直饮机/饮水机（排除淋浴器、水表）。
  bool _isDrinkingBill(Map<String, dynamic> b) {
    if ((b['status'] as int?) != 3) return false; // 只算已付款
    final msg = b['msg'] as String? ?? '';
    if (msg.contains('淋浴') || msg.contains('水表')) return false;
    return msg.contains('直饮') || msg.contains('水控');
  }

  /// 单张账单的出水升数（`bill.dev.subs[].out` 求和）；失败返回 0。
  Future<double> _fetchLiters(Map<String, dynamic> bill) async {
    final id = bill['id']?.toString();
    if (id == null) return 0;
    try {
      final detail = await _api.getBillDetail(id);
      if (!detail.isSuccess) return 0;
      final billMap = detail.dataMap?['bill'];
      if (billMap is! Map) return 0;
      final dev = billMap['dev'];
      if (dev is! Map) return 0;
      final subs = dev['subs'];
      if (subs is! List) return 0;
      var sum = 0.0;
      for (final s in subs) {
        if (s is Map) sum += (s['out'] as num?)?.toDouble() ?? 0;
      }
      return sum;
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, double>> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDetailCache);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return json.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveCache(Map<String, double> cache) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDetailCache, jsonEncode(cache));
  }
}
