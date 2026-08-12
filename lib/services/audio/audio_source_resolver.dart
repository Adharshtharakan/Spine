import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'audio_track.dart';

/// Turns a catalogue `audio` string into something the player can open, and
/// owns the on-device cache for cloud-hosted narration.
///
/// MVP content is bundled (`asset:`), so nothing here touches the network yet.
/// When narration moves to a CDN, `prefetch` is the only thing that needs
/// wiring into a download queue.
class AudioSourceResolver {
  AudioSourceResolver({this.baseUrl = '', http.Client? client})
    : _client = client ?? http.Client();

  /// Prepended to relative refs once content is cloud-hosted.
  final String baseUrl;

  final http.Client _client;
  Directory? _cacheDir;

  Future<AudioSourceDescriptor> resolve(AudioTrack track) async {
    final ref = track.ref;
    if (ref == null || ref.isEmpty) return const UnrecordedAudioSource();

    if (ref.startsWith('asset:')) {
      return AssetAudioSource(ref.substring('asset:'.length));
    }
    if (ref.startsWith('file:')) {
      return FileAudioSource(Uri.parse(ref).toFilePath());
    }

    final uri = _absolute(ref);
    if (uri == null) return const UnrecordedAudioSource();

    // Serve from cache when we already have the bytes — the feed should never
    // re-download a track the reader has heard.
    final cached = await _cachedFile(uri);
    if (cached != null && await cached.exists()) {
      return FileAudioSource(cached.path);
    }
    return RemoteAudioSource(uri);
  }

  /// Downloads a remote track into the cache. Safe to call for tracks that are
  /// already cached (no-op) or bundled (no-op).
  Future<void> prefetch(AudioTrack track) async {
    final ref = track.ref;
    if (ref == null || ref.startsWith('asset:') || ref.startsWith('file:')) {
      return;
    }
    final uri = _absolute(ref);
    if (uri == null) return;

    final target = await _cachedFile(uri);
    if (target == null || await target.exists()) return;

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return;
      final temp = File('${target.path}.part');
      await temp.writeAsBytes(response.bodyBytes, flush: true);
      await temp.rename(target.path);
    } catch (error) {
      debugPrint('Spine: prefetch failed for $uri — $error');
    }
  }

  Uri? _absolute(String ref) {
    final combined = ref.startsWith('http')
        ? ref
        : '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/${ref.replaceFirst(RegExp(r'^/+'), '')}';
    final uri = Uri.tryParse(combined);
    return (uri != null && uri.hasScheme) ? uri : null;
  }

  Future<File?> _cachedFile(Uri uri) async {
    try {
      final dir = _cacheDir ??= Directory(
        '${(await getApplicationCacheDirectory()).path}/spine-audio',
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      final name = uri.pathSegments.isEmpty
          ? uri.hashCode.toString()
          : '${uri.hashCode}-${uri.pathSegments.last}';
      return File('${dir.path}/$name');
    } catch (error) {
      debugPrint('Spine: audio cache unavailable — $error');
      return null;
    }
  }

  void dispose() => _client.close();
}
