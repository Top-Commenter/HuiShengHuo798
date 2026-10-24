import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 惠生活798 业务 API 客户端（仅业务数据接口，无任何广告相关请求）。
class ApiClient {
  static const String _baseUrl = 'https://i.ilife798.com';

  /// 单次请求上限。没有它时服务端只建连不回包会让界面一直转圈。
  static const Duration _timeout = Duration(seconds: 20);
  static const _keyToken = 'auth_token';
  static const _keyUid = 'auth_uid';
  static const _keyEid = 'auth_eid';
  static const _keyLastPhone = 'last_phone';

  late final http.Client _client;

  String? _token;
  String? _uid;
  String? _eid;

  ApiClient() {
    _client = _createClient();
  }

  http.Client _createClient() {
    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 15);
    // 学习项目：关闭证书校验以便个人使用（与服务端未配置 pinning 一致）
    httpClient.badCertificateCallback = (_, _, _) => true;
    return IOClient(httpClient);
  }

  /// 伪造的客户端版本号，与官方版本保持一致。
  ///
  /// 服务端对部分接口（已实测 /api/v1/dev/start）做了最低版本校验：
  /// 之前报 3.1.4 时返回 `{"code":-1,"msg":"请升级最新版APP"}`，启动设备必失败；
  /// 改成 3.2.0 后同一请求返回 code 0，设备正常启动。
  static const String _appVersion = '3.2.0';

  Map<String, String> get _baseHeaders => {
        'ApplicationType': '1,1',
        'VersionCode': _appVersion,
        'user-agent': 'Android_ilife798_$_appVersion',
      };

  Map<String, String> get _authHeaders {
    final h = <String, String>{..._baseHeaders};
    final t = _token;
    if (t != null) h['Authorization'] = t;
    return h;
  }

  double _randS() => Random().nextDouble();

  // ── 登录 ─────────────────────────────────────────────

  /// 获取图片验证码。
  Future<CaptchaResult> getCaptcha() async {
    final s = _randS();
    final r = DateTime.now().millisecondsSinceEpoch;
    final url = Uri.parse('$_baseUrl/api/v1/captcha/?s=$s&r=$r');
    final resp = await _client
        .get(url, headers: {
          'User-Agent':
              'Dalvik/2.1.0 (Linux; U; Android 16; PHP110 Build/BP2A.250605.015)',
        })
        .timeout(_timeout);
    final bytes = resp.bodyBytes;
    if (resp.statusCode != 200 || !_looksLikeImage(bytes)) {
      throw HttpException(
        '验证码接口返回异常 (HTTP ${resp.statusCode}, ${bytes.length} 字节)',
      );
    }
    return CaptchaResult(
      s: s,
      r: r,
      imageBytes: bytes,
      contentType: resp.headers['content-type'] ?? 'image/png',
    );
  }

  /// 按文件头判断响应体是不是真图片（服务端 Content-Type 不可信）。
  bool _looksLikeImage(List<int> b) {
    if (b.length < 4) return false;
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) return true; // PNG
    if (b[0] == 0xff && b[1] == 0xd8) return true; // JPEG
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true; // GIF
    return false;
  }

  /// 发送短信验证码。
  Future<ApiResponse> sendSmsCode({
    required String phone,
    required String captchaCode,
    required double captchaS,
  }) async {
    final resp = await _post('/api/v1/acc/login/code', data: {
      'authCode': captchaCode,
      's': captchaS,
      'un': phone,
    });
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// 短信验证码登录。
  Future<ApiResponse> login({required String phone, required String smsCode}) async {
    final resp = await _post('/api/v1/acc/login', data: {
      'authCode': smsCode,
      'un': phone,
    });
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = ApiResponse.fromJson(json);
    if (result.code == 0) {
      final data = json['data'];
      final al = data is Map ? data['al'] : null;
      if (al is Map) {
        _token = al['token'] as String?;
        _uid = al['uid'] as String?;
        _eid = al['eid'] as String?;
        try {
          await _persistToken();
          await _saveLastPhone(phone);
        } catch (e) {
          // 本地写入失败不应让登录本身失败，本次会话仍可用
          debugPrint('[api] 登录态持久化失败: $e');
        }
      }
    }
    return result;
  }

  // ── 设备 ─────────────────────────────────────────────

  /// 主数据：设备列表 + 账号信息。
  Future<ApiResponse> getMaster() async {
    final resp = await _get('/api/v1/ui/app/master');
    final result = ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    // 登录态失效时服务端会按“未登录”返回 code 0 + 只有 ads 的空壳（account 为空），
    // 缓存它会让下次启动看起来像“设备全没了”，所以只缓存带账号信息的完整响应。
    if (result.isSuccess && result.dataMap?['account'] != null) {
      await _cacheMaster(resp.body);
    }
    return result;
  }

  Future<Map<String, dynamic>?> loadCachedMaster() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cache_master');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final data = json['data'];
      // 同样跳过没有账号信息的空壳，否则启动时会先闪一下“还没有绑定设备”
      if (json['code'] == 0 && data is Map<String, dynamic> && data['account'] != null) {
        return data;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _cacheMaster(String body) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cache_master', body);
  }

  /// 设备首页数据（含计费方式 payItems、余额）。
  Future<ApiResponse> getDeviceHome(String deviceId, {int apply = 6}) async {
    final resp =
        await _get('/api/v1/ui/app/dev/home/1?did=$deviceId&apply=$apply');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// 设备实时状态。
  Future<ApiResponse> getDeviceStatus(String deviceId) async {
    final resp =
        await _get('/api/v1/ui/app/dev/status?did=$deviceId&more=false');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// 启动设备（取水）。
  Future<ApiResponse> startDevice(String deviceId, {int ptype = 21}) async {
    final resp = await _get(
      '/api/v1/dev/start?did=$deviceId&upgrade=true&ptype=$ptype&args=&rcp=false&cnt=1',
    );
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// 停止设备。
  Future<ApiResponse> stopDevice(String deviceId) async {
    final resp = await _get('/api/v1/dev/end?did=$deviceId&rcp=false');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// 设备取水状态（qr/use，含本次用量与费用明细）。
  Future<ApiResponse> getDeviceQr(String deviceId) async {
    final resp = await _get('/api/v1/qr/use?id=$deviceId');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// 收藏 / 取消收藏设备。
  Future<ApiResponse> favoriteDevice(String deviceId, {bool remove = false}) async {
    final resp = await _get('/api/v1/dev/favo?did=$deviceId&remove=${remove ? 1 : 0}');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ── 账户 / 积分 ─────────────────────────────────────

  Future<ApiResponse> getAccount() async {
    final resp = await _get('/api/v1/acc/');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// 积分任务列表。
  Future<ApiResponse> getMissionList() async {
    final resp = await _get('/api/v1/acc/score/mission-lst');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// 领取积分。
  Future<ApiResponse> sendScore({
    required String adId,
    required int score,
    required String sign,
    int addScoreType = 1,
  }) async {
    final resp = await _post('/api/v1/acc/score/score-send?sign=$sign&s=1', data: {
      'adId': adId,
      'type': 101,
      'addScoreType': addScoreType,
      'addScore': score,
      'token': _token ?? '',
    });
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// 积分明细。src: null=全部, 101=收入, 105=支出。
  Future<ApiResponse> getScoreList({int page = 0, int size = 20, int? src}) async {
    final srcStr = src != null ? '&src=$src' : '';
    final resp = await _get('/api/v1/acc/score/score-lst?page=$page&size=$size&hasCount=true$srcStr');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// 切换积分抵扣。
  Future<ApiResponse> setUseScore(bool enable) async {
    final resp = await _post('/api/v1/acc/upt', data: {'useScore': enable ? 1 : 0});
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ── 账单 ─────────────────────────────────────────────

  /// 账单列表。status: null=全部, 1=未付款, 2=待确认, 3=已付款, 4=失败, 9=已取消。
  Future<ApiResponse> getBillList({int page = 0, int size = 20, int? status}) async {
    final statusStr = status != null ? '&status=$status' : '';
    final resp = await _get('/api/v1/bill/lst-owner?page=$page&size=$size&hasCount=true$statusStr');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// 账单详情。
  Future<ApiResponse> getBillDetail(String billId) async {
    final resp = await _get('/api/v1/bill/view-full?id=$billId');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ── 钱包 ─────────────────────────────────────────────

  Future<ApiResponse> getWalletOwner(String eid) async {
    final resp = await _get('/api/v1/acc/wallet/owner?eid=$eid&all=true');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<ApiResponse> checkPga(String eid) async {
    final resp = await _get('/api/v1/ui/app/pga-check?eid=$eid&isCombine=false');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<ApiResponse> getPgaChannels() async {
    final resp = await _get('/api/v1/ui/app/acc-pgas');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<ApiResponse> getPgaSign(int type) async {
    final resp = await _get('/api/v1/ui/app/sign-pga?type=$type');
    return ApiResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ── 登录态 ───────────────────────────────────────────

  bool get isLoggedIn => _token != null;
  String? get token => _token;
  String? get uid => _uid;
  String? get eid => _eid;

  Future<void> _persistToken() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) {
      await prefs.setString(_keyToken, _token!);
      await prefs.setString(_keyUid, _uid ?? '');
      await prefs.setString(_keyEid, _eid ?? '');
    }
  }

  /// 上次登录用的手机号。服务端 token 有有效期，失效后拿它预填登录框，
  /// 用户只需要再收一次短信验证码，不用重新敲手机号。
  Future<String?> loadLastPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final p = prefs.getString(_keyLastPhone);
    return (p != null && p.isNotEmpty) ? p : null;
  }

  Future<void> _saveLastPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastPhone, phone);
  }

  Future<bool> restoreToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_keyToken);
    if (t != null && t.isNotEmpty) {
      _token = t;
      _uid = prefs.getString(_keyUid);
      _eid = prefs.getString(_keyEid);
      return true;
    }
    return false;
  }

  Future<void> clearToken() async {
    _token = null;
    _uid = null;
    _eid = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUid);
    await prefs.remove(_keyEid);
  }

  Future<http.Response> _get(String path) async {
    final url = Uri.parse('$_baseUrl$path');
    return _client.get(url, headers: _authHeaders).timeout(_timeout);
  }

  Future<http.Response> _post(String path, {required Map<String, dynamic> data}) async {
    final url = Uri.parse('$_baseUrl$path');
    return _client
        .post(
          url,
          headers: {..._authHeaders, 'Content-Type': 'application/json; charset=UTF-8'},
          body: jsonEncode(data),
        )
        .timeout(_timeout);
  }

  void dispose() {
    _client.close();
  }
}

class CaptchaResult {
  final double s;
  final int r;
  final List<int> imageBytes;
  final String contentType;

  CaptchaResult({
    required this.s,
    required this.r,
    required this.imageBytes,
    required this.contentType,
  });
}

class ApiResponse {
  final int code;

  /// 服务端返回的失败原因。之前丢掉了它，界面上只能看到 code 猜不到原因。
  final String? msg;
  final dynamic data;
  final int? time;

  ApiResponse({required this.code, this.msg, this.data, this.time});

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    final m = json['msg'] ?? json['message'];
    return ApiResponse(
      code: json['code'] as int? ?? -1,
      msg: m is String && m.isNotEmpty ? m : null,
      data: json['data'],
      time: json['time'] as int?,
    );
  }

  bool get isSuccess => code == 0;

  /// 登录态失效（服务端用 -99，部分接口用 401/403）。
  bool get isSessionExpired => code == -99 || code == 401 || code == 403;

  Map<String, dynamic>? get dataMap => data is Map<String, dynamic> ? data : null;

  List<dynamic>? get dataList => data is List<dynamic> ? data : null;
}
