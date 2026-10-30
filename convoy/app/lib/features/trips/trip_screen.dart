import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/one_ui.dart';
import '../../state/providers.dart';
import '../../state/trip_session.dart';
import '../chat/chat_tab.dart';
import '../itinerary/itinerary_tab.dart';
import '../map/map_tab.dart';
import 'convoy_tab.dart';

/// One open trip. Owns the [TripSession] for as long as the trip is on screen.
class TripScreen extends ConsumerStatefulWidget {
  const TripScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends ConsumerState<TripScreen> {
  late final TripSession session;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    session = createTripSession(ref, widget.tripId)..open();
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.loading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final unread = session.messages.length;
        final tabs = [
          MapTab(session: session),
          ItineraryTab(session: session),
          ChatTab(session: session),
          ConvoyTab(session: session),
          ...extraTripTabs(session),
        ];
        // Tabs draw their own headers; the tab bar floats over the content.
        return Scaffold(
          extendBody: true,
          body: IndexedStack(index: _tab, children: tabs),
          bottomNavigationBar: FloatingNavBar(
            index: _tab,
            onTap: (i) => setState(() => _tab = i),
            items: [
              const FloatingNavItem(Icons.map_outlined, Icons.map_rounded, 'Map'),
              const FloatingNavItem(Icons.route_outlined, Icons.route_rounded, 'Plan'),
              FloatingNavItem(Icons.forum_outlined, Icons.forum_rounded, 'Chat', badge: _tab == 2 ? 0 : unread),
              const FloatingNavItem(Icons.groups_outlined, Icons.groups_rounded, 'Convoy'),
              ...extraTripDestinations(),
            ],
          ),
        );
      },
    );
  }
}

/// Builds the session and wires in optional subsystems (mesh, affiliate
/// stops) registered by later layers.
TripSession createTripSession(WidgetRef ref, String tripId) {
  final s = TripSession(ref.read(supabaseProvider), tripId);
  for (final hook in tripSessionHooks) {
    hook(ref, s);
  }
  return s;
}

/// Extension points so the offline mesh and the affiliate "Stops" tab plug
/// into the trip without this screen depending on them directly.
final List<void Function(WidgetRef ref, TripSession s)> tripSessionHooks = [];
final List<Widget Function(TripSession s)> _extraTabs = [];
final List<FloatingNavItem> _extraDestinations = [];

void registerTripTab(FloatingNavItem destination, Widget Function(TripSession s) build) {
  _extraDestinations.add(destination);
  _extraTabs.add(build);
}

List<Widget> extraTripTabs(TripSession s) => [for (final b in _extraTabs) b(s)];
List<FloatingNavItem> extraTripDestinations() => List.of(_extraDestinations);
