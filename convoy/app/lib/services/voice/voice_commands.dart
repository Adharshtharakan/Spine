import '../../data/models/convoy_event.dart';

/// What the driver asked for, parsed from a spoken sentence.
sealed class VoiceCommand {
  const VoiceCommand();
}

/// "Tell everyone fuel stop in 10 minutes."
class Broadcast extends VoiceCommand {
  const Broadcast(this.text);
  final String text;
}

class WhereIsLead extends VoiceCommand {
  const WhereIsLead();
}

/// "Where is Priya?" — [name] as spoken; matched against the roster.
class WhereIs extends VoiceCommand {
  const WhereIs(this.name);
  final String name;
}

class NextStop extends VoiceCommand {
  const NextStop();
}

class RaiseSos extends VoiceCommand {
  const RaiseSos();
}

class ReportHazard extends VoiceCommand {
  const ReportHazard(this.type);
  final HazardType type;
}

class ReadyToGo extends VoiceCommand {
  const ReadyToGo();
}

class RegroupHere extends VoiceCommand {
  const RegroupHere();
}

class RunningLate extends VoiceCommand {
  const RunningLate(this.minutes);
  final int minutes;
}

class Unknown extends VoiceCommand {
  const Unknown(this.heard);
  final String heard;
}

/// Turns a recognised sentence into a [VoiceCommand]. Deliberately small and
/// predictable: a fixed set of phrasings drivers can learn, no guessing.
abstract final class VoiceCommands {
  static final _wake = RegExp(r'^(hey|hi|ok|okay)\s+drive\s*sync\b');

  /// True when [heard] starts with the wake phrase ("Hey DriveSync").
  static bool hasWakeWord(String heard) => _wake.hasMatch(heard.toLowerCase().trim());

  static VoiceCommand parse(String heard) {
    // Same text twice: [original] keeps the driver's casing for messages,
    // [s] is lower-cased for matching; both have the same length.
    final original = heard
        .trim()
        .replaceFirst(RegExp(r'^(hey|hi|ok|okay)\s+drive\s*sync[\s,.!]*', caseSensitive: false), '')
        .replaceAll(RegExp(r'[.!?]+$'), '')
        .trim();
    final s = original.toLowerCase();

    final tell = RegExp(r'^(?:tell|message|send(?: a message)? to|say to|let)\s+(?:everyone|everybody|all|the convoy|the group|the others)(?:\s+know)?(?:\s+that)?[\s,:]+(.+)$')
        .firstMatch(s);
    if (tell != null) return Broadcast(_sentence(original.substring(original.length - tell.group(1)!.length)));
    final send = RegExp(r'^send\s+(.+)$').firstMatch(s);
    if (send != null) return Broadcast(_sentence(original.substring(original.length - send.group(1)!.length)));

    if (RegExp(r'\b(sos|emergency|mayday|i need help|we need help|help me)\b').hasMatch(s)) return const RaiseSos();

    final hazard = RegExp(r'\b(pothole|police|cops|speed trap|accident|crash|flood(?:ed)?|water on the road)\b').firstMatch(s);
    if (hazard != null && RegExp(r'\b(report|there(?:.s| is)|watch out|warning|mark)\b').hasMatch(s)) {
      return ReportHazard(switch (hazard.group(1)) {
        'pothole' => HazardType.pothole,
        'police' || 'cops' || 'speed trap' => HazardType.police,
        'accident' || 'crash' => HazardType.accident,
        _ => HazardType.flood,
      });
    }

    if (RegExp(r'\b(where(?:.s| is)|how far(?: ahead)? is|find)\s+the\s+lead').hasMatch(s) || s == 'lead' || s.contains('lead car')) {
      return const WhereIsLead();
    }
    if (RegExp(r'\b(next stop|how far to go|when do we (?:get there|arrive)|how long to)').hasMatch(s)) return const NextStop();
    if (RegExp(r"\b(i.?m ready|we.?re ready|ready to go|i am ready|we are ready)\b").hasMatch(s)) return const ReadyToGo();
    if (RegExp(r'\b(regroup|wait for me|meet here|gather here)\b').hasMatch(s)) return const RegroupHere();

    final late = RegExp(r'running\s+(\w+(?:\s\w+)?)\s+minutes?\s+late').firstMatch(s);
    if (late != null) {
      final n = int.tryParse(late.group(1)!) ?? _numbers[late.group(1)!];
      if (n != null && n > 0 && n <= 180) return RunningLate(n);
    }

    final where = RegExp(r'^where(?:.s| is| are)\s+(.+)$').firstMatch(s);
    if (where != null) return WhereIs(where.group(1)!.replaceFirst(RegExp(r'^the\s+'), ''));
    return Unknown(heard);
  }

  static String _sentence(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1);
  }

  static const _numbers = {
    'five': 5, 'ten': 10, 'fifteen': 15, 'twenty': 20, 'twenty five': 25, 'thirty': 30,
    'forty': 40, 'forty five': 45, 'fifty': 50, 'sixty': 60, 'ninety': 90,
  };
}
