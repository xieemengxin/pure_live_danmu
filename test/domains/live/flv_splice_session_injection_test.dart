import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/domains/live/data/stream/flv_splice_relay.dart';

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

Uint8List flvHeader() => Uint8List.fromList([0x46, 0x4c, 0x56, 1, 5, 0, 0, 0, 9, 0, 0, 0, 0]);

const sps = [0x67, 100, 0, 51, 0xac, 0x52];
const ppsA = [0x68, 0xee, 0x17, 0x2c];
const ppsB = [0x68, 0xea, 0x82, 0x72, 0xc0];

Uint8List config(List<int> pps, int ts) =>
    tag(9, ts, [0x17, 0, 0, 0, 0, 1, 100, 0, 51, 0xff, 0xe1, 0, sps.length, ...sps, 1, 0, pps.length, ...pps]);
Uint8List keyframe(int ts) => tag(9, ts, [0x17, 1, 0, 0, 0, 0, 0, 0, 3, 0x65, 0x88, 0x84]);
Uint8List inter(int ts) => tag(9, ts, [0x27, 1, 0, 0, 0, 0, 0, 0, 3, 0x41, 0x9a, 0x02]);
Uint8List audio(int ts) => tag(8, ts, [0xaf, 1, 0x21]);

class _ListReader implements FlvTagReader {
  _ListReader(this._packets);
  final List<Uint8List> _packets;
  int _index = 0;
  bool cancelled = false;

  @override
  Future<Uint8List?> next() async => _index < _packets.length ? _packets[_index++] : null;

  @override
  Future<void> cancel() async => cancelled = true;
}

List<int> payload(Uint8List tag) => tag.sublist(16, tag.length - 4);

void main() {
  test('a changed sequence header on the same connection gets its parameter sets repeated in-band', () async {
    final upstream = _ListReader([
      flvHeader(),
      config(ppsA, 0),
      keyframe(0),
      inter(33),
      audio(40),
      config(ppsB, 66),
      keyframe(66),
      inter(100),
    ]);
    final emitted = <Uint8List>[];
    final session = FlvSpliceSession(
      initial: FlvLeasedSource(Uri.parse('https://al.flv.huya.com/a.flv')),
      open: (_) async => upstream,
      renew: (current) async => throw StateError('no renewal expected'),
      emit: emitted.add,
    );
    await session.run();

    expect(emitted, hasLength(8));
    expect(session.injectedParameterSets, 1);
    // Only the keyframe after the changed header grows, by SPS + new PPS.
    expect(payload(emitted[2]), [0, 0, 0, 3, 0x65, 0x88, 0x84]);
    expect(payload(emitted[6]), [
      0,
      0,
      0,
      sps.length,
      ...sps,
      0,
      0,
      0,
      ppsB.length,
      ...ppsB,
      0,
      0,
      0,
      3,
      0x65,
      0x88,
      0x84,
    ]);
    expect(payload(emitted[7]), [0, 0, 0, 3, 0x41, 0x9a, 0x02]);
    expect(FlvTag.timestamp(emitted[6]), 66);
  });

  test('a renewed connection with other parameter sets is spliced and injected', () async {
    final first = _ListReader([flvHeader(), config(ppsA, 0), keyframe(0), inter(33), inter(66)]);
    // The renewed connection starts at an earlier keyframe on the same timeline
    // and re-publishes with another PPS.
    final second = _ListReader([
      flvHeader(),
      config(ppsB, 0),
      keyframe(0),
      inter(33),
      inter(66),
      keyframe(100),
      inter(133),
    ]);
    // After the renewed connection ends the session tries once more; an empty
    // upstream then ends the session.
    final readers = <_ListReader>[first, second, _ListReader(const [])];
    var opened = 0;
    final emitted = <Uint8List>[];
    final session = FlvSpliceSession(
      initial: FlvLeasedSource(Uri.parse('https://al.flv.huya.com/a.flv')),
      open: (_) async => readers[opened++],
      renew: (current) async => FlvLeasedSource(Uri.parse('https://al.flv.huya.com/b.flv')),
      emit: emitted.add,
    );
    await session.run();

    expect(opened, 3);
    expect(session.switches, 1);
    expect(session.injectedParameterSets, 1);
    final video = emitted.where((p) => p.length > 11 && (p[0] & 0x1f) == 9).toList();
    // header, configA, key0, inter33, inter66, then configB + key100 (+ inter133)
    expect(video.map(FlvTag.timestamp).toList(), [0, 0, 33, 66, 100, 100, 133]);
    expect(FlvTag.isVideoConfig(video[4]), isTrue);
    expect(payload(video[5]).sublist(0, 4 + sps.length + 4 + ppsB.length), [
      0,
      0,
      0,
      sps.length,
      ...sps,
      0,
      0,
      0,
      ppsB.length,
      ...ppsB,
    ]);
  });

  test('a failed initial open renews the URL once before giving up', () async {
    final renewed = _ListReader([flvHeader(), config(ppsA, 0), keyframe(0), inter(33)]);
    final attempts = <String>[];
    final emitted = <Uint8List>[];
    final session = FlvSpliceSession(
      initial: FlvLeasedSource(Uri.parse('https://al.flv.huya.com/expired.flv')),
      open: (url) async {
        attempts.add(url.path);
        if (attempts.length == 1) throw const HttpException('FLV upstream answered 403');
        return renewed;
      },
      renew: (current) async => FlvLeasedSource(Uri.parse('https://al.flv.huya.com/fresh.flv')),
      emit: emitted.add,
    );
    await session.run();

    expect(attempts.take(2).toList(), ['/expired.flv', '/fresh.flv']);
    expect(emitted, hasLength(4));
  });

  test('injection can be switched off', () async {
    final upstream = _ListReader([flvHeader(), config(ppsA, 0), keyframe(0), config(ppsB, 66), keyframe(66)]);
    final emitted = <Uint8List>[];
    final session = FlvSpliceSession(
      initial: FlvLeasedSource(Uri.parse('https://al.flv.huya.com/a.flv')),
      open: (_) async => upstream,
      renew: (current) async => throw StateError('no renewal expected'),
      emit: emitted.add,
      injectParameterSets: false,
    );
    await session.run();
    expect(session.injectedParameterSets, 0);
    expect(payload(emitted[4]), [0, 0, 0, 3, 0x65, 0x88, 0x84]);
  });
}
