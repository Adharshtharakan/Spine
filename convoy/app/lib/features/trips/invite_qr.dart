import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/trip.dart';
import '../../services/invite/invite_links.dart';

/// The invite as a QR code, for the meeting point: others scan it from
/// "Join" on their home screen (or with the camera app, when it's a link).
Future<void> showInviteQr(BuildContext context, Trip trip) => showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.tones;
        final t = Theme.of(ctx).textTheme;
        final data = InviteLinks.link(trip.inviteCode) ?? trip.inviteCode;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Scan to join', style: t.headlineSmall),
              const SizedBox(height: 4),
              Text(trip.title, style: t.bodyMedium?.copyWith(color: c.sub)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Radii.card)),
                child: QrImageView(
                  data: data,
                  size: 220,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF111114)),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF111114)),
                ),
              ),
              const SizedBox(height: 16),
              Text(trip.inviteCode, style: t.headlineMedium?.copyWith(letterSpacing: 4, color: c.accent)),
            ]),
          ),
        );
      },
    );

/// Scans an invite QR and returns its code.
class InviteScanner extends StatefulWidget {
  const InviteScanner({super.key});

  @override
  State<InviteScanner> createState() => _InviteScannerState();
}

class _InviteScannerState extends State<InviteScanner> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan invite', style: TextStyle(color: Colors.white)),
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final code = InviteLinks.codeFrom(b.rawValue ?? '');
              if (code != null) {
                _done = true;
                Navigator.pop(context, code);
                return;
              }
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('The camera is not available. Type the code instead.',
                  textAlign: TextAlign.center, style: t.bodyLarge?.copyWith(color: Colors.white)),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(32),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Text('Point the camera at the QR code on the organiser\'s phone.',
              textAlign: TextAlign.center, style: t.bodyLarge?.copyWith(color: Colors.white)),
        ),
      ]),
    );
  }
}
