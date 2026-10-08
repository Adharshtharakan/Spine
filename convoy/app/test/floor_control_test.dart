import 'package:convoy/services/voice/floor_control.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 1, 12);

  test('one talker at a time', () {
    final f = FloorControl();
    expect(f.tryAcquire('a', t0), isTrue);
    f.remoteStart('b', t0.add(const Duration(seconds: 1)));
    expect(f.holder, 'a');
    f.release('a');
    expect(f.holder, isNull);
  });

  test('simultaneous presses resolve identically on both phones', () {
    final onA = FloorControl()..tryAcquire('a', t0.add(const Duration(milliseconds: 40)));
    final onB = FloorControl()..tryAcquire('b', t0);
    onA.remoteStart('b', t0);
    onB.remoteStart('a', t0.add(const Duration(milliseconds: 40)));
    expect(onA.holder, 'b');
    expect(onB.holder, 'b');
  });

  test('ties go to the smaller id', () {
    final f = FloorControl()..remoteStart('z', t0);
    f.remoteStart('m', t0);
    expect(f.holder, 'm');
  });

  test('a talker who lost signal does not hold the floor forever', () {
    final f = FloorControl(maxHold: const Duration(seconds: 50))..remoteStart('a', t0);
    expect(f.tryAcquire('b', t0.add(const Duration(seconds: 10))), isFalse);
    expect(f.tryAcquire('b', t0.add(const Duration(seconds: 51))), isTrue);
  });
}
