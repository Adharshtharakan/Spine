import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'features/stops/stops_tab.dart';
import 'features/trips/trip_screen.dart';
import 'services/mesh/mesh_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Env.isConfigured) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  }

  // Offline mesh rides along with every open trip.
  tripSessionHooks.add(attachMesh);
  // Affiliate stops along the route (hotels, campsites, fuel, rest areas).
  registerTripTab(
    const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Stops'),
    (s) => StopsTab(session: s),
  );

  runApp(const ProviderScope(child: ConvoyApp()));
}
