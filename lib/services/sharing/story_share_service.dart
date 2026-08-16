import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Where a story card can be shared to.
enum StoryTarget {
  instagram,
  facebook;

  String get label => switch (this) {
    StoryTarget.instagram => 'Instagram',
    StoryTarget.facebook => 'Facebook',
  };
}

/// Shares a rendered story card.
///
/// Instagram and Facebook both expose a native "add to story" contract
/// (Android intent action, iOS pasteboard handoff) rather than a normal share
/// sheet entry — see `android/.../MainActivity.kt` and
/// `ios/Runner/AppDelegate.swift` for the platform side of this channel. Any
/// platform without that wiring, or without the target app installed, falls
/// back to the OS share sheet, so the button is never a dead end.
abstract interface class StoryShareService {
  /// Whether [target]'s app is installed and can receive a story. Used to
  /// decide which buttons to offer, not to gate the fallback share sheet.
  Future<bool> canShare(StoryTarget target);

  Future<void> shareToStory(File image, {required StoryTarget target});

  /// The plain OS share sheet — always available, used both as the explicit
  /// "more" option and as the fallback when a target app isn't installed.
  Future<void> shareGeneric(File image);
}

class NativeStoryShareService implements StoryShareService {
  NativeStoryShareService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('spine/story_share');

  final MethodChannel _channel;

  @override
  Future<bool> canShare(StoryTarget target) async {
    try {
      return await _channel.invokeMethod<bool>('canShare', {
            'target': target.name,
          }) ??
          false;
    } catch (error) {
      debugPrint('Spine: canShare(${target.name}) failed — $error');
      return false;
    }
  }

  @override
  Future<void> shareToStory(File image, {required StoryTarget target}) async {
    try {
      final handled = await _channel.invokeMethod<bool>('shareToStory', {
        'target': target.name,
        'path': image.path,
      });
      if (handled == true) return;
    } catch (error) {
      debugPrint('Spine: shareToStory(${target.name}) failed — $error');
    }
    // The target app either isn't installed or the platform channel isn't
    // implemented here (e.g. desktop) — the OS share sheet always works.
    await shareGeneric(image);
  }

  @override
  Future<void> shareGeneric(File image) async {
    await Share.shareXFiles([XFile(image.path)]);
  }
}

/// Used in tests and as a safe default before the native channel is wired.
class NoopStoryShareService implements StoryShareService {
  final List<String> calls = [];

  @override
  Future<bool> canShare(StoryTarget target) async {
    calls.add('canShare:${target.name}');
    return false;
  }

  @override
  Future<void> shareToStory(File image, {required StoryTarget target}) async {
    calls.add('shareToStory:${target.name}:${image.path}');
  }

  @override
  Future<void> shareGeneric(File image) async {
    calls.add('shareGeneric:${image.path}');
  }
}
