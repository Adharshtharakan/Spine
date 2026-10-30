import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
import '../../state/trip_session.dart';

/// What each part of the link is doing right now: the live connection, the
/// fallback sync and GPS. Opened by tapping the trip title on the map; the
/// text can be copied to send to whoever is helping.
Future<void> showConnectionDetails(BuildContext context, TripSession s) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scroll) => ListenableBuilder(
          listenable: s,
          builder: (ctx, _) {
            final c = ctx.tones;
            final t = Theme.of(ctx).textTheme;
            final now = DateTime.now();
            String ago(DateTime? at) {
              if (at == null) return 'never';
              final d = now.difference(at);
              return d.inSeconds < 60 ? '${d.inSeconds} s ago' : '${d.inMinutes} min ago';
            }

            final ch = s.channel;
            final g = s.gps;
            final last = g?.last;
            final rows = <(IconData, Color, String, String)>[
              (
                Icons.bolt_rounded,
                ch?.isLive == true ? c.good : c.warn,
                'Live connection',
                ch == null
                    ? 'Not started (not a member of this trip?)'
                    : '${ch.currentStatus.name}, socket ${ch.socketState}${ch.lastError == null ? '' : '\n${ch.lastError}'}',
              ),
              (
                Icons.sync_rounded,
                s.lastSyncOk != null && now.difference(s.lastSyncOk!) < const Duration(minutes: 1) ? c.good : c.faint,
                'Backup sync (every 15 s)',
                'Last OK ${ago(s.lastSyncOk)}${s.syncError == null ? '' : '\n${s.syncError}'}',
              ),
              (
                Icons.location_on_rounded,
                (g?.fixes ?? 0) > 0 ? c.good : c.bad,
                'GPS',
                g == null
                    ? 'Not started'
                    : 'Permission: ${g.permission?.name ?? 'asking…'}\n'
                        'Fixes: ${g.fixes}${last == null ? '' : ', last ${ago(last.timestamp.toLocal())}, ±${last.accuracyM.round()} m'}'
                        '${g.parked ? '\nParked: saving battery' : ''}'
                        '${g.lastError == null ? '' : '\nError: ${g.lastError}'}',
              ),
              (
                Icons.mic_rounded,
                (s.ptt?.connectedPeers.value ?? 0) > 0 ? c.good : c.warn,
                'Voice (push-to-talk)',
                s.ptt == null
                    ? 'Not started'
                    : '${s.ptt!.connectedPeers.value} of ${(s.online.length - 1).clamp(0, 99)} phones connected'
                        '${s.ptt!.peerStates.isEmpty ? '' : '\n${s.ptt!.peerStates.entries.map((e) => '${s.members[e.key]?.vehicleLabel ?? s.members[e.key]?.displayName ?? 'member'}: ${e.value}').join(', ')}'}'
                        '${s.ptt!.micError == null ? '' : '\nMicrophone: ${s.ptt!.micError}'}'
                        '\nRelay (TURN): ${s.ptt!.hasRelay ? 'available' : 'not set up, so phones on different mobile networks may not hear each other'}',
              ),
              (Icons.cloud_upload_rounded, s.pendingWrites == 0 ? c.good : c.warn, 'Waiting to send', '${s.pendingWrites} change(s)'),
            ];
            final text = [
              for (final r in rows) '${r.$3}: ${r.$4}',
              if (ch != null && ch.history.isNotEmpty) 'Live connection log:\n${ch.history.join('\n')}',
            ].join('\n\n');
            return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              Text('Connection details', textAlign: TextAlign.center, style: t.headlineSmall),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  for (final (i, (icon, color, title, detail)) in rows.indexed) ...[
                    if (i > 0) const Divider(indent: 20, endIndent: 20),
                    Tile(leading: TileIcon(icon, color: color, size: 34), title: title, subtitle: detail),
                  ],
                ]),
              ),
              if (ch != null && ch.history.isNotEmpty)
                Section(title: 'Live connection log', children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(ch.history.join('\n'), style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
                  ),
                ]),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy details'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied. Paste it in a message.')));
                },
              ),
            ]);
          },
        ),
      ),
    );
