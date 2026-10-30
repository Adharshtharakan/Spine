import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/wayfind.dart';
import '../../data/models/social.dart';
import '../../data/repositories/trip_repository.dart';
import '../../state/providers.dart';

final _documentsProvider = FutureProvider<List<GuidelineDocument>>(
  (ref) => ref.watch(guidelineRepositoryProvider).current(),
);

/// Every traveller must accept the current platform guidelines and driver
/// terms (with the three driver attestations) before creating, joining or
/// approving a trip. The server enforces the same rule; this screen only
/// collects the acceptance.
class GuidelinesScreen extends ConsumerStatefulWidget {
  const GuidelinesScreen({super.key});

  @override
  ConsumerState<GuidelinesScreen> createState() => _GuidelinesScreenState();
}

class _GuidelinesScreenState extends ConsumerState<GuidelinesScreen> {
  bool _readGuidelines = false;
  bool _licensed = false;
  bool _insured = false;
  bool _roadworthy = false;
  bool _busy = false;
  String? _error;

  bool get _ready => _readGuidelines && _licensed && _insured && _roadworthy;

  Future<void> _accept(List<GuidelineDocument> docs) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(guidelineRepositoryProvider);
      for (final d in docs) {
        await repo.accept(
          d,
          attestation: d.kind == 'driver_terms'
              ? {'licensed': _licensed, 'insured': _insured, 'roadworthy': _roadworthy}
              : const {},
        );
      }
      ref.invalidate(acceptedGuidelinesProvider);
      ref.invalidate(verifiedPartyProvider);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(_documentsProvider);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Before you drive')),
      body: docs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(padding: const EdgeInsets.all(16), children: [Note(friendlyError(e))]),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [
            Text('A few promises before the road', style: t.textTheme.headlineMedium),
            const SizedBox(height: 10),
            Text(
              'Everyone in a DriveSync convoy accepts the same rules. Read them once; we ask again only if they change.',
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            for (final d in list) ...[
              BoardHead(
                d.title,
                padding: const EdgeInsets.only(top: 20),
                trailing: Text('Version ${d.version}', style: t.textTheme.labelMedium),
              ),
              const SizedBox(height: 12),
              Text(d.body.trim(), style: t.textTheme.bodyMedium),
              const SizedBox(height: 8),
            ],
            BoardHead('Your promises', padding: const EdgeInsets.only(top: 24, bottom: 4)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _readGuidelines,
              onChanged: (v) => setState(() => _readGuidelines = v ?? false),
              title: const Text('I have read and accept the community guidelines'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _licensed,
              onChanged: (v) => setState(() => _licensed = v ?? false),
              title: const Text('I hold a valid licence for the vehicle I drive'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _insured,
              onChanged: (v) => setState(() => _insured = v ?? false),
              title: const Text('My vehicle is insured where I travel'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _roadworthy,
              onChanged: (v) => setState(() => _roadworthy = v ?? false),
              title: const Text('My vehicle is roadworthy for the planned route'),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Note(_error!)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _ready && !_busy ? () => _accept(list) : null,
              child: const Text('Accept and continue'),
            ),
          ],
        ),
      ),
    );
  }
}
