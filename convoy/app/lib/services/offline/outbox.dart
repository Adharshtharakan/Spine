import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Durable queue of writes made while offline: itinerary edits and chat
/// messages. Both are safe to replay — waypoints are guarded by their HLC
/// on the server, messages carry client-generated ids — so the outbox can
/// simply retry until each write lands.
class Outbox {
  Outbox(this._db, this.tripId);

  final SupabaseClient _db;
  final String tripId;
  final List<OutboxItem> _items = [];
  File? _file;
  bool _flushing = false;

  int get length => _items.length;

  Future<void> load() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/outbox_$tripId.json');
    if (await _file!.exists()) {
      try {
        final list = jsonDecode(await _file!.readAsString()) as List;
        _items
          ..clear()
          ..addAll(list.map((e) => OutboxItem.fromJson(Map<String, dynamic>.from(e as Map))));
      } catch (_) {
        // A corrupt file must never block the app; the data is also in the
        // in-memory ItineraryDoc and will be re-sent on the next edit.
        _items.clear();
      }
    }
  }

  Future<void> _persist() async {
    final f = _file;
    if (f == null) return;
    await f.writeAsString(jsonEncode(_items.map((e) => e.toJson()).toList()), flush: true);
  }

  Future<void> add(OutboxItem item) async {
    // Only the newest version of a waypoint matters.
    if (item.table == 'waypoints') {
      _items.removeWhere((e) => e.table == 'waypoints' && e.row['id'] == item.row['id']);
    }
    _items.add(item);
    await _persist();
  }

  /// Sends everything queued. Returns how many writes landed.
  Future<int> flush() async {
    if (_flushing || _items.isEmpty) return 0;
    _flushing = true;
    var sent = 0;
    try {
      while (_items.isNotEmpty) {
        final item = _items.first;
        try {
          switch (item.table) {
            case 'waypoints':
              await _db.from('waypoints').upsert(item.row);
            case 'messages':
              await _db.from('messages').upsert(item.row, ignoreDuplicates: true);
            case 'relay_message':
              // Another car's message heard over the radio; it may have no
              // signal for hours, so whoever reaches the cloud first posts it.
              await _db.rpc('relay_message', params: {'p_row': item.row});
          }
        } on PostgrestException catch (e) {
          // A permanent rejection (RLS, check constraint) would block the
          // queue forever; drop it. Network errors surface as other types.
          if (e.code != null && (e.code!.startsWith('4') || e.code!.startsWith('2'))) {
            _items.removeAt(0);
            await _persist();
            continue;
          }
          rethrow;
        }
        _items.removeAt(0);
        sent++;
        await _persist();
      }
    } catch (_) {
      // Still offline; try again on the next connectivity change.
    } finally {
      _flushing = false;
    }
    return sent;
  }
}

class OutboxItem {
  const OutboxItem(this.table, this.row);

  final String table;
  final Map<String, dynamic> row;

  Map<String, dynamic> toJson() => {'table': table, 'row': row};

  factory OutboxItem.fromJson(Map<String, dynamic> j) =>
      OutboxItem(j['table'] as String, Map<String, dynamic>.from(j['row'] as Map));
}
