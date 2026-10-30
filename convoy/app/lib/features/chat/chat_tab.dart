import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/wayfind.dart';
import '../../state/trip_session.dart';
import '../map/map_tab.dart';

/// Text channel for the travel party only (RLS + private Realtime channel).
/// Quick replies are one tap so a passenger, or a driver at a standstill,
/// can answer without typing.
class ChatTab extends StatefulWidget {
  const ChatTab({super.key, required this.session});

  final TripSession session;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _text = TextEditingController();

  static const quick = ['Need a stop', 'Fuel soon', 'Lost sight of you', 'All good', 'Pull over ahead', 'Slow down'];

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final t = Theme.of(context);
    final w = context.wf;
    final msgs = s.messages.reversed.toList();
    return Column(
      children: [
        Expanded(
          child: msgs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      'No messages yet. Only people on this trip can read them.',
                      style: t.textTheme.bodyMedium?.copyWith(color: w.muted),
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final mine = m.senderId == s.userId;
                    if (m.kind == 'system') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          '${m.senderName ?? 'Someone'} ${m.body}',
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodySmall,
                        ),
                      );
                    }
                    // Square slips: yours on the ink plate, everyone else's on paper with an ink rule.
                    final fg = mine ? w.onPlate : w.ink;
                    final sub = mine ? w.plateMuted : w.muted;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
                        decoration: BoxDecoration(
                          color: mine ? w.plate : w.paper3,
                          border: Border.all(color: mine ? w.plateRule : w.ink, width: Rules.bar),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!mine)
                              Text(
                                m.senderName ?? 'Driver',
                                style: t.textTheme.labelMedium?.copyWith(color: w.ink, fontWeight: FontWeight.w800),
                              ),
                            Text(
                              m.body,
                              style: (m.kind == 'quick' ? t.textTheme.titleMedium : t.textTheme.bodyLarge)?.copyWith(
                                color: fg,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DateFormat.Hm().format(m.createdAt),
                                  style: t.textTheme.labelSmall?.copyWith(color: sub),
                                ),
                                if (m.viaMesh) ...[
                                  const SizedBox(width: 8),
                                  Text('by radio', style: t.textTheme.labelSmall?.copyWith(color: sub)),
                                ],
                                if (m.pending) ...[
                                  const SizedBox(width: 8),
                                  Text('sending', style: t.textTheme.labelSmall?.copyWith(color: sub)),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        // Quick replies: one tap, square keys in a row along the rule.
        Container(
          height: 56,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: w.ink, width: Rules.bar),
            ),
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            children: [
              for (final q in quick)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: t.textTheme.titleSmall,
                      backgroundColor: w.paper3,
                    ),
                    onPressed: () => s.sendMessage(q, kind: 'quick'),
                    child: Text(q),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  // Typing is paused while this phone is in a moving car that
                  // someone is driving: quick replies and push-to-talk remain.
                  child: s.drivingLock
                      ? _DrivingLock(onPassenger: () => setState(() => s.passengerMode = true))
                      : TextField(
                          controller: _text,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(hintText: 'Message the convoy', isDense: true),
                          onSubmitted: (_) => _send(),
                        ),
                ),
                if (!s.drivingLock) IconButton(tooltip: 'Send', icon: const Icon(Icons.send), onPressed: _send),
                Transform.scale(scale: 0.7, child: PttButton(session: s)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _send() {
    final text = _text.text;
    _text.clear();
    widget.session.sendMessage(text);
  }
}

class _DrivingLock extends StatelessWidget {
  const _DrivingLock({required this.onPassenger});
  final VoidCallback onPassenger;

  @override
  Widget build(BuildContext context) => Note(
    'Typing is paused while you drive. Use a quick reply or hold to talk.',
    icon: Icons.directions_car,
    actionBelow: true,
    action: TextButton(
      style: TextButton.styleFrom(foregroundColor: context.wf.onFigure),
      onPressed: onPassenger,
      child: const Text("I'm a passenger"),
    ),
  );
}
