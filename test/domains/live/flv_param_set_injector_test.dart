import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/data/stream/flv_param_set_injector.dart';
import 'package:pure_live/domains/live/data/stream/flv_splice_relay.dart' show FlvTag;

/// One complete FLV tag (header, data, PreviousTagSize).
Uint8List tag(int type, int timestamp, List<int> data) {
  final out = Uint8List(11 + data.length + 4);
  out[0] = type;
  out[1] = (data.length >> 16) & 0xff;
  out[2] = (data.length >> 8) & 0xff;
  out[3] = data.length & 0xff;
  out[4] = (timestamp >> 16) & 0xff;
  out[5] = (timestamp >> 8) & 0xff;
  out[6] = timestamp & 0xff;
  out[7] = (timestamp >> 24) & 0xff;
  out.setRange(11, 11 + data.length, data);
  ByteData.sublistView(out).setUint32(11 + data.length, 11 + data.length);
  return out;
}

Uint8List avcConfig(List<List<int>> sps, List<List<int>> pps, {int lengthSize = 4, int timestamp = 0}) {
  final record = <int>[1, sps.first[1], sps.first[2], sps.first[3], 0xfc | (lengthSize - 1), 0xe0 | sps.length];
  for (final unit in sps) {
    record.addAll([unit.length >> 8, unit.length & 0xff, ...unit]);
  }
  record.add(pps.length);
  for (final unit in pps) {
    record.addAll([unit.length >> 8, unit.length & 0xff, ...unit]);
  }
  return tag(9, timestamp, [0x17, 0, 0, 0, 0, ...record]);
}

List<int> lengthPrefixed(List<int> nal, {int lengthSize = 4}) => [
  for (var i = lengthSize - 1; i >= 0; i--) (nal.length >> (8 * i)) & 0xff,
  ...nal,
];

Uint8List avcFrame(List<List<int>> nals, {bool keyframe = true, int timestamp = 0, int cts = 0, int lengthSize = 4}) =>
    tag(9, timestamp, [
      keyframe ? 0x17 : 0x27,
      1,
      (cts >> 16) & 0xff,
      (cts >> 8) & 0xff,
      cts & 0xff,
      for (final nal in nals) ...lengthPrefixed(nal, lengthSize: lengthSize),
    ]);

const spsA = [0x67, 100, 0, 51, 0xac, 0x52, 0x14, 0x02];
const ppsA = [0x68, 0xee, 0x17, 0x2c];
const ppsB = [0x68, 0xea, 0x82, 0x72, 0xc0];
const idr = [0x65, 0x88, 0x84, 0x00, 0x11];
const sliceP = [0x41, 0x9a, 0x02];

void main() {
  group('FlvParamSetInjector', () {
    test('the first sequence header and unchanged repeats inject nothing', () {
      final injector = FlvParamSetInjector();
      final config = avcConfig([spsA], [ppsA]);
      final frame = avcFrame([idr]);
      expect(identical(injector.rewrite(config), config), isTrue);
      expect(identical(injector.rewrite(frame), frame), isTrue);
      expect(identical(injector.rewrite(avcConfig([spsA], [ppsA], timestamp: 3000)), config), isFalse);
      expect(identical(injector.rewrite(frame), frame), isTrue);
      expect(injector.configChanges, 0);
      expect(injector.injectedTags, 0);
    });

    test('a changed PPS is repeated in-band on the next NALU tag only', () {
      final injector = FlvParamSetInjector();
      injector.rewrite(avcConfig([spsA], [ppsA]));
      injector.rewrite(avcFrame([idr]));
      injector.rewrite(avcConfig([spsA], [ppsB], timestamp: 5000));
      final frame = avcFrame([idr], timestamp: 5000, cts: 50);
      final rewritten = injector.rewrite(frame);

      expect(identical(rewritten, frame), isFalse);
      expect(injector.configChanges, 1);
      expect(injector.injectedTags, 1);
      // Same tag header fields, grown DataSize, trailing size kept in sync.
      expect(FlvTag.type(rewritten), 9);
      expect(FlvTag.timestamp(rewritten), 5000);
      final dataSize = (rewritten[1] << 16) | (rewritten[2] << 8) | rewritten[3];
      expect(dataSize, 5 + (4 + spsA.length) + (4 + ppsB.length) + (4 + idr.length));
      expect(rewritten.length, 11 + dataSize + 4);
      expect(ByteData.sublistView(rewritten).getUint32(rewritten.length - 4), 11 + dataSize);
      expect(rewritten.sublist(11, 16), [0x17, 1, 0, 0, 50]);
      expect(rewritten.sublist(16, rewritten.length - 4), [...lengthPrefixed(spsA), ...lengthPrefixed(ppsB), ...lengthPrefixed(idr)]);
      // The following frames pass through untouched.
      final next = avcFrame([sliceP], keyframe: false, timestamp: 5016);
      expect(identical(injector.rewrite(next), next), isTrue);
      expect(injector.injectedTags, 1);
    });

    test('honours the declared NAL length size', () {
      final injector = FlvParamSetInjector();
      injector.rewrite(avcConfig([spsA], [ppsA], lengthSize: 2));
      injector.rewrite(avcConfig([spsA], [ppsB], lengthSize: 2));
      final rewritten = injector.rewrite(avcFrame([idr], lengthSize: 2));
      expect(rewritten.sublist(16, rewritten.length - 4), [
        ...lengthPrefixed(spsA, lengthSize: 2),
        ...lengthPrefixed(ppsB, lengthSize: 2),
        ...lengthPrefixed(idr, lengthSize: 2),
      ]);
    });

    test('audio, script, enhanced FLV and non-AVC video tags are untouched', () {
      final injector = FlvParamSetInjector();
      injector.rewrite(avcConfig([spsA], [ppsA]));
      injector.rewrite(avcConfig([spsA], [ppsB]));
      final audio = tag(8, 0, [0xaf, 1, 0x21, 0x10]);
      final script = tag(18, 0, List<int>.filled(24, 2));
      final enhanced = tag(9, 0, [0x91, 0x68, 0x76, 0x63, 0x31, 0, 0, 0, 1, 0]);
      final hevcLegacy = tag(9, 0, [0x1c, 1, 0, 0, 0, 0, 0, 0, 1, 0x26]);
      for (final other in [audio, script, enhanced, hevcLegacy]) {
        expect(identical(injector.rewrite(other), other), isTrue);
      }
      // The pending injection still lands on the next AVC NALU tag.
      expect(injector.rewrite(avcFrame([idr])).length, greaterThan(avcFrame([idr]).length));
    });

    test('a malformed sequence header is ignored', () {
      final injector = FlvParamSetInjector();
      injector.rewrite(avcConfig([spsA], [ppsA]));
      final broken = tag(9, 0, [0x17, 0, 0, 0, 0, 1, 100, 0, 51, 0xff, 0xe1, 0x00, 0x40, 0x67]);
      expect(identical(injector.rewrite(broken), broken), isTrue);
      final frame = avcFrame([idr]);
      expect(identical(injector.rewrite(frame), frame), isTrue);
      expect(injector.configChanges, 0);
    });
  });
}
