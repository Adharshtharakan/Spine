import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(id == null ? 'Radio removed' : 'Radio paired — it will connect when you open a trip'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Convoy radio')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Stay linked with no cell signal', style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Phones alone only reach cars a few hundred metres away. A small LoRa radio running Meshtastic '
          '(Heltec V3, RAK WisBlock, LilyGO T-Echo — about \$25–40) reaches 2–10 km between cars on the road, '
          'and every radio relays for the others, so the link stretches with the convoy.\n\n'
          'Set each radio to the same region and the default channel in the Meshtastic app once. Convoy '
          'encrypts everything it sends with your trip\'s key, so other radio users cannot read or fake it.',
        ),
        const SizedBox(height: 16),
        if (_paired != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_input_antenna, color: Colors.green),
              title: const Text('Paired radio'),
              subtitle: Text(_paired!),
              trailing: TextButton(onPressed: () => _pair(null), child: const Text('Remove')),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _scanning ? null : _scan,
          icon: const Icon(Icons.bluetooth_searching),
          label: Text(_scanning ? 'Searching…' : 'Find radios nearby'),
        ),
        for (final r in _found)
          ListTile(
            leading: const Icon(Icons.router),
            title: Text(r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.remoteId.str),
            subtitle: Text('Signal ${r.rssi} dBm'),
            trailing: r.device.remoteId.str == _paired
                ? const Icon(Icons.check)
                : OutlinedButton(onPressed: () => _pair(r.device.remoteId.str), child: const Text('Pair')),
          ),
      ]),
    );
  }
}
