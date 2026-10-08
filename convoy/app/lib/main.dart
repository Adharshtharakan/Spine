import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/theme.dart';

void main() {
  runApp(const ProviderScope(child: ConvoyApp()));
}

class ConvoyApp extends StatelessWidget {
  const ConvoyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Convoy',
        theme: ConvoyTheme.light(),
        darkTheme: ConvoyTheme.dark(),
        home: const Scaffold(body: Center(child: Text('Convoy'))),
      );
}
