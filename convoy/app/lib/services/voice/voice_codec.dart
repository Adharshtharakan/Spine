import 'dart:convert';
import 'dart:typed_data';

/// Telephone-quality voice for push-to-talk over the Realtime channel:
/// 16 kHz microphone PCM is halved to 8 kHz and G.711 µ-law encoded, one
/// byte per sample: 8 KB/s, about 11 KB/s as base64 text. Light enough for
/// a weak mobile signal and a free Supabase plan, clear enough for a CB-style
/// channel.
abstract final class VoiceCodec {
  static const micRate = 16000;
  static const wireRate = 8000;

  /// One frame of audio per message: 200 ms.
  static const frameMs = 200;
  static const micFrameBytes = micRate * frameMs ~/ 1000 * 2;

  static const _bias = 0x84;
  static const _clip = 32635;

  static final Uint8List _expLut = () {
    final t = Uint8List(256);
    for (var i = 1; i < 256; i++) {
      var e = 0;
      while ((i >> (e + 1)) > 0) {
        e++;
      }
      t[i] = e;
    }
    return t;
  }();

  static int encodeSample(int sample) {
    var s = sample;
    final sign = s < 0 ? 0x80 : 0;
    if (s < 0) s = -s;
    if (s > _clip) s = _clip;
    s += _bias;
    final exponent = _expLut[(s >> 7) & 0xFF];
    final mantissa = (s >> (exponent + 3)) & 0x0F;
    return ~(sign | (exponent << 4) | mantissa) & 0xFF;
  }

  static int decodeSample(int ulaw) {
    final u = ~ulaw & 0xFF;
    final exponent = (u >> 4) & 0x07;
    final t = (((u & 0x0F) << 3) + _bias) << exponent;
    return (u & 0x80) != 0 ? _bias - t : t - _bias;
  }

  /// 16-bit little-endian PCM at [micRate] → base64 µ-law at [wireRate].
  static String encodeFrame(Uint8List pcm16le) {
    final samples = pcm16le.buffer.asByteData(pcm16le.offsetInBytes, pcm16le.lengthInBytes);
    final n = pcm16le.lengthInBytes ~/ 4; // two 16-bit samples per output sample
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      final a = samples.getInt16(i * 4, Endian.little);
      final b = samples.getInt16(i * 4 + 2, Endian.little);
      out[i] = encodeSample((a + b) >> 1);
    }
    return base64Encode(out);
  }

  /// base64 µ-law → 16-bit samples at [wireRate].
  static Int16List decodeFrame(String b64) {
    final bytes = base64Decode(b64);
    final out = Int16List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      out[i] = decodeSample(bytes[i]);
    }
    return out;
  }
}
