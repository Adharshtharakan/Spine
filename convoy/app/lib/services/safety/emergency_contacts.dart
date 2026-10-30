import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Someone outside the convoy to tell when you need help. Kept on this
/// phone only; never uploaded.
class EmergencyContact {
  const EmergencyContact(this.name, this.phone);
  final String name;
  final String phone;

  Map<String, String> toJson() => {'name': name, 'phone': phone};
}

abstract final class EmergencyContacts {
  static const _key = 'emergency_contacts';

  static Future<List<EmergencyContact>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final c in jsonDecode(raw) as List) EmergencyContact(c['name'] as String, c['phone'] as String),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<EmergencyContact> contacts) async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final c in contacts.take(5)) c.toJson()]));

  /// Opens the SMS app with the message ready to send to every contact.
  /// Android and iOS do not let apps send texts silently, so this is the
  /// fallback when the Worker's SMS relay isn't configured.
  static Future<bool> composeSms(List<EmergencyContact> contacts, String body) async {
    if (contacts.isEmpty) return false;
    final to = contacts.map((c) => c.phone.replaceAll(RegExp(r'[\s()-]'), '')).join(',');
    return launchUrl(Uri(scheme: 'sms', path: to, queryParameters: {'body': body}));
  }

  static Future<bool> call(EmergencyContact c) => launchUrl(Uri(scheme: 'tel', path: c.phone));

  /// The map link included in SOS texts.
  static String mapLink(double lat, double lng) =>
      'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
}
