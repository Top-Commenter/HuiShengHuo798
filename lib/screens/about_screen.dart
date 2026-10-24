import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_info.dart';

/// 关于页：版本号、仓库/参考项目地址与免责声明。
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法打开：$url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.water_drop, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(kAppName,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(kAppIntroName,
                            style: TextStyle(
                                fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text('版本 $kAppVersion',
                            style: TextStyle(
                                fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.code, color: theme.colorScheme.primary),
                  title: const Text('仓库源码'),
                  subtitle: const Text(kRepoUrl),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _open(context, kRepoUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.link, color: theme.colorScheme.primary),
                  title: const Text('项目参考'),
                  subtitle: const Text(kReferenceUrl),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _open(context, kReferenceUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '免责声明：本项目为个人学习与技术研究用途，仅供学习交流，不用于任何商业用途。'
              '项目与相关服务提供方无任何关联，使用产生的任何费用与后果由使用者自行承担。',
              style: TextStyle(fontSize: 12, height: 1.6, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
