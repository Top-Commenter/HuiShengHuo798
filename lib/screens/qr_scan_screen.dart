import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

/// 扫码添加设备：从二维码中解析设备 ID，调用设备二维码接口完成绑定。
/// 绑定成功（或设备已存在）时以 `true` 返回上一页，由调用方刷新设备列表。
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _binding = false;
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 从二维码内容中提取设备 ID：纯数字、URL 的 id/did 参数、或任意位置的数字串。
  String? _extractDeviceId(String code) {
    if (RegExp(r'^\d{10,20}$').hasMatch(code)) return code;

    final uri = Uri.tryParse(code);
    if (uri != null) {
      final id = uri.queryParameters['id'];
      if (id != null && id.isNotEmpty) return id;
      final did = uri.queryParameters['did'];
      if (did != null && did.isNotEmpty) return did;
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final last = segments.last;
        if (RegExp(r'^\d{10,20}$').hasMatch(last)) return last;
      }
    }
    return RegExp(r'(\d{10,20})').firstMatch(code)?.group(1);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_binding || _done) return;
    final barcodes = capture.barcodes;
    final code = barcodes.isEmpty ? null : barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    final did = _extractDeviceId(code);
    if (did == null || did.isEmpty) return;

    setState(() => _binding = true);

    final api = context.read<AuthProvider>().api;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    try {
      // 先确认二维码对应真实设备，再调用收藏接口把它加入「我的设备」。
      // 只查 qr/use 不会改变设备列表，这是之前“扫码后列表没变化”的原因。
      final check = await api.getDeviceQr(did);
      if (!mounted) return;
      if (!check.isSuccess) {
        setState(() => _binding = false);
        messenger.showSnackBar(SnackBar(
            content: Text(check.msg ?? '二维码无效或设备不存在 (code: ${check.code})')));
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) setState(() => _done = false);
        return;
      }

      final fav = await api.favoriteDevice(did);
      if (!mounted) return;
      setState(() => _done = true);

      if (fav.isSuccess) {
        messenger.showSnackBar(
          const SnackBar(content: Text('设备添加成功'), backgroundColor: Colors.green),
        );
        await Future.delayed(const Duration(milliseconds: 600));
        nav.pop(true);
      } else if (fav.code == 400 || fav.code == 409) {
        messenger.showSnackBar(
          const SnackBar(content: Text('设备已在列表中'), backgroundColor: Colors.orange),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        nav.pop(true);
      } else {
        setState(() => _binding = false);
        messenger.showSnackBar(SnackBar(
            content: Text(fav.msg ?? '添加失败 (code: ${fav.code})，请重试')));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _binding = false);
      messenger.showSnackBar(const SnackBar(content: Text('网络异常，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码添加设备'),
        actions: [
          IconButton(
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              await _ctrl.toggleTorch();
              setState(() => _torch = !_torch);
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: _done ? Colors.green : Colors.blue, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          if (_binding)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('正在绑定设备...', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Text(
              '将设备二维码对准框内',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
