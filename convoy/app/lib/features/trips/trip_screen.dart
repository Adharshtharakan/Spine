import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        return Scaffold(
          appBar: AppBar(title: Text(session.trip?.title ?? 'Convoy')),
          body: IndexedStack(index: _tab, children: tabs),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
              const NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Plan'),
              NavigationDestination(
                icon: Badge(isLabelVisible: unread > 0 && _tab != 2, smallSize: 8, child: const Icon(Icons.forum_outlined)),
                selectedIcon: const Icon(Icons.forum),
                label: 'Chat',
              ),
              const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Convoy'),
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
final List<NavigationDestination> _extraDestinations = [];

void registerTripTab(NavigationDestination destination, Widget Function(TripSession s) build) {
  _extraDestinations.add(destination);
  _extraTabs.add(build);
}

List<Widget> extraTripTabs(TripSession s) => [for (final b in _extraTabs) b(s)];
List<NavigationDestination> extraTripDestinations() => List.of(_extraDestinations);
