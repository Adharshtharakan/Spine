import '../../core/config/env.dart';

/// Invite links (`https://<worker>/j/K7Q2M9XP`), the app's own scheme
/// (`drivesync://join/K7Q2M9XP`) and bare codes all lead to the same join.
abstract final class InviteLinks {
  static final _code = RegExp(r'^[A-Z0-9]{6,12}$');

  static String? link(String code) => Env.inviteBaseUrl.isEmpty ? null : '${Env.inviteBaseUrl}/j/$code';

  /// Shared to WhatsApp and friends.
  static String shareText(String tripTitle, String code) {
    final url = link(code);
    return url == null
        ? 'Join "$tripTitle" on DriveSync with invite code $code'
        : 'Join "$tripTitle" on DriveSync: $url (invite code $code)';
  }

  /// The invite code in a scanned QR, a tapped link or pasted text.
  static String? codeFrom(String text) {
    final t = text.trim();
    final uri = Uri.tryParse(t);
    if (uri != null && uri.hasScheme) {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      String? candidate;
      if (uri.scheme == 'drivesync' && uri.host == 'join' && segs.isNotEmpty) candidate = segs.first;
      if ((uri.scheme == 'https' || uri.scheme == 'http') && segs.length == 2 && segs.first == 'j') candidate = segs[1];
      if (candidate == null) return null;
      final c = candidate.toUpperCase();
      return _code.hasMatch(c) ? c : null;
    }
    final c = t.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    return _code.hasMatch(c) ? c : null;
  }
}
