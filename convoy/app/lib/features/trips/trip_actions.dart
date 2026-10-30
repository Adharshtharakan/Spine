import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/trip.dart';
import '../../data/repositories/trip_repository.dart';
import '../../state/providers.dart';

/// Delete (organiser) or leave (everyone else) a trip, after confirming.
/// Returns true when the trip is gone from this user's list.
Future<bool> removeTrip(BuildContext context, WidgetRef ref, Trip trip) async {
  final owner = trip.ownerId == ref.read(supabaseProvider).auth.currentUser?.id;
  final c = context.tones;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(owner ? Icons.delete_forever_rounded : Icons.logout_rounded, color: c.bad, size: 32),
      title: Text(owner ? 'Delete "${trip.title}"?' : 'Leave "${trip.title}"?'),
      content: Text(owner
          ? 'This deletes the trip for everyone in it: the plan, chat, positions, checklists and requests. It can\'t be undone.'
          : 'You will disappear from the convoy map and stop receiving its updates. You can rejoin with the invite code.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.bad),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(owner ? 'Delete trip' : 'Leave trip'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    final repo = ref.read(tripRepositoryProvider);
    owner ? await repo.deleteTrip(trip.id) : await repo.leaveTrip(trip.id);
    ref.invalidate(myTripsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(owner ? 'Trip deleted' : 'You left the trip')));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not do that: ${friendlyError(e)}')));
    }
    return false;
  }
}
