import 'dart:typed_data';

/// Repeats changed H.264 parameter sets in-band so a hardware decoder follows a
/// mid-stream re-publish.
///
/// Huya re-sends an AVC sequence header when the broadcaster's encoder restarts
/// mid-stream; the PPS in it can differ while profile/level stay the same.
/// FFmpeg's VideoToolbox hwaccel only rebuilds its session when the SPS
/// profile/level bytes change and learns parameter sets delivered through the
/// container (extradata side data) without telling the hardware session, so
/// every frame after such a header fails, mpv falls back to a software decoder
/// built from the stale original extradata, and the picture freezes and then
/// turns grey until the room is reopened (measured on the app's own libmpv
/// 0.36 / FFmpeg 6.0 build, 2026-10-09).
///
/// Parameter sets carried inside the access unit are handled by both decoders:
/// with the new SPS and PPS prepended to the IDR that follows the changed
/// sequence header, the same build decodes straight through without a frame
/// lost. The injector therefore watches every AVC sequence header; when the set
/// of SPS/PPS NAL units differs from the one currently in force it prepends
/// those units (length-prefixed, as the stream's `lengthSizeMinusOne` declares)
/// to the next AVC NALU tag. Every other tag is returned unchanged, as the same
/// instance.
class FlvParamSetInjector {
  int _lengthSize = 4;
  List<Uint8List> _paramSets = const <Uint8List>[];
  bool _pending = false;
  int _configChanges = 0;
  int _injectedTags = 0;

  /// Sequence headers whose parameter sets differed from the ones in force.
  int get configChanges => _configChanges;

  /// NALU tags that received an in-band copy of the parameter sets.
  int get injectedTags => _injectedTags;

  /// [tag] is one complete FLV tag including its trailing PreviousTagSize.
  Uint8List rewrite(Uint8List tag) {
    if (tag.length < 16 + 4 || (tag[0] & 0x1f) != 9) return tag;
    final flags = tag[11];
    // Enhanced FLV (FourCC video) and non-AVC codecs are left to the decoder.
    if ((flags & 0x80) != 0 || (flags & 0x0f) != 7) return tag;
    final packetType = tag[12];
    if (packetType == 0) {
      _observeConfig(tag);
      return tag;
    }
    if (packetType != 1 || !_pending) return tag;
    _pending = false;
    return _inject(tag);
  }

  void _observeConfig(Uint8List tag) {
    final record = Uint8List.sublistView(tag, 16, tag.length - 4);
    final parsed = _parseAvcC(record);
    if (parsed == null) return;
    final changed = _paramSets.isNotEmpty && !_sameSets(_paramSets, parsed.units);
    _paramSets = parsed.units;
    _lengthSize = parsed.lengthSize;
    if (changed) {
      _configChanges++;
      _pending = true;
    }
  }

  Uint8List _inject(Uint8List tag) {
    final dataSize = (tag[1] << 16) | (tag[2] << 8) | tag[3];
    if (11 + dataSize + 4 != tag.length || dataSize < 5) return tag;
    var extra = 0;
    for (final unit in _paramSets) {
      extra += _lengthSize + unit.length;
    }
    final newSize = dataSize + extra;
    if (newSize > 0xffffff) return tag;
    final out = Uint8List(11 + newSize + 4);
    // Tag header, video flags, AVCPacketType and composition time are kept.
    out.setRange(0, 16, tag);
    out[1] = (newSize >> 16) & 0xff;
    out[2] = (newSize >> 8) & 0xff;
    out[3] = newSize & 0xff;
    var p = 16;
    for (final unit in _paramSets) {
      for (var i = _lengthSize - 1; i >= 0; i--) {
        out[p++] = (unit.length >> (8 * i)) & 0xff;
      }
      out.setRange(p, p + unit.length, unit);
      p += unit.length;
    }
    out.setRange(p, 11 + newSize, tag, 16);
    ByteData.sublistView(out).setUint32(11 + newSize, 11 + newSize);
    _injectedTags++;
    return out;
  }

  /// SPS then PPS units of an AVCDecoderConfigurationRecord, or null when the
  /// record is malformed (then nothing is injected and nothing is remembered).
  static ({int lengthSize, List<Uint8List> units})? _parseAvcC(Uint8List record) {
    if (record.length < 7 || record[0] != 1) return null;
    final lengthSize = (record[4] & 0x03) + 1;
    final units = <Uint8List>[];
    var p = 5;
    final numSps = record[p++] & 0x1f;
    for (var i = 0; i < numSps; i++) {
      if (p + 2 > record.length) return null;
      final length = (record[p] << 8) | record[p + 1];
      p += 2;
      if (length == 0 || p + length > record.length) return null;
      units.add(Uint8List.fromList(record.sublist(p, p + length)));
      p += length;
    }
    if (p >= record.length) return null;
    final numPps = record[p++];
    for (var i = 0; i < numPps; i++) {
      if (p + 2 > record.length) return null;
      final length = (record[p] << 8) | record[p + 1];
      p += 2;
      if (length == 0 || p + length > record.length) return null;
      units.add(Uint8List.fromList(record.sublist(p, p + length)));
      p += length;
    }
    if (units.isEmpty) return null;
    return (lengthSize: lengthSize, units: units);
  }

  static bool _sameSets(List<Uint8List> a, List<Uint8List> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }
}
