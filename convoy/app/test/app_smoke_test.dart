import 'package:convoy/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('without build configuration the app explains how to configure it', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ConvoyApp()));
    expect(find.textContaining('not configured'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
