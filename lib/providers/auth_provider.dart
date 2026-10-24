import 'package:flutter/material.dart';
import '../api/api_client.dart';

class AuthProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient();
  bool _loading = false;
  bool _checking = true;
  String? _error;
  CaptchaResult? _captcha;

  ApiClient get api => _api;
  bool get loading => _loading;
  bool get checking => _checking;
  String? get error => _error;
  CaptchaResult? get captcha => _captcha;
  bool get isLoggedIn => _api.isLoggedIn;

  /// 读取本地登录态。异常向上抛给启动页展示，避免无限转圈。
  Future<void> tryAutoLogin() async {
    _checking = true;
    notifyListeners();
    try {
      await _api.restoreToken();
    } catch (e) {
      debugPrint('[auth] restoreToken 失败: $e');
      rethrow;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _api.clearToken();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<bool> fetchCaptcha() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _captcha = await _api.getCaptcha();
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[auth] getCaptcha 失败: $e');
      _error = '获取验证码失败: $e';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendSmsCode(String phone, String captchaCode) async {
    if (_captcha == null) {
      _error = '图片验证码已失效，请重新获取';
      notifyListeners();
      return false;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final resp = await _api.sendSmsCode(
        phone: phone,
        captchaCode: captchaCode,
        captchaS: _captcha!.s,
      );
      _loading = false;
      if (resp.isSuccess) {
        notifyListeners();
        return true;
      }
      _error = '发送验证码失败 (code: ${resp.code})';
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('[auth] sendSmsCode 失败: $e');
      _error = '发送验证码失败: $e';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String phone, String smsCode) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final resp = await _api.login(phone: phone, smsCode: smsCode);
      _loading = false;
      if (resp.isSuccess) {
        notifyListeners();
        return true;
      }
      _error = '登录失败 (code: ${resp.code})';
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('[auth] login 失败: $e');
      _error = '登录失败: $e';
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }
}
