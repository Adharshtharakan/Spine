import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
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
      setState(
        () => _status = switch (e.kind) {
          'pending' => 'Waiting for the store',
          'cancelled' => null,
          'premium' => 'Premium is active. Thank you!',
          _ => e.message,
        },
      );
      if (e.kind == 'premium') ref.invalidate(entitlementProvider);
    });
    _billing!
        .products()
        .then((p) {
          if (mounted) {
            setState(() {
              _products = p;
              _loading = false;
            });
          }
        })
        .catchError((_) {
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
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final rows = [
      (Icons.directions_car_rounded, c.accent, 'Vehicles per convoy', '${Entitlement.freeVehicleCap}', '${Entitlement.premiumVehicleCap}'),
      (Icons.map_rounded, c.good, 'Offline map detail', 'Overview', 'Street level'),
      (Icons.layers_rounded, c.warn, 'Offline trips stored', '${Entitlement.freeOfflineRegions}', 'Unlimited'),
      (Icons.hub_rounded, Color(Tones.vehicleColours[4]), 'Relay through other cars', 'Direct only', 'Multi-hop'),
      (Icons.forum_rounded, Color(Tones.vehicleColours[5]), 'Chat and push-to-talk', 'Included', 'Included'),
    ];
    return LargeTitleScaffold(
      title: 'Premium',
      subtitle: ent.isPremium ? 'You are on Premium. Thank you!' : 'Bigger convoys and stronger offline tools',
      children: [
        Section(top: 0, title: 'Free compared with Premium', children: [
          for (final (icon, color, label, free, premium) in rows)
            Tile(
              leading: TileIcon(icon, color: color),
              title: label,
              subtitle: 'Free: $free',
              trailing: Text(premium, style: t.titleSmall?.copyWith(color: c.accent)),
            ),
        ]),
        const SizedBox(height: 24),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (!_loading && _products.isEmpty)
          const InfoBanner('Subscriptions are not available on this device right now.', icon: Icons.storefront_rounded),
        for (final p in _products)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 58)),
              onPressed: ent.isPremium ? null : () => _billing?.buy(p),
              child: Row(children: [
                Expanded(child: Text(p.title.replaceAll(RegExp(r'\s*\(.*\)$'), ''))),
                Text(p.price),
              ]),
            ),
          ),
        Center(child: TextButton(onPressed: () => _billing?.restore(), child: const Text('Restore purchases'))),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, textAlign: TextAlign.center, style: t.bodyMedium),
          ),
      ],
    );
  }
}
