import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../legal_text.dart';
import '../providers/auth_provider.dart';

/// 免责声明与用户须知。
/// [forceAgree] 为 true 时表示首次启动的强制确认流程（勾选后才能继续）；
/// 为 false 时仅作只读回看（从「关于」页进入）。
class DisclaimerScreen extends StatefulWidget {
  final bool forceAgree;

  const DisclaimerScreen({super.key, this.forceAgree = true});

  @override
  State<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  bool _agreed = false;
  bool _submitting = false;

  Future<void> _accept() async {
    setState(() => _submitting = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kDisclaimerAgreeKey, true);
    if (!mounted) return;
    final loggedIn = context.read<AuthProvider>().isLoggedIn;
    Navigator.of(context).pushReplacementNamed(loggedIn ? '/main' : '/login');
  }

  Future<void> _decline() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未同意声明'),
        content: const Text('不同意免责声明与用户须知将无法使用本应用，确定退出吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('再看看')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('退出应用', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok == true) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(kDisclaimerTitle),
        automaticallyImplyLeading: !widget.forceAgree,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '请在继续使用前仔细阅读以下全部内容。本应用为个人学习项目，'
                    '与任何官方服务无关联，使用产生的费用与后果由你自行承担。',
                    style: TextStyle(fontSize: 13, height: 1.6, color: theme.colorScheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(height: 8),
                for (final section in kDisclaimerSections) ...[
                  const SizedBox(height: 16),
                  Text(section.title,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  for (final item in section.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('· ', style: TextStyle(color: theme.colorScheme.primary, fontSize: 13)),
                          Expanded(
                            child: Text(item,
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1.6,
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (widget.forceAgree)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      value: _agreed,
                      onChanged: (v) => setState(() => _agreed = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('我已阅读并同意上述免责声明与用户须知',
                          style: TextStyle(fontSize: 13)),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _submitting ? null : _decline,
                          child: const Text('不同意'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: (_agreed && !_submitting) ? _accept : null,
                            child: const Text('同意并继续'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
