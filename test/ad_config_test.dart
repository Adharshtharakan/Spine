import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spine/core/config/ad_config.dart';
import 'package:spine/services/ads/native_ad_preloader.dart';

void main() {
  group('AdConfig', () {
    test('defaults to Google\'s test units, never a live one', () {
      const config = AdConfig();
      expect(config.androidNativeUnitId, AdConfig.testNativeUnitIdAndroid);
      expect(config.iosNativeUnitId, AdConfig.testNativeUnitIdIos);
      expect(config.useTestUnits, isTrue);
    });

    test('fromEnvironment stays on test units with nothing defined', () {
      // Serving live inventory from a dev build is what gets AdMob accounts
      // suspended, so it has to take a deliberate --dart-define to happen.
      final config = AdConfig.fromEnvironment();
      expect(config.useTestUnits, isTrue);
      expect(config.frequency, 6);
      expect(config.leadIn, 5);
    });

    test('copyWith carries the unit ids through', () {
      const config = AdConfig();
      final live = config.copyWith(
        androidNativeUnitId: 'ca-app-pub-0000000000000000/1111111111',
        useTestUnits: false,
      );

      expect(live.androidNativeUnitId, isNot(AdConfig.testNativeUnitIdAndroid));
      expect(live.iosNativeUnitId, AdConfig.testNativeUnitIdIos);
      expect(live.useTestUnits, isFalse);
    });

    test('asking for a unit id off Android and iOS is an error, not a guess', () {
      // The test VM is neither, which is exactly the case being pinned: a
      // silent fallback here would mean desktop builds quietly requesting ads
      // against an Android unit.
      expect(AdConfig.supportsAds, isFalse);
      expect(() => const AdConfig().nativeUnitId, throwsUnsupportedError);
    });
  });

  group('NativeAdPreloader', () {
    test('does nothing on a platform without ads', () {
      // No SDK is registered in a test run, so if the guard were missing this
      // would throw on the first NativeAd construction rather than no-op.
      final preloader = NativeAdPreloader(config: const AdConfig());
      addTearDown(preloader.dispose);

      preloader.preload([1, 2, 3], focused: 1);

      expect(preloader.adFor(1), isNull);
      expect(preloader.hasFailed(1), isFalse);
    });

    test('does nothing when ads are switched off', () {
      final preloader = NativeAdPreloader(
        config: const AdConfig(enabled: false),
      );
      addTearDown(preloader.dispose);

      preloader.preload([1]);

      expect(preloader.adFor(1), isNull);
    });

    test('both platforms register the factory id Dart asks for', () {
      // The id is a string shared across Dart, Kotlin and Swift with no
      // compiler between them. A mismatch fails at ad-load time with
      // "factory not found" — a long way from where the mistake was made, and
      // only on a device. Reading the sources is cheap next to that.
      final native = {
        'MainActivity.kt': File(
          'android/app/src/main/kotlin/com/spineapp/spine/MainActivity.kt',
        ),
        'AppDelegate.swift': File('ios/Runner/AppDelegate.swift'),
      };

      for (final entry in native.entries) {
        expect(
          entry.value.existsSync(),
          isTrue,
          reason: '${entry.key} is missing',
        );
        expect(
          entry.value.readAsStringSync(),
          contains('"$kReelAdFactoryId"'),
          reason: '${entry.key} does not register "$kReelAdFactoryId"',
        );
      }
    });
  });
}
