import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'legal_text.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/disclaimer_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const HuiLifeApp());
}

class HuiLifeApp extends StatelessWidget {
  const HuiLifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (_, settings, __) => MaterialApp(
          title: '饮咩野',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode,
          home: const SplashScreen(),
          routes: {
            '/login': (_) => const LoginScreen(),
            '/main': (_) => const MainShell(),
            '/disclaimer': (_) => const DisclaimerScreen(),
          },
        ),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final auth = context.read<AuthProvider>();
    try {
      await auth.tryAutoLogin().timeout(const Duration(seconds: 10));
    } catch (e) {
      // 读本地登录态失败或卡住：把原因显示出来，绝不无限转圈
      debugPrint('[splash] 启动检查失败: $e');
      if (mounted) setState(() => _startupError = '$e');
      return;
    }
    if (!mounted) return;
    // 首次启动必须先阅读并同意免责声明与用户须知。
    final prefs = await SharedPreferences.getInstance();
    final agreed = prefs.getBool(kDisclaimerAgreeKey) ?? false;
    if (!mounted) return;
    if (!agreed) {
      Navigator.of(context).pushReplacementNamed('/disclaimer');
      return;
    }
    Navigator.of(context).pushReplacementNamed(auth.isLoggedIn ? '/main' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.water_drop, size: 48, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text('饮咩野', style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            if (_startupError == null)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.primary),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '启动异常: $_startupError',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pushReplacementNamed('/login'),
                child: const Text('进入登录页'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
