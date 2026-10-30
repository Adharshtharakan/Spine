import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/widgets/one_ui.dart';
import 'features/stops/stops_tab.dart';
import 'features/trips/trip_screen.dart';
import 'services/mesh/mesh_bridge.dart';
import 'services/safety/crash_hook.dart';
import 'services/voice/announcer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Env.isConfigured) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  }

  // Offline mesh, spoken alerts and crash detection ride along with every open trip.
  tripSessionHooks
    ..add(attachMesh)
    ..add(attachAnnouncer)
    ..add(attachCrashDetection);
  // Affiliate stops along the route (hotels, campsites, fuel, rest areas).
  registerTripTab(
    const FloatingNavItem(Icons.storefront_outlined, Icons.storefront_rounded, 'Stops'),
    (s) => StopsTab(session: s),
  );

  runApp(const ProviderScope(child: DriveSyncApp()));
}
