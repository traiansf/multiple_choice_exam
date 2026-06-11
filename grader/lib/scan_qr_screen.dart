/// QR scanning screen (mobile_scanner). Thin camera plumbing: every decoded
/// barcode is handed to GraderSession.setQr, which owns all validation.
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'session.dart';

class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key, required this.session});

  final GraderSession session;

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  final MobileScannerController _controller = MobileScannerController();
  String? _rejection;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      if (widget.session.setQr(raw)) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _rejection = widget.session.lastError);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan the sheet QR code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: _controller.toggleTorch,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _rejection ??
                    'Point the camera at the QR code in the top-right corner'
                        ' of the answer sheet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _rejection == null ? Colors.white : Colors.redAccent,
                  fontSize: 14,
                  shadows: const [Shadow(blurRadius: 4)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
