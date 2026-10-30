import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
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
    final c = context.tones;
    final t = Theme.of(context).textTheme;
    final list = docs.value ?? const <GuidelineDocument>[];
    Widget check(String text, bool value, ValueChanged<bool> set) => InkWell(
          onTap: () => set(!value),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 20, 6),
            child: Row(children: [
              Checkbox(value: value, onChanged: (v) => set(v ?? false)),
              const SizedBox(width: 4),
              Expanded(child: Text(text, style: t.bodyLarge)),
            ]),
          ),
        );
    return LargeTitleScaffold(
      title: 'Before you drive',
      subtitle: 'Read once. We ask again only if the rules change.',
      bottomBar: docs.hasValue
          ? SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: FilledButton(
                  onPressed: _ready && !_busy ? () => _accept(list) : null,
                  child: const Text('Accept and continue'),
                ),
              ),
            )
          : null,
      children: [
        ...docs.when(
          loading: () => const [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
          error: (e, _) => [InfoBanner(friendlyError(e), tone: Tone.bad, icon: Icons.error_rounded)],
          data: (list) => [
            for (final (i, d) in list.indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        TileIcon(d.kind == 'driver_terms' ? Icons.badge_rounded : Icons.handshake_rounded,
                            color: d.kind == 'driver_terms' ? c.accent : c.good),
                        const SizedBox(width: 14),
                        Expanded(child: Text(d.title, style: t.titleMedium)),
                        Pill('v${d.version}'),
                      ]),
                      const SizedBox(height: 14),
                      Text(d.body.trim(), style: t.bodyMedium?.copyWith(color: c.sub)),
                    ]),
                  ),
                ),
              ),
            Section(title: 'Your promises', children: [
              check('I have read and accept the community guidelines', _readGuidelines,
                  (v) => setState(() => _readGuidelines = v)),
              check('I hold a valid licence for the vehicle I drive', _licensed, (v) => setState(() => _licensed = v)),
              check('My vehicle is insured where I travel', _insured, (v) => setState(() => _insured = v)),
              check('My vehicle is roadworthy for the planned route', _roadworthy,
                  (v) => setState(() => _roadworthy = v)),
            ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: InfoBanner(_error!, tone: Tone.bad, icon: Icons.error_rounded),
              ),
          ],
        ),
      ],
    );
  }
}
