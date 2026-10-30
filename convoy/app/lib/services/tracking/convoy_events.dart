import '../../data/models/convoy_event.dart';

/// Who is ready to go at a stop.
class Headcount {
  const Headcount(this.started, this.ready);

  /// The `headcount` event that opened it (who asked, when).
  final ConvoyEvent started;

  /// Members who tapped "Ready to go".
  final Set<String> ready;
}

/// Current state derived from the append-only convoy event log.
class ConvoyEventState {
  const ConvoyEventState({this.sos = const {}, this.hazards = const [], this.regroup, this.headcount});

  /// memberId → their active SOS.
  final Map<String, ConvoyEvent> sos;

  /// Live hazard reports, oldest first.
  final List<ConvoyEvent> hazards;

  /// The current regroup point, if any.
  final ConvoyEvent? regroup;

  /// An open headcount, if any.
  final Headcount? headcount;

  static const sosLifetime = Duration(hours: 12);
  static const regroupLifetime = Duration(hours: 6);
  static const headcountLifetime = Duration(hours: 3);

  factory ConvoyEventState.from(Iterable<ConvoyEvent> events, DateTime now) {
    final sorted = events.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final sos = <String, ConvoyEvent>{};
    final hazards = <String, ConvoyEvent>{};
    ConvoyEvent? regroup;
    ConvoyEvent? headcount;
    var ready = <String>{};
    for (final e in sorted) {
      switch (e.kind) {
        case EventKind.sos:
          sos[e.memberId] = e;
        case EventKind.sosClear:
          // "I'm OK" from the person themselves, or someone resolving it.
          sos.removeWhere((m, s) => s.id == e.ref || (e.ref == null && m == e.memberId));
        case EventKind.hazard:
          hazards[e.id] = e;
        case EventKind.hazardClear:
          hazards.remove(e.ref);
        case EventKind.regroup:
          regroup = e;
        case EventKind.regroupClear:
          if (e.ref == null || e.ref == regroup?.id) regroup = null;
        case EventKind.headcount:
          headcount = e;
          ready = {e.memberId};
        case EventKind.ready:
          if (headcount != null) ready.add(e.memberId);
        case EventKind.go:
          headcount = null;
          ready = {};
      }
    }
    bool fresh(ConvoyEvent e, Duration life) => now.difference(e.createdAt) < life;
    return ConvoyEventState(
      sos: {
        for (final x in sos.entries)
          if (fresh(x.value, sosLifetime)) x.key: x.value,
      },
      hazards: [
        for (final h in hazards.values)
          if (fresh(h, h.hazard.lifetime)) h,
      ],
      regroup: regroup != null && fresh(regroup, regroupLifetime) ? regroup : null,
      headcount: headcount != null && fresh(headcount, headcountLifetime) ? Headcount(headcount, ready) : null,
    );
  }
}
