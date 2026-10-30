import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/one_ui.dart';
import '../../services/safety/emergency_contacts.dart';

/// Up to five people outside the convoy to text when you raise an SOS or a
/// crash is detected. Stored on this phone only.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  List<EmergencyContact>? _contacts;

  @override
  void initState() {
    super.initState();
    EmergencyContacts.load().then((c) => mounted ? setState(() => _contacts = c) : null);
  }

  Future<void> _add() async {
    final contact = await editEmergencyContact(context);
    if (contact == null) return;
    final list = [...?_contacts, contact];
    await EmergencyContacts.save(list);
    setState(() => _contacts = list);
  }

  Future<void> _remove(EmergencyContact c) async {
    final list = [...?_contacts]..remove(c);
    await EmergencyContacts.save(list);
    setState(() => _contacts = list);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tones;
    final list = _contacts;
    return LargeTitleScaffold(
      title: 'Emergency contacts',
      subtitle: 'Texted with your location if you raise an SOS or a crash is detected',
      children: [
        const InfoBanner('Kept on this phone only. They don\'t need DriveSync.', icon: Icons.lock_rounded, tone: Tone.info),
        if (list != null)
          Section(children: [
            for (final e in list)
              Tile(
                leading: CircleAvatar(
                  backgroundColor: c.badSoft,
                  child: Text(e.name.isEmpty ? '?' : e.name[0].toUpperCase(), style: TextStyle(color: c.bad, fontWeight: FontWeight.w700)),
                ),
                title: e.name,
                subtitle: e.phone,
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: Icon(Icons.delete_outline_rounded, color: c.bad),
                  onPressed: () => _remove(e),
                ),
              ),
            if (list.length < 5)
              Tile(
                onTap: _add,
                leading: TileIcon(Icons.person_add_rounded, color: c.accent),
                title: 'Add a contact',
                titleStyle: Theme.of(context).textTheme.titleSmall?.copyWith(color: c.accent),
              ),
          ]),
      ],
    );
  }
}

Future<EmergencyContact?> editEmergencyContact(BuildContext context) async {
  final name = TextEditingController();
  final phone = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Emergency contact'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone with country code', hintText: '+91 98765 43210'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  final n = name.text.trim(), p = phone.text.trim();
  if (ok != true || n.isEmpty || p.replaceAll(RegExp(r'\D'), '').length < 7) return null;
  return EmergencyContact(n, p);
}
