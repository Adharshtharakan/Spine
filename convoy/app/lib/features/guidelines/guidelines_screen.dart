import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        await repo.accept(d,
            attestation: d.kind == 'driver_terms'
                ? {'licensed': _licensed, 'insured': _insured, 'roadworthy': _roadworthy}
                : const {});
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
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (list) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final d in list) ...[
              Text('${d.title} (v${d.version})', style: t.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(d.body.trim(), style: t.textTheme.bodyMedium),
              const SizedBox(height: 20),
            ],
            CheckboxListTile(
              value: _readGuidelines,
              onChanged: (v) => setState(() => _readGuidelines = v ?? false),
              title: const Text('I have read and accept the community guidelines'),
            ),
            const Divider(),
            CheckboxListTile(
              value: _licensed,
              onChanged: (v) => setState(() => _licensed = v ?? false),
              title: const Text('I hold a valid licence for the vehicle I drive'),
            ),
            CheckboxListTile(
              value: _insured,
              onChanged: (v) => setState(() => _insured = v ?? false),
              title: const Text('My vehicle is insured where I travel'),
            ),
            CheckboxListTile(
              value: _roadworthy,
              onChanged: (v) => setState(() => _roadworthy = v ?? false),
              title: const Text('My vehicle is roadworthy for the planned route'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
              ),
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
