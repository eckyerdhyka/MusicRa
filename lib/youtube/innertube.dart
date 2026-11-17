/// Minimal YouTube Music InnerTube client, ported from Convx's `innertube`
/// module. No account and no cookies: every request is anonymous and carries
/// only a visitorData id, like a logged-out music.youtube.com tab.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class YtClient {
  const YtClient({
    required this.name,
    required this.version,
    required this.id,
    required this.userAgent,
    this.osName,
    this.osVersion,
    this.deviceMake,
    this.deviceModel,
    this.androidSdkVersion,
  });

  final String name;
  final String version;

  /// Numeric client id, sent in the `X-YouTube-Client-Name` header.
  final String id;
  final String userAgent;
  final String? osName;
  final String? osVersion;
  final String? deviceMake;
  final String? deviceModel;
  final String? androidSdkVersion;

  Map<String, dynamic> context({required String hl, required String gl, String? visitorData}) => {
        'client': {
          'clientName': name,
          'clientVersion': version,
          if (osName != null) 'osName': osName,
          if (osVersion != null) 'osVersion': osVersion,
          if (deviceMake != null) 'deviceMake': deviceMake,
          if (deviceModel != null) 'deviceModel': deviceModel,
          if (androidSdkVersion != null) 'androidSdkVersion': androidSdkVersion,
          'hl': hl,
          'gl': gl,
          if (visitorData != null) 'visitorData': visitorData,
        },
        'request': {'internalExperimentFlags': <String>[], 'useSsl': true},
        'user': {'lockedSafetyMode': false},
      };

  static const _webUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0';

  /// music.youtube.com web client: search, browse, next, suggestions.
  static const webRemix = YtClient(
    name: 'WEB_REMIX',
    version: '1.20260213.01.00',
    id: '67',
    userAgent: _webUa,
  );

  /// Primary stream client in Convx: no PoToken, direct (unciphered) URLs.
  static const androidVr143 = YtClient(
    name: 'ANDROID_VR',
    version: '1.43.32',
    id: '28',
    userAgent:
        'com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)',
    osName: 'Android',
    osVersion: '12',
    deviceMake: 'Oculus',
    deviceModel: 'Quest 3',
    androidSdkVersion: '32',
  );

  static const androidVr161 = YtClient(
    name: 'ANDROID_VR',
    version: '1.61.48',
    id: '28',
    userAgent:
        'com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)',
    osName: 'Android',
    osVersion: '12',
    deviceMake: 'Oculus',
    deviceModel: 'Quest 3',
    androidSdkVersion: '32',
  );

  static const visionOs = YtClient(
    name: 'VISIONOS',
    version: '0.1',
    id: '101',
    userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
    osName: 'visionOS',
    osVersion: '1.3.21O771',
    deviceMake: 'Apple',
    deviceModel: 'RealityDevice14,1',
  );

  static const ios = YtClient(
    name: 'IOS',
    version: '21.03.1',
    id: '5',
    userAgent: 'com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)',
    osVersion: '18.2.22C152',
  );

  /// Stream clients in the order Convx tries them.
  static const streamChain = [androidVr143, visionOs, ios, androidVr161];
}

class InnerTubeException implements Exception {
  InnerTubeException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => 'InnerTubeException($statusCode): $message';
}

class InnerTube {
  InnerTube({http.Client? client, this.hl = 'id', this.gl = 'ID'})
      : _http = client ?? http.Client();

  static const origin = 'https://music.youtube.com';
  static const _api = '$origin/youtubei/v1/';

  final http.Client _http;
  final String hl;
  final String gl;

  String? visitorData;
  Future<String?>? _visitorFuture;

  /// Fetches an anonymous visitor id from `sw.js_data` (same as Convx).
  Future<String?> ensureVisitorData() {
    if (visitorData != null) return Future.value(visitorData);
    return _visitorFuture ??= _loadVisitorData().whenComplete(() => _visitorFuture = null);
  }

  Future<String?> _loadVisitorData() async {
    try {
      final res = await _http.get(Uri.parse('$origin/sw.js_data'), headers: {
        'User-Agent': YtClient.webRemix.userAgent,
        'Referer': '$origin/',
      }).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      var body = res.body;
      if (body.startsWith(")]}'")) body = body.substring(4);
      final root = jsonDecode(body);
      final candidates = (root as List)[0][2] as List;
      final re = RegExp(r'^Cg[ts]');
      for (final c in candidates) {
        if (c is String && re.hasMatch(c)) return visitorData = c;
      }
    } catch (_) {
      // Requests still work without a visitor id, just less localised.
    }
    return null;
  }

  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body, {
    YtClient client = YtClient.webRemix,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final vd = await ensureVisitorData();
    final uri = Uri.parse('$_api$endpoint').replace(queryParameters: {
      'prettyPrint': 'false',
      ...?query,
    });
    final payload = {
      'context': client.context(hl: hl, gl: gl, visitorData: vd),
      ...body,
    };
    final headers = {
      'Content-Type': 'application/json',
      'User-Agent': client.userAgent,
      'X-Goog-Api-Format-Version': '1',
      'X-YouTube-Client-Name': client.id,
      'X-YouTube-Client-Version': client.version,
      'X-Origin': origin,
      'Referer': '$origin/',
      if (vd != null) 'X-Goog-Visitor-Id': vd,
    };

    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final res = await _http
            .post(uri, headers: headers, body: jsonEncode(payload))
            .timeout(timeout);
        if (res.statusCode == 200) {
          return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        }
        final retryable = res.statusCode == 429 || res.statusCode >= 500;
        if (!retryable || attempt >= 3) {
          throw InnerTubeException('HTTP ${res.statusCode} on $endpoint', res.statusCode);
        }
      } on TimeoutException {
        if (attempt >= 2) rethrow;
      } on http.ClientException {
        if (attempt >= 3) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt * attempt));
    }
  }

  Future<Map<String, dynamic>> search({String? query, String? params, String? continuation}) =>
      post(
        'search',
        {if (query != null) 'query': query, if (params != null) 'params': params},
        query: continuation == null ? null : {'continuation': continuation, 'ctoken': continuation},
      );

  Future<Map<String, dynamic>> browse({String? browseId, String? params, String? continuation}) =>
      post('browse', {
        if (browseId != null) 'browseId': browseId,
        if (params != null) 'params': params,
        if (continuation != null) 'continuation': continuation,
      });

  Future<Map<String, dynamic>> next({
    String? videoId,
    String? playlistId,
    String? params,
    String? continuation,
  }) =>
      post('next', {
        if (videoId != null) 'videoId': videoId,
        if (playlistId != null) 'playlistId': playlistId,
        if (params != null) 'params': params,
        if (continuation != null) 'continuation': continuation,
        'isAudioOnly': true,
        'enablePersistentPlaylistPanel': true,
        'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
      });

  Future<Map<String, dynamic>> suggestions(String input) =>
      post('music/get_search_suggestions', {'input': input});

  Future<Map<String, dynamic>> player(String videoId, YtClient client) => post(
        'player',
        {
          'videoId': videoId,
          'contentCheckOk': true,
          'racyCheckOk': true,
        },
        client: client,
        timeout: const Duration(seconds: 8),
      );

  /// True when a stream URL answers a HEAD request, i.e. it is not blocked.
  Future<bool> validateUrl(String url, String userAgent) async {
    try {
      final req = http.Request('HEAD', Uri.parse(url))..headers['User-Agent'] = userAgent;
      final res = await _http.send(req).timeout(const Duration(seconds: 6));
      await res.stream.drain<void>();
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  void close() => _http.close();
}
