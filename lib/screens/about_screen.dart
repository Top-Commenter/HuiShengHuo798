import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';
import '../app_info.dart';

/// 关于页：版本号、仓库/参考项目地址、可折叠的历史更新内容。
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _LogEntry {
  final String version;
  final String date;
  final List<String> lines;

  const _LogEntry(this.version, this.date, this.lines);
}

class _AboutScreenState extends State<AboutScreen> {
  List<_LogEntry>? _logs;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  /// 直接解析打包进 assets 的 docs/CHANGELOG.md，保证文档与 App 内展示同源。
  Future<void> _loadLogs() async {
    try {
      final raw = await rootBundle.loadString('docs/CHANGELOG.md');
      if (!mounted) return;
      setState(() => _logs = _parse(raw));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  List<_LogEntry> _parse(String raw) {
    final entries = <_LogEntry>[];
    String? version;
    String date = '';
    var lines = <String>[];
    void flush() {
      if (version != null) entries.add(_LogEntry(version!, date, List.of(lines)));
    }

    for (final line in raw.split('\n')) {
      final t = line.trimRight();
      if (t.startsWith('## ')) {
        flush();
        final title = t.substring(3).trim();
        final parts = title.split('·');
        version = parts.first.trim();
        date = parts.length > 1 ? parts.sublist(1).join('·').trim() : '';
        lines = [];
      } else if (version != null && t.trim().isNotEmpty && !t.startsWith('# ')) {
        lines.add(t.trim());
      }
    }
    flush();
    return entries;
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
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
                  onTap: () => _open(kRepoUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.link, color: theme.colorScheme.primary),
                  title: const Text('项目参考'),
                  subtitle: const Text(kReferenceUrl),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _open(kReferenceUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('历史版本更新', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (_failed)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('更新记录加载失败', style: TextStyle(fontSize: 13)),
                  )
                else if (_logs == null)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  for (var i = 0; i < _logs!.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      initiallyExpanded: i == 0,
                      title: Text(_logs![i].version,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: _logs![i].date.isEmpty
                          ? null
                          : Text(_logs![i].date, style: const TextStyle(fontSize: 12)),
                      children: _logLines(theme, _logs![i].lines),
                    ),
                  ],
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

  List<Widget> _logLines(ThemeData theme, List<String> lines) {
    final widgets = <Widget>[];
    for (final line in lines) {
      if (line.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(line.substring(4).trim(),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
        ));
      } else if (line.startsWith('- ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('· ', style: TextStyle(color: theme.colorScheme.primary, fontSize: 13)),
              Expanded(
                child: Text(line.substring(2).replaceAll('`', '').trim(),
                    style: TextStyle(fontSize: 13, height: 1.5, color: theme.colorScheme.onSurface)),
              ),
            ],
          ),
        ));
      }
    }
    return widgets;
  }
}
