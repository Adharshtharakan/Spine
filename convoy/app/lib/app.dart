import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/theme/theme.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/guidelines/guidelines_screen.dart';
import 'features/trips/home_screen.dart';
import 'state/providers.dart';

class ConvoyApp extends StatelessWidget {
  const ConvoyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Convoy',
        debugShowCheckedModeBanner: false,
        theme: ConvoyTheme.light(),
        darkTheme: ConvoyTheme.dark(),
        home: Env.isConfigured ? const _Gate() : const _NotConfigured(),
      );
}

/// Signed in → accepted current guidelines and driver terms → home.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SignInScreen();
    return ref.watch(acceptedGuidelinesProvider).when(
          data: (ok) => ok ? const HomeScreen() : const GuidelinesScreen(),
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
            child: Text('Convoy is not configured.\n\nRun with --dart-define-from-file=env.json '
                '(see env.example.json).', textAlign: TextAlign.center),
          ),
        ),
      );
}
