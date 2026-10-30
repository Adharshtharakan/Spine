import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/convoy_event.dart';

/// Checklists for a trip: personal documents and pre-trip checks, personal
/// packing, and a shared group list.
class ChecklistRepository {
  ChecklistRepository(this._db);
  final SupabaseClient _db;
  static const _uuid = Uuid();

  static const categories = ['documents', 'vehicle', 'packing', 'group'];

  static String label(String category) => switch (category) {
        'documents' => 'Documents',
        'vehicle' => 'Vehicle check',
        'packing' => 'Packing',
        _ => 'Group',
      };

  /// Starting points, added the first time someone opens a trip's lists.
  static const templates = {
    'documents': ['Driving licence', 'Vehicle RC', 'Insurance certificate', 'PUC certificate', 'FASTag balance topped up', 'ID card'],
    'vehicle': ['Tyre pressure, spare included', 'Engine oil and coolant', 'Brakes and lights', 'Jack and wheel spanner', 'First-aid kit', 'Phone mount and charger'],
    'packing': ['Water and snacks', 'Power bank', 'Medicines', 'Jacket or raincoat', 'Cash for tolls'],
    'group': ['Offline maps downloaded', 'Meeting point agreed'],
  };

  Future<List<ChecklistItem>> list(String tripId) async {
    final rows = await _db.from('checklist_items').select().eq('trip_id', tripId).order('sort');
    return rows.map(ChecklistItem.fromRow).toList();
  }

  /// Adds the templates for any category this member has nothing in yet.
  Future<List<ChecklistItem>> seed(String tripId, String memberId, List<ChecklistItem> existing) async {
    final rows = <Map<String, dynamic>>[];
    for (final e in templates.entries) {
      final shared = e.key == 'group';
      final has = existing.any((i) => i.category == e.key && (shared ? i.memberId == null : i.memberId == memberId));
      if (has) continue;
      for (final (n, title) in e.value.indexed) {
        rows.add(ChecklistItem(
          id: _uuid.v4(),
          tripId: tripId,
          memberId: shared ? null : memberId,
          category: e.key,
          title: title,
          sort: n.toDouble(),
        ).toRow());
      }
    }
    if (rows.isNotEmpty) await _db.from('checklist_items').insert(rows);
    return rows.map(ChecklistItem.fromRow).toList();
  }

  Future<ChecklistItem> add(String tripId, {required String category, required String title, String? memberId, double sort = 100}) async {
    final item = ChecklistItem(id: _uuid.v4(), tripId: tripId, memberId: memberId, category: category, title: title, sort: sort);
    await _db.from('checklist_items').insert(item.toRow());
    return item;
  }

  Future<void> setDone(ChecklistItem item, bool done) => _db
      .from('checklist_items')
      .update({'done': done, 'done_by': done ? _db.auth.currentUser?.id : null}).eq('id', item.id);

  Future<void> remove(ChecklistItem item) => _db.from('checklist_items').delete().eq('id', item.id);
}
