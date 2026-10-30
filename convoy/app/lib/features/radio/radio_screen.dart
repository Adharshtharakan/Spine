import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
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
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    return LargeTitleScaffold(
      title: 'Long-range radio',
      subtitle: 'Stay linked with no cell signal',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Phones alone only reach cars a few hundred metres away. A small LoRa radio running Meshtastic '
                '(Heltec V3, RAK WisBlock or LilyGO T-Echo, about \$25 to \$40) reaches 2 to 10 km between cars, '
                'and every radio relays for the others, so the link stretches with the convoy.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 10),
              Text(
                'Set each radio to the same region and the default channel in the Meshtastic app once. DriveSync '
                'encrypts everything it sends with your trip\'s key, so other radio users cannot read or fake it.',
                style: t.bodySmall,
              ),
            ]),
          ),
        ),
        if (_paired != null)
          Section(title: 'Paired', children: [
            Tile(
              leading: TileIcon(Icons.settings_input_antenna, color: c.good),
              title: 'Paired radio',
              subtitle: _paired!,
              trailing: TextButton(onPressed: () => _pair(null), child: const Text('Remove')),
            ),
          ]),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _scanning ? null : _scan,
          icon: _scanning
              ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.faint))
              : const Icon(Icons.bluetooth_searching_rounded),
          label: Text(_scanning ? 'Searching' : 'Find radios nearby'),
        ),
        if (_found.isNotEmpty)
          Section(title: 'Found nearby', children: [
            for (final r in _found)
              Tile(
                leading: TileIcon(Icons.router_rounded, color: c.accent),
                title: r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.remoteId.str,
                subtitle: 'Signal ${r.rssi} dBm',
                trailing: r.device.remoteId.str == _paired
                    ? Icon(Icons.check_circle_rounded, color: c.good)
                    : OutlinedButton(onPressed: () => _pair(r.device.remoteId.str), child: const Text('Pair')),
              ),
          ]),
        if (!_scanning && _found.isEmpty && _sub != null)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: InfoBanner('No radios found. Check the radio is on and Bluetooth is enabled, then search again.',
                icon: Icons.bluetooth_disabled_rounded),
          ),
      ],
    );
  }
}
