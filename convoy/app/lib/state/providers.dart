import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/social.dart';
import '../data/models/trip.dart';
import '../data/repositories/trip_repository.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});

final tripRepositoryProvider = Provider((ref) => TripRepository(ref.watch(supabaseProvider)));
final guidelineRepositoryProvider = Provider((ref) => GuidelineRepository(ref.watch(supabaseProvider)));
final entitlementRepositoryProvider = Provider((ref) => EntitlementRepository(ref.watch(supabaseProvider)));

final acceptedGuidelinesProvider = FutureProvider<bool>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(guidelineRepositoryProvider).hasAcceptedCurrent();
});

final verifiedPartyProvider = FutureProvider<bool>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(guidelineRepositoryProvider).isVerifiedParty();
});

final entitlementProvider = FutureProvider<Entitlement>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(entitlementRepositoryProvider).mine();
});

final myTripsProvider = FutureProvider<List<Trip>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(tripRepositoryProvider).myTrips();
});

final myJoinRequestsProvider = FutureProvider<List<JoinRequest>>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(tripRepositoryProvider).myJoinRequests();
});
