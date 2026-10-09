import 'dart:async';

import 'package:dio/dio.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart' show kMediaKitCustomInputKey;
import 'package:pure_live/core/player/core/playback_input_lease.dart';
import 'package:pure_live/core/player/core/playback_proxy_policy.dart';
import 'package:pure_live/core/player/kernel/owned_input_opener.dart' show OwnedInputRecipe;
import 'package:pure_live/domains/live/data/stream/flv_splice_relay.dart';
import 'package:pure_live/domains/live/domain/live_player_facade.dart';

/// Routes Huya FLV lines through a loopback [FlvSpliceRelay].
///
/// Two things the native connection cannot do for a Huya room:
///
/// * A broadcaster re-publishing mid-stream sends a new AVC sequence header
///   with a changed PPS. The relay's session repeats the parameter sets
///   in-band so the hardware decoder follows (see `FlvParamSetInjector`);
///   fed directly, the decoder freezes and the picture turns grey.
/// * The signed URL stops admitting new connections 299 s after it was
///   issued. The relay keeps the player on one continuous local stream and,
///   when the upstream connection ends, renews the URL through the play's
///   [PlaybackSourceResolver] and splices the new connection at a keyframe.
///
/// Only the sources handed to the kernel change: ids and URIs are kept, so
/// the room's line list, line switching and recording are untouched.
abstract final class HuyaFlvRelay {
  /// Plain FLV over HTTP(S) from a Huya CDN host.
  static bool appliesTo(Uri uri) {
    if (!const {'http', 'https'}.contains(uri.scheme.toLowerCase())) return false;
    final host = uri.host.toLowerCase();
    if (host != 'huya.com' && !host.endsWith('.huya.com')) return false;
    return uri.path.toLowerCase().endsWith('.flv');
  }

  /// A [FacadeSourceInterceptor]: every Huya FLV line becomes a custom-input
  /// source whose recipe starts a relay for that line when the kernel opens it.
  static Future<List<PlayerSource>> intercept(List<PlayerSource> sources, PlaybackSourceResolver? resolver) async {
    final lines = <String>[for (final source in sources) source.uri.toString()];
    return <PlayerSource>[
      for (var i = 0; i < sources.length; i++)
        if (sources[i].protocol != SourceProtocol.custom &&
            !sources[i].metadata.containsKey(kMediaKitCustomInputKey) &&
            appliesTo(sources[i].uri))
          sources[i].copyWith(
            protocol: SourceProtocol.custom,
            metadata: <String, Object?>{
              ...sources[i].metadata,
              kMediaKitCustomInputKey: recipe(
                url: sources[i].uri,
                headers: sources[i].headers?.values ?? const <String, String>{},
                renew: renewer(resolver: resolver, lineIndex: i, lines: lines),
              ),
            },
          )
        else
          sources[i],
    ];
  }

  /// Starts one relay per open; the lease closes it.
  static OwnedInputRecipe recipe({
    required Uri url,
    required Map<String, String> headers,
    required FlvSourceRenewer renew,
    String Function(Uri) findProxy = _currentProxy,
  }) {
    return (CancelToken cancel) async {
      if (cancel.isCancelled) throw cancel.cancelError!;
      final relay = await FlvSpliceRelay.start(
        FlvLeasedSource(url),
        renew: renew,
        headers: headers,
        findProxy: findProxy,
      );
      if (cancel.isCancelled) {
        await relay.close();
        throw cancel.cancelError!;
      }
      return PlaybackInputLease(relay.inputUri, relay.close, isUsable: () => !relay.isClosed);
    };
  }

  /// Asks the play's resolver for fresh lines and picks the one that
  /// corresponds to [lineIndex]; without a resolver the same URL is reused
  /// (a reconnect inside the credential's lifetime still works).
  static FlvSourceRenewer renewer({
    required PlaybackSourceResolver? resolver,
    required int lineIndex,
    required List<String> lines,
  }) {
    return (current) async {
      if (resolver == null) return FlvLeasedSource(current.url);
      final result = await resolver(
        PlaybackSourceRefreshRequest(
          currentLineIndex: lineIndex,
          advanceLine: false,
          currentUrl: lineIndex < lines.length ? lines[lineIndex] : current.url.toString(),
        ),
      );
      final urls = result.urls;
      if (urls.isEmpty) throw StateError('Huya relay: the resolver returned no line to renew with');
      final next = urls[result.preferredLineIndex.clamp(0, urls.length - 1)];
      return FlvLeasedSource(Uri.parse(next));
    };
  }

  static String _currentProxy(Uri _) => PlaybackProxyPolicy.currentDirective();
}
