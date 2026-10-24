import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _captchaCtrl = TextEditingController();
  final _smsCtrl = TextEditingController();
  int _step = 0;
  bool _sendingSms = false;

  /// 上一页带过来的提示（例如登录态过期）
  String? _notice;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final p = await context.read<AuthProvider>().api.loadLastPhone();
    if (!mounted || p == null) return;
    setState(() => _phoneCtrl.text = p);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String && arg.isNotEmpty) _notice ??= arg;
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _captchaCtrl.dispose();
    _smsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(Icons.water_drop, size: 44, color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 20),
                Center(child: Text('惠生活798', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
                const SizedBox(height: 4),
                Center(child: Text('自定义客户端 · 仅业务数据', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                if (_notice != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_notice!,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 36),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  decoration: const InputDecoration(
                    labelText: '手机号',
                    prefixIcon: Icon(Icons.phone_android),
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                if (_step >= 1) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _captchaCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '图片验证码',
                            prefixIcon: Icon(Icons.shield_outlined),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: auth.loading ? null : () => auth.fetchCaptcha(),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: auth.captcha != null
                              // 服务端验证码图固定 120×40，必须按原尺寸完整显示。
                              // 之前写 104×48 + BoxFit.cover 会把图放大后左右各裁掉
                              // 约 17px，把第一个字符裁掉，导致用户永远读不对验证码。
                              ? Image.memory(
                                  Uint8List.fromList(auth.captcha!.imageBytes),
                                  width: 120,
                                  height: 40,
                                  fit: BoxFit.contain,
                                )
                              : Container(
                                  width: 120,
                                  height: 40,
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  child: auth.loading
                                      ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                                      : const Icon(Icons.refresh, size: 20),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                if (_step >= 2) ...[
                  TextField(
                    controller: _smsCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '短信验证码',
                      prefixIcon: Icon(Icons.sms_outlined),
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                ],
                if (auth.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(auth.error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                  ),
                const SizedBox(height: 6),
                FilledButton(
                  onPressed: _next(auth),
                  child: auth.loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_buttonText()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buttonText() => switch (_step) {
        0 => '获取图片验证码',
        1 => '发送短信',
        _ => '登录',
      };

  void Function()? _next(AuthProvider auth) {
    if (auth.loading) return null;
    if (_step == 0) {
      if (_phoneCtrl.text.length != 11) return null;
      return () async {
        final ok = await auth.fetchCaptcha();
        if (ok && mounted) setState(() => _step = 1);
      };
    }
    if (_step == 1) {
      if (_captchaCtrl.text.length < 4 || _sendingSms) return null;
      return () async {
        setState(() => _sendingSms = true);
        final ok = await auth.sendSmsCode(_phoneCtrl.text, _captchaCtrl.text);
        if (mounted) {
          setState(() {
            _sendingSms = false;
            if (ok) _step = 2;
          });
        }
      };
    }
    if (_smsCtrl.text.length < 4) return null;
    return () async {
      final ok = await auth.login(_phoneCtrl.text, _smsCtrl.text);
      if (ok && mounted) {
        Navigator.of(context).pushReplacementNamed('/main');
      }
    };
  }
}
