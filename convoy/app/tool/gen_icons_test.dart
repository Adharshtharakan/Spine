// Regenerates the Android and iOS launcher icons from DriveSyncMarkPainter:
//
//   flutter test tool/gen_icons_test.dart
//
// Lives in tool/ so CI does not run it.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:convoy/core/brand/logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> render(CustomPainter p, int px, String path) async {
  final rec = ui.PictureRecorder();
  p.paint(Canvas(rec), Size(px.toDouble(), px.toDouble()));
  final img = await rec.endRecording().toImage(px, px);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  test('generate launcher icons', () async {
    const res = 'android/app/src/main/res';
    const densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
    // Adaptive layers are 108 dp; the glyph must fit the 66 dp mask circle.
    const adaptiveGlyph = 0.68;
    for (final e in densities.entries) {
      final dir = '$res/mipmap-${e.key}';
      await render(const DriveSyncMarkPainter(), (48 * e.value).round(), '$dir/ic_launcher.png');
      final layer = (108 * e.value).round();
      await render(const DriveSyncMarkPainter(roundedTile: false, glyph: false), layer, '$dir/ic_launcher_background.png');
      await render(const DriveSyncMarkPainter(background: false, glyphScale: adaptiveGlyph), layer, '$dir/ic_launcher_foreground.png');
      await render(const DriveSyncMarkPainter(background: false, monochrome: true, glyphScale: adaptiveGlyph), layer,
          '$dir/ic_launcher_monochrome.png');
    }
    File('$res/mipmap-anydpi-v26/ic_launcher.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
''');

    // iOS: every image listed in the asset catalogue, square (iOS masks it).
    const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final contents = jsonDecode(File('$ios/Contents.json').readAsStringSync()) as Map<String, dynamic>;
    for (final img in (contents['images'] as List).cast<Map<String, dynamic>>()) {
      final file = img['filename'] as String?;
      if (file == null) continue;
      final pt = double.parse((img['size'] as String).split('x').first);
      final scale = double.parse((img['scale'] as String).replaceAll('x', ''));
      await render(const DriveSyncMarkPainter(roundedTile: false), (pt * scale).round(), '$ios/$file');
    }
  });
}
