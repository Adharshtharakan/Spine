import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/theme/theme.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/guidelines/guidelines_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/trips/home_screen.dart';
import 'features/trips/trip_screen.dart';
import 'services/invite/invite_links.dart';
import 'services/push/push_service.dart';
import 'state/providers.dart';
import 'state/settings.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class DriveSyncApp extends ConsumerStatefulWidget {
  const DriveSyncApp({super.key});

  @override
  ConsumerState<DriveSyncApp> createState() => _DriveSyncAppState();
}

class _DriveSyncAppState extends ConsumerState<DriveSyncApp> {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    // Tapped notification → that trip.
    PushService.onOpenTrip = (tripId) =>
        rootNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => TripScreen(tripId: tripId)));
    // Invite links (https://…/j/CODE, drivesync://join/CODE) → join.
    try {
      _links = AppLinks().uriLinkStream.listen((uri) {
        final code = InviteLinks.codeFrom(uri.toString());
        if (code != null) ref.read(pendingInviteProvider.notifier).set(code);
      });
    } catch (_) {
      // No platform support (tests).
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DriveSync',
        navigatorKey: rootNavigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ConvoyTheme.light(),
        darkTheme: ConvoyTheme.dark(),
        themeMode: ref.watch(themeModeProvider),
        home: Env.isConfigured ? const _Gate() : const _NotConfigured(),
      );
}

/// Signed in → accepted current guidelines and driver terms → first-run
/// setup → home.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SignInScreen();
    return ref.watch(acceptedGuidelinesProvider).when(
          data: (ok) => !ok
              ? const GuidelinesScreen()
              : ref.watch(onboardedProvider).when(
                    data: (done) {
                      // Push notifications for this account (no-op without
                      // Firebase keys); first-run setup asks for permission itself.
                      if (done) unawaited(PushService.start(ref.read(supabaseProvider)));
                      return done ? const HomeScreen() : const OnboardingScreen();
                    },
                    loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
                    error: (_, _) => const HomeScreen(),
                  ),
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          // Offline at launch: let a returning user reach their cached trips;
          // the server still enforces acceptance on every write.
          error: (_, _) => const HomeScreen(),
        );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('DriveSync is not configured.\n\nRun with --dart-define-from-file=env.json '
                '(see env.example.json).', textAlign: TextAlign.center),
          ),
        ),
      );
}
