import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Screen-capture protection for the reading surface.
///
/// What this actually does, per platform — worth being precise, because the two
/// are not equivalent:
///
///   Android — `FLAG_SECURE` genuinely blocks screenshots and screen
///   recording, and blanks the app in the recents switcher. The OS enforces it.
///
///   iOS — Apple provides no way to prevent a screenshot. The app can only be
///   told one happened, and can hide its content in the app switcher. So on
///   iPhone this is a deterrent and a signal, not a block.
///
/// On both platforms a second camera pointed at the screen defeats it entirely.
/// This raises the effort required to lift content; it is not DRM, and the app
/// should never promise users that their content cannot be captured.
class CaptureGuard {
  CaptureGuard({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('spine/capture_guard');

  final MethodChannel _channel;

  bool _enabled = false;
  bool get isEnabled => _enabled;

  /// Turns protection on. Safe to call more than once, and safe on platforms
  /// where the channel isn't implemented — capture protection failing must
  /// never stop the app from opening.
  Future<void> enable() => _set(true);

  Future<void> disable() => _set(false);

  Future<void> _set(bool value) async {
    if (_enabled == value) return;
    try {
      await _channel.invokeMethod<void>('setProtected', value);
      _enabled = value;
    } on MissingPluginException {
      // Desktop, web, or a test host: nothing to protect.
      debugPrint('Spine: capture protection unavailable on this platform');
    } catch (error) {
      debugPrint('Spine: capture protection failed — $error');
    }
  }

  /// Fires when iOS reports a screenshot was taken. Android never calls this:
  /// there, the screenshot didn't happen.
  void onScreenshotDetected(VoidCallback listener) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'screenshotTaken') listener();
    });
  }
}
