import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
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
    final t = Theme.of(context).textTheme;
    final c = context.tones;
    final mq = MediaQuery.of(context);
    final msgs = s.messages.reversed.toList();
    // Clear the floating tab bar, unless the keyboard is up and hides it.
    final bottom = mq.viewInsets.bottom > 0 ? 8.0 : mq.padding.bottom + 4;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Chat'),
          Text('${s.trip?.title ?? 'Trip'}  ·  ${s.members.length} people', style: t.bodySmall),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: msgs.isEmpty
              ? const SingleChildScrollView(
                  child: EmptyState(
                    icon: Icons.forum_rounded,
                    title: 'No messages yet',
                    text: 'Only people on this trip can read them. Quick replies are one tap.',
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final mine = m.senderId == s.userId;
                    if (m.kind == 'system') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(color: c.cardHigh, borderRadius: BorderRadius.circular(99)),
                            child: Text('${m.senderName ?? 'Someone'} ${m.body}', style: t.labelMedium),
                          ),
                        ),
                      );
                    }
                    final fg = mine ? c.onAccent : c.ink;
                    final sub = mine ? c.onAccent.withValues(alpha: 0.75) : c.faint;
                    const r = Radius.circular(22), tail = Radius.circular(6);
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          if (!mine)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 0, 3),
                              child: Text(m.senderName ?? 'Driver', style: t.labelMedium),
                            ),
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.fromLTRB(15, 10, 15, 8),
                            constraints: BoxConstraints(maxWidth: mq.size.width * 0.78),
                            decoration: BoxDecoration(
                              color: mine ? c.accent : c.card,
                              borderRadius: BorderRadius.only(
                                topLeft: r,
                                topRight: r,
                                bottomLeft: mine ? r : tail,
                                bottomRight: mine ? tail : r,
                              ),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(m.body,
                                  style: (m.kind == 'quick' ? t.titleMedium : t.bodyLarge)?.copyWith(color: fg)),
                              const SizedBox(height: 3),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(DateFormat.Hm().format(m.createdAt), style: t.labelSmall?.copyWith(color: sub)),
                                if (m.viaMesh) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.settings_input_antenna, size: 12, color: sub),
                                  const SizedBox(width: 2),
                                  Text('radio', style: t.labelSmall?.copyWith(color: sub)),
                                ],
                                if (m.pending) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.schedule_rounded, size: 12, color: sub),
                                ],
                              ]),
                            ]),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        // Quick replies: one tap.
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
            children: [
              for (final q in quick)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(q),
                    labelStyle: t.titleSmall?.copyWith(color: c.accent),
                    backgroundColor: c.accentSoft,
                    onPressed: () => s.sendMessage(q, kind: 'quick'),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(14, 4, 14, bottom),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              // Typing is paused while this phone is in a moving car that
              // someone is driving: quick replies and push-to-talk remain.
              child: s.drivingLock
                  ? _DrivingLock(onPassenger: () => setState(() => s.passengerMode = true))
                  : TextField(
                      controller: _text,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Message the convoy',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
                        enabledBorder:
                            OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
                        focusedBorder:
                            OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
                        suffixIcon: IconButton(
                          tooltip: 'Send',
                          icon: Icon(Icons.send_rounded, color: c.accent),
                          onPressed: _send,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
            ),
            const SizedBox(width: 10),
            PttButton(session: s, size: 52),
          ]),
        ),
      ]),
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
  Widget build(BuildContext context) => InfoBanner(
        'Typing is paused while you drive. Use a quick reply or hold to talk.',
        icon: Icons.directions_car_rounded,
        action: TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
          onPressed: onPassenger,
          child: const Text("I'm a passenger"),
        ),
      );
}
