// ui/qr_scan_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// QRコードをスキャンしてコード文字列を返す画面。
/// - 成功時: Navigator.pop(context, scannedCode)
/// - キャンセル時: Navigator.pop(context) (null)
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    torchEnabled: false,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  bool _torchOn = false; // 端末の状態と完全同期ではないが、UI上の状態として使用

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes.first.rawValue ?? '';
    if (raw.isEmpty) return;

    // 受理は一度だけ
    _handled = true;

    // URL形式(teamalarm://invite?code=XXXX or https://.../invite?code=XXXX) も許容
    final code = _extractCode(raw);
    Navigator.of(context).pop(code ?? raw);
  }

  String? _extractCode(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null) {
      final q = uri.queryParameters['code'];
      if (q != null && q.isNotEmpty) return q;
    }
    // 純粋なコード(英数6～32桁を想定)ならそのまま返す
    final reg = RegExp(r'^[A-Za-z0-9]{6,32}$');
    if (reg.hasMatch(raw)) return raw;
    return null;
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) {
        setState(() {
          _torchOn = !_torchOn; // 簡易トグル（APIの戻り値に依存しない）
        });
      }
    } catch (_) {
      // 端末未対応などの例外は無視（必要ならSnackBar表示も可能）
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QRコードをスキャン'),
        actions: [
          IconButton(
            tooltip: 'ライト',
            onPressed: _toggleTorch,
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
          IconButton(
            tooltip: 'カメラ切替',
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,

                
              ),
            ),
          ),
        ],
      ),
    );
  }
}