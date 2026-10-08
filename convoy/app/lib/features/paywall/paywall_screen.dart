import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/theme/theme.dart';
import '../../data/models/social.dart';
import '../../services/billing/billing_service.dart';
import '../../services/edge/edge_client.dart';
import '../../state/providers.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  BillingService? _billing;
  List<ProductDetails> _products = const [];
  bool _loading = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    _billing = BillingService(EdgeClient(ref.read(supabaseProvider)), userId: user.id)..listen();
    _billing!.events.listen((e) {
      if (!mounted) return;
      setState(() => _status = switch (e.kind) {
            'pending' => 'Waiting for the store…',
            'cancelled' => null,
            'premium' => 'Premium is active. Thank you!',
            _ => e.message,
          });
      if (e.kind == 'premium') ref.invalidate(entitlementProvider);
    });
    _billing!.products().then((p) {
      if (mounted) {
        setState(() {
          _products = p;
          _loading = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _billing?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ent = ref.watch(entitlementProvider).value ?? Entitlement.free;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Convoy Premium')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Icon(Icons.workspace_premium, size: 56, color: ConvoyTheme.lead),
        const SizedBox(height: 12),
        Text(ent.isPremium ? 'You are on Premium' : 'Bigger convoys, stronger offline tools',
            style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        _row(Icons.directions_car, 'Vehicles per convoy', '${Entitlement.freeVehicleCap}', '${Entitlement.premiumVehicleCap}'),
        _row(Icons.map, 'Offline map detail', 'Overview (z12)', 'Street level (z14)'),
        _row(Icons.layers, 'Offline trips stored', '${Entitlement.freeOfflineRegions}', 'Unlimited'),
        _row(Icons.hub, 'Mesh relay through other cars', 'Direct only', 'Multi-hop'),
        _row(Icons.forum, 'Text + push-to-talk', 'Included', 'Included'),
        const SizedBox(height: 24),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (!_loading && _products.isEmpty)
          const Text('Subscriptions are not available on this device right now.', textAlign: TextAlign.center),
        for (final p in _products)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton(
              onPressed: ent.isPremium ? null : () => _billing?.buy(p),
              child: Text('${p.title.replaceAll(RegExp(r'\s*\(.*\)$'), '')} — ${p.price}'),
            ),
          ),
        TextButton(onPressed: () => _billing?.restore(), child: const Text('Restore purchases')),
        if (_status != null) Text(_status!, textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _row(IconData icon, String label, String free, String premium) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text('Free: $free'),
        trailing: Text(premium, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
}
