import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../i18n/strings.g.dart';
import '../../services/pleya_share/pleya_share_uri.dart';

/// Camera scanner for a Pleya Share host QR. Pops with the parsed
/// [PleyaSharePairUri] on the first valid pair link, or null if cancelled.
/// Non-pair QR codes are ignored so the camera keeps scanning.
class PleyaShareScanScreen extends StatefulWidget {
  const PleyaShareScanScreen({super.key});

  @override
  State<PleyaShareScanScreen> createState() => _PleyaShareScanScreenState();
}

class _PleyaShareScanScreenState extends State<PleyaShareScanScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final parsed = PleyaSharePairUri.tryParse(raw);
      if (parsed != null) {
        _handled = true;
        Navigator.of(context).pop(parsed);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.pleyaShare.scanQr)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(t.pleyaShare.scanQrHint, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
