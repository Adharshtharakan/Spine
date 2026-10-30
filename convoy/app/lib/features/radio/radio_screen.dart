import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/wayfind.dart';
import '../../services/mesh/meshtastic_transport.dart';

/// Pair the car's LoRa radio. One-time setup: the app reconnects to it
/// automatically whenever a trip is open.
class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  String? _paired;
  List<ScanResult> _found = const [];
  bool _scanning = false;
  StreamSubscription<List<ScanResult>>? _sub;

  @override
  void initState() {
    super.initState();
    MeshtasticTransport.savedDevice().then((id) => mounted ? setState(() => _paired = id) : null);
  }

  @override
  void dispose() {
    _sub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _scan() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
    setState(() {
      _scanning = true;
      _found = const [];
    });
    await _sub?.cancel();
    _sub = scanForRadios().listen((r) {
      if (mounted) setState(() => _found = r);
    });
    await Future<void>.delayed(const Duration(seconds: 15));
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _pair(String? id) async {
    await MeshtasticTransport.saveDevice(id);
    setState(() => _paired = id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(id == null ? 'Radio removed' : 'Radio paired. It connects when you open a trip.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Long-range radio')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          Text('Stay linked with no cell signal', style: t.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'Phones alone only reach cars a few hundred metres away. A small LoRa radio running Meshtastic '
            '(Heltec V3, RAK WisBlock or LilyGO T-Echo, about \$25 to \$40) reaches 2 to 10 km between cars on the road, '
            'and every radio relays for the others, so the link stretches with the convoy.',
            style: t.bodyLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'Set each radio to the same region and the default channel in the Meshtastic app once. DriveSync '
            'encrypts everything it sends with your trip\'s key, so other radio users cannot read or fake it.',
            style: t.bodyMedium?.copyWith(color: w.muted),
          ),
          const SizedBox(height: 24),
          if (_paired != null)
            Plate(
              child: Row(
                children: [
                  const Icon(Icons.settings_input_antenna),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Paired radio', style: t.labelSmall?.copyWith(color: w.plateMuted)),
                        Text(
                          _paired!,
                          style: t.titleSmall?.copyWith(color: w.figure, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: w.onPlate),
                    onPressed: () => _pair(null),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.bluetooth_searching),
            label: Text(_scanning ? 'Searching for 15 s' : 'Find radios nearby'),
          ),
          if (_found.isNotEmpty)
            BoardHead(
              'Found',
              padding: const EdgeInsets.only(top: 28),
              trailing: Text('${_found.length}', style: t.titleSmall),
            ),
          if (!_scanning && _found.isEmpty && _sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'No radios found. Check the radio is on and Bluetooth is enabled, then search again.',
                style: t.bodyMedium?.copyWith(color: w.muted),
              ),
            ),
          for (final r in _found)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: w.rule, width: Rules.hair),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.remoteId.str,
                          style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text('Signal ${r.rssi} dBm', style: t.bodySmall),
                      ],
                    ),
                  ),
                  if (r.device.remoteId.str == _paired)
                    Text('Paired', style: t.labelLarge?.copyWith(color: w.live))
                  else
                    OutlinedButton(onPressed: () => _pair(r.device.remoteId.str), child: const Text('Pair')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
