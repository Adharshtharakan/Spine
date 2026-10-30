import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/wayfind.dart';
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
    final w = context.wf;
    final t = Theme.of(context).textTheme;
    // The plan comparison as a fare table: one row per feature, free and Premium side by side.
    final rows = [
      ('Vehicles per convoy', '${Entitlement.freeVehicleCap}', '${Entitlement.premiumVehicleCap}'),
      ('Offline map detail', 'Overview, z12', 'Street level, z14'),
      ('Offline trips stored', '${Entitlement.freeOfflineRegions}', 'Unlimited'),
      ('Mesh relay through other cars', 'Direct only', 'Multi-hop'),
      ('Text and push-to-talk', 'Included', 'Included'),
    ];
    TableRow row(List<Widget> cells, {Color? color}) => TableRow(
      decoration: BoxDecoration(
        color: color,
        border: Border(
          bottom: BorderSide(color: w.rule, width: Rules.hair),
        ),
      ),
      children: [for (final c in cells) Padding(padding: const EdgeInsets.fromLTRB(0, 12, 12, 12), child: c)],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('DriveSync Premium')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          Text(
            ent.isPremium ? 'You are on Premium.' : 'Bigger convoys and stronger offline tools.',
            style: t.headlineMedium,
          ),
          const SizedBox(height: 24),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: w.ink, width: Rules.bar),
              ),
            ),
            child: Table(
              columnWidths: const {0: FlexColumnWidth(1.5), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.1)},
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                row([
                  const SizedBox.shrink(),
                  Text('Free', style: t.labelMedium),
                  Text(
                    'Premium',
                    style: t.labelMedium?.copyWith(color: w.ink, fontWeight: FontWeight.w800),
                  ),
                ]),
                for (final (label, free, premium) in rows)
                  row([
                    Text(label, style: t.bodyMedium),
                    Text(free, style: t.bodyMedium?.copyWith(color: w.muted)),
                    Text(premium, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ]),
              ],
            ),
          ),
          const SizedBox(height: 28),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && _products.isEmpty)
            const Note('Subscriptions are not available on this device right now.', icon: Icons.storefront_outlined),
          for (final p in _products)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FilledButton(
                onPressed: ent.isPremium ? null : () => _billing?.buy(p),
                child: Row(
                  children: [
                    Expanded(child: Text(p.title.replaceAll(RegExp(r'\s*\(.*\)$'), ''))),
                    Text(p.price),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => _billing?.restore(), child: const Text('Restore purchases')),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status!, style: t.bodyMedium),
            ),
        ],
      ),
    );
  }
}
