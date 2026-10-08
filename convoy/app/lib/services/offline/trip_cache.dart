import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Last good snapshot of a trip (trip row, members, itinerary, recent chat,
/// last-known positions) so the trip opens, the map plots and the mesh can
/// start even when the phone has no signal at all.
class TripCache {
  TripCache(this.tripId);

  final String tripId;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/trip_$tripId.json');
  }

  Future<void> save(Map<String, dynamic> snapshot) async {
    try {
      await (await _file()).writeAsString(jsonEncode(snapshot), flush: true);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
