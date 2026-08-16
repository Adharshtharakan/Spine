import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

/// Captures a widget to a PNG file without ever showing it to the reader.
///
/// `RenderRepaintBoundary.toImage` only has something to capture once its
/// widget has gone through a real layout and paint pass, so the card is
/// mounted through an [Overlay] entry positioned off the visible canvas —
/// technically part of the render tree, never on screen.
class StoryCardRenderer {
  const StoryCardRenderer();

  /// [pixelRatio] of 1 against a widget already sized to the target
  /// resolution (see `StoryCard.size`) makes the export exact — the card's
  /// logical size *is* the output's pixel size.
  Future<File> capture({
    required BuildContext context,
    required Widget card,
    required String fileName,
    double pixelRatio = 1,
  }) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final boundaryKey = GlobalKey();
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        left: -8000,
        top: 0,
        child: IgnorePointer(
          child: Material(
            type: MaterialType.transparency,
            child: RepaintBoundary(key: boundaryKey, child: card),
          ),
        ),
      ),
    );

    overlay.insert(entry);

    try {
      // Two frames: the first lays out and paints; the second lets any asset
      // image still decoding when the first frame fired catch up before the
      // capture reads pixels.
      await SchedulerBinding.instance.endOfFrame;
      await SchedulerBinding.instance.endOfFrame;

      final renderObject = boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('Story card failed to mount for capture.');
      }

      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      final bytes = await _encodePng(image);

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } finally {
      entry.remove();
    }
  }

  Future<Uint8List> _encodePng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Failed to encode the story card.');
    return data.buffer.asUint8List();
  }
}
