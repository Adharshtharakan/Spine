import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/theme.dart';
import '../../state/trip_session.dart';
import '../map/map_tab.dart';

/// Text channel for the travel party only (RLS + private Realtime channel).
/// Quick replies are one tap so a passenger — or a driver at a standstill —
/// can answer without typing.
class ChatTab extends StatefulWidget {
  const ChatTab({super.key, required this.session});

  final TripSession session;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _text = TextEditingController();

  static const quick = [
    'Need a stop',
    'Fuel soon',
    'Lost sight of you',
    'All good',
    'Pull over ahead',
    'Slow down',
  ];

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final t = Theme.of(context);
    final msgs = s.messages.reversed.toList();
    return Column(children: [
      Expanded(
        child: ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(12),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final m = msgs[i];
            final mine = m.senderId == s.userId;
            if (m.kind == 'system') {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('${m.senderName ?? 'Someone'} ${m.body}',
                    textAlign: TextAlign.center, style: t.textTheme.bodySmall),
              );
            }
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                decoration: BoxDecoration(
                  color: mine ? t.colorScheme.primary : t.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(mine ? 20 : 6),
                    bottomRight: Radius.circular(mine ? 6 : 20),
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!mine)
                    Text(m.senderName ?? 'Driver',
                        style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w800)),
                  Text(m.body,
                      style: (m.kind == 'quick' ? t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) : t.textTheme.bodyLarge)
                          ?.copyWith(color: mine ? t.colorScheme.onPrimary : t.colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(DateFormat.Hm().format(m.createdAt),
                        style: t.textTheme.labelSmall?.copyWith(
                            color: (mine ? t.colorScheme.onPrimary : t.colorScheme.onSurfaceVariant).withValues(alpha: 0.8))),
                    if (m.viaMesh) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.settings_input_antenna, size: 12, color: ConvoyTheme.mesh),
                    ],
                    if (m.pending) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.schedule, size: 12, color: mine ? t.colorScheme.onPrimary : null),
                    ],
                  ]),
                ]),
              ),
            );
          },
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            for (final q in quick)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(label: Text(q), onPressed: () => s.sendMessage(q, kind: 'quick')),
              ),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _text,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Message the convoy', isDense: true),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(icon: const Icon(Icons.send), onPressed: _send),
            Transform.scale(scale: 0.7, child: PttButton(session: s)),
          ]),
        ),
      ),
    ]);
  }

  void _send() {
    final text = _text.text;
    _text.clear();
    widget.session.sendMessage(text);
  }
}
