import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
import '../../data/models/convoy_event.dart';
import '../../data/repositories/checklist_repository.dart';
import '../../state/trip_session.dart';

/// Documents, a pre-trip vehicle check, packing (personal) and a group list
/// (shared with everyone in the trip).
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key, required this.session});
  final TripSession session;

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  late final _repo = ChecklistRepository(widget.session.db);
  List<ChecklistItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var items = await _repo.list(widget.session.tripId);
      final me = widget.session.me;
      if (me != null) items = [...items, ...await _repo.seed(widget.session.tripId, me.id, items)];
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = 'Checklists need a connection the first time.');
    }
  }

  Future<void> _toggle(ChecklistItem item) async {
    setState(() => _items = [for (final i in _items!) i.id == item.id ? i.copyWith(done: !i.done) : i]);
    try {
      await _repo.setDone(item, !item.done);
    } catch (_) {
      if (mounted) setState(() => _items = [for (final i in _items!) i.id == item.id ? item : i]);
    }
  }

  Future<void> _add(String category) async {
    final ctl = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add to ${ChecklistRepository.label(category)}'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Item'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Add')),
        ],
      ),
    );
    final text = title?.trim() ?? '';
    if (text.isEmpty) return;
    try {
      final item = await _repo.add(widget.session.tripId,
          category: category, title: text, memberId: category == 'group' ? null : widget.session.me?.id);
      setState(() => _items = [...?_items, item]);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not add the item. Check your connection.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final items = _items;
    final done = items?.where((i) => i.done).length ?? 0;
    final icons = {
      'documents': (Icons.badge_rounded, c.accent),
      'vehicle': (Icons.car_repair_rounded, c.warn),
      'packing': (Icons.backpack_rounded, c.good),
      'group': (Icons.groups_rounded, Color(Tones.vehicleColours[4])),
    };
    return LargeTitleScaffold(
      title: 'Checklists',
      subtitle: items == null ? widget.session.trip?.title : '$done of ${items.length} done',
      onRefresh: _load,
      children: [
        if (_error != null) InfoBanner(_error!, icon: Icons.cloud_off_rounded),
        if (items == null && _error == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (items != null)
          for (final cat in ChecklistRepository.categories)
            Section(
              title: cat == 'group' ? 'Group (shared with everyone)' : ChecklistRepository.label(cat),
              top: cat == ChecklistRepository.categories.first ? 0 : 20,
              trailing: Text(
                '${items.where((i) => i.category == cat && i.done).length}/${items.where((i) => i.category == cat).length}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              children: [
                for (final i in items.where((i) => i.category == cat))
                  Dismissible(
                    key: ValueKey(i.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      color: c.bad,
                      child: const Icon(Icons.delete_rounded, color: Colors.white),
                    ),
                    onDismissed: (_) {
                      setState(() => _items = items.where((x) => x.id != i.id).toList());
                      _repo.remove(i).catchError((_) {});
                    },
                    child: InkWell(
                      onTap: () => _toggle(i),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 20, 4),
                        child: Row(children: [
                          Checkbox(value: i.done, onChanged: (_) => _toggle(i)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              i.title,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: i.done ? c.faint : c.ink,
                                    decoration: i.done ? TextDecoration.lineThrough : null,
                                  ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                Tile(
                  onTap: () => _add(cat),
                  leading: TileIcon(icons[cat]!.$1, color: icons[cat]!.$2, size: 32),
                  title: 'Add item',
                  titleStyle: Theme.of(context).textTheme.titleSmall?.copyWith(color: c.accent),
                ),
              ],
            ),
      ],
    );
  }
}
