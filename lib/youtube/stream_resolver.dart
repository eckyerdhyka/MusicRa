import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yte;

import 'innertube.dart';
import 'parsers.dart';

class AudioStream {
  const AudioStream({
    required this.url,
    required this.mimeType,
    required this.bitrate,
    required this.userAgent,
    required this.expiresAt,
    this.contentLength,
    this.source = 'innertube',
  });

  final String url;
  final String mimeType;
  final int bitrate;
  final int? contentLength;
  final String userAgent;
  final DateTime expiresAt;
  final String source;

  bool get isExpired => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)));

  /// File extension for downloads.
  String get extension => mimeType.contains('webm') ? 'webm' : 'm4a';
}

class StreamUnavailableException implements Exception {
  StreamUnavailableException(this.videoId, this.reason);

  final String videoId;
  final String reason;

  @override
  String toString() => 'Lagu tidak bisa diputar ($reason)';
}

/// Finds a playable audio-only URL, walking the same client chain as Convx
/// and finishing with youtube_explode as a last resort.
class StreamResolver {
  StreamResolver(this._tube);

  final InnerTube _tube;
  final Map<String, AudioStream> _cache = {};
  yte.YoutubeExplode? _yt;

  /// The client that last produced a working URL is tried first next time;
  /// YouTube tends to block a client per network ("confirm you're not a bot").
  YtClient? _preferred;

  Future<AudioStream> resolve(String videoId, {bool forceRefresh = false}) async {
    final cached = _cache[videoId];
    if (!forceRefresh && cached != null && !cached.isExpired) return cached;

    String lastReason = 'tidak ada format audio';
    final chain = [
      if (_preferred != null) _preferred!,
      ...YtClient.streamChain.where((c) => c != _preferred),
    ];
    for (final client in chain) {
      try {
        final json = await _tube.player(videoId, client);
        final status = digStr(json, ['playabilityStatus', 'status']);
        if (status != 'OK') {
          lastReason = digStr(json, ['playabilityStatus', 'reason']) ?? status ?? lastReason;
          continue;
        }
        final expiresIn = int.tryParse(
                '${dig(json, ['streamingData', 'expiresInSeconds']) ?? ''}') ??
            21600;
        final formats = ((dig(json, ['streamingData', 'adaptiveFormats']) as List?) ?? const [])
            .whereType<Map>()
            .where((f) =>
                (f['mimeType'] as String? ?? '').startsWith('audio/') &&
                f['url'] is String &&
                f['isDrc'] != true)
            .toList()
          ..sort((a, b) => ((b['bitrate'] as num?) ?? 0).compareTo((a['bitrate'] as num?) ?? 0));
        for (final f in formats.take(2)) {
          final url = f['url'] as String;
          if (!await _tube.validateUrl(url, client.userAgent)) continue;
          final stream = AudioStream(
            url: url,
            mimeType: f['mimeType'] as String,
            bitrate: (f['bitrate'] as num?)?.toInt() ?? 0,
            contentLength: int.tryParse('${f['contentLength'] ?? ''}'),
            userAgent: client.userAgent,
            expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
            source: client.name,
          );
          _preferred = client;
          return _cache[videoId] = stream;
        }
        lastReason = 'URL ditolak (${client.name})';
      } catch (e) {
        lastReason = e.toString();
      }
    }

    try {
      return _cache[videoId] = await _resolveWithExplode(videoId);
    } catch (e) {
      throw StreamUnavailableException(videoId, lastReason);
    }
  }

  Future<AudioStream> _resolveWithExplode(String videoId) async {
    final yt = _yt ??= yte.YoutubeExplode();
    final manifest = await yt.videos.streams.getManifest(videoId, ytClients: [
      yte.YoutubeApiClient.androidVr,
      yte.YoutubeApiClient.ios,
    ]);
    final audio = manifest.audioOnly.withHighestBitrate();
    return AudioStream(
      url: audio.url.toString(),
      mimeType: 'audio/${audio.container.name}',
      bitrate: audio.bitrate.bitsPerSecond,
      contentLength: audio.size.totalBytes,
      userAgent: YtClient.androidVr143.userAgent,
      expiresAt: DateTime.now().add(const Duration(hours: 5)),
      source: 'youtube_explode',
    );
  }

  void invalidate(String videoId) => _cache.remove(videoId);

  void close() => _yt?.close();
}
