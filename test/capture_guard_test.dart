import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spine/services/security/capture_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('spine/capture_guard');
  final calls = <MethodCall>[];

  void handle(Future<Object?>? Function(MethodCall)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    calls.clear();
    handle((call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => handle(null));

  test('enabling asks the platform to protect the window', () async {
    final guard = CaptureGuard();
    await guard.enable();

    expect(calls.single.method, 'setProtected');
    expect(calls.single.arguments, isTrue);
    expect(guard.isEnabled, isTrue);
  });

  test('enabling twice does not talk to the platform twice', () async {
    final guard = CaptureGuard();
    await guard.enable();
    await guard.enable();

    expect(calls, hasLength(1));
  });

  test('disabling clears the flag', () async {
    final guard = CaptureGuard();
    await guard.enable();
    await guard.disable();

    expect(calls.last.arguments, isFalse);
    expect(guard.isEnabled, isFalse);
  });

  test('a platform without capture protection does not break the app', () async {
    // Desktop, web, or a test host: the channel simply isn't there.
    handle(null);

    final guard = CaptureGuard();
    await guard.enable();

    expect(guard.isEnabled, isFalse);
  });
}
