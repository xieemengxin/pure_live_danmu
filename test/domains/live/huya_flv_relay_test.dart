import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart' show kMediaKitCustomInputKey;
import 'package:pure_live/domains/live/data/stream/flv_splice_relay.dart';
import 'package:pure_live/domains/live/data/stream/huya_flv_relay.dart';
import 'package:pure_live/domains/live/domain/live_player_facade.dart';

PlayerSource line(String url) => PlayerSource(
  id: SourceId('live-$url'),
  uri: Uri.parse(url),
  type: SourceType.live,
  headers: SourceHeaders(const {'user-agent': 'probe'}),
);

void main() {
  const native = 'https://al.flv.huya.com/src/123-abc.flv?wsSecret=x&wsTime=68e7&ctype=huya_pc_exe&t=100&codec=264';
  const hls = 'https://al.hls.huya.com/src/123-abc.m3u8?wsSecret=x';
  const douyu = 'https://tx2play1.douyucdn.cn/live/1.flv?expire=300';

  group('HuyaFlvRelay.appliesTo', () {
    test('matches plain FLV on huya.com hosts only', () {
      expect(HuyaFlvRelay.appliesTo(Uri.parse(native)), isTrue);
      expect(HuyaFlvRelay.appliesTo(Uri.parse('http://tx.flv.huya.com/src/1.FLV?a=1')), isTrue);
      expect(HuyaFlvRelay.appliesTo(Uri.parse(hls)), isFalse);
      expect(HuyaFlvRelay.appliesTo(Uri.parse(douyu)), isFalse);
      expect(HuyaFlvRelay.appliesTo(Uri.parse('https://huya.com.evil.example/x.flv')), isFalse);
      expect(HuyaFlvRelay.appliesTo(Uri(scheme: 'owned', path: 'huya/1')), isFalse);
    });
  });

  group('HuyaFlvRelay.intercept', () {
    test('turns Huya FLV lines into custom inputs and keeps everything else', () async {
      final sources = [line(native), line(hls), line(douyu)];
      final result = await HuyaFlvRelay.intercept(sources, null);

      expect(result, hasLength(3));
      expect(result[0].id, sources[0].id);
      expect(result[0].uri, sources[0].uri);
      expect(result[0].protocol, SourceProtocol.custom);
      expect(result[0].metadata[kMediaKitCustomInputKey], isA<Function>());
      expect(identical(result[1], sources[1]), isTrue);
      expect(identical(result[2], sources[2]), isTrue);
    });

    test('an already owned source is not wrapped twice', () async {
      final owned = line(native).copyWith(protocol: SourceProtocol.custom, metadata: {kMediaKitCustomInputKey: 1});
      final result = await HuyaFlvRelay.intercept([owned], null);
      expect(identical(result.single, owned), isTrue);
    });
  });

  group('HuyaFlvRelay.renewer', () {
    test('asks the resolver for the same line and takes its preferred pick', () async {
      PlaybackSourceRefreshRequest? seen;
      Future<PlaybackSourceRefreshResult> resolver(PlaybackSourceRefreshRequest request) async {
        seen = request;
        return const PlaybackSourceRefreshResult(
          urls: ['https://tx.flv.huya.com/new-tx.flv', 'https://al.flv.huya.com/new-al.flv'],
          preferredLineIndex: 1,
        );
      }

      final renew = HuyaFlvRelay.renewer(
        resolver: resolver,
        lineIndex: 1,
        lines: const ['https://tx.flv.huya.com/old-tx.flv', native],
      );
      final next = await renew(FlvLeasedSource(Uri.parse(native)));

      expect(next.url.toString(), 'https://al.flv.huya.com/new-al.flv');
      expect(next.refreshAt, isNull);
      expect(seen?.currentLineIndex, 1);
      expect(seen?.advanceLine, isFalse);
      expect(seen?.currentUrl, native);
    });

    test('without a resolver the current URL is reused', () async {
      final renew = HuyaFlvRelay.renewer(resolver: null, lineIndex: 0, lines: const [native]);
      expect((await renew(FlvLeasedSource(Uri.parse(native)))).url.toString(), native);
    });

    test('an empty resolution is an error rather than a silent reconnect', () async {
      Future<PlaybackSourceRefreshResult> resolver(PlaybackSourceRefreshRequest request) async =>
          const PlaybackSourceRefreshResult(urls: [], preferredLineIndex: 0);
      final renew = HuyaFlvRelay.renewer(resolver: resolver, lineIndex: 0, lines: const [native]);
      expect(() => renew(FlvLeasedSource(Uri.parse(native))), throwsStateError);
    });
  });
}
