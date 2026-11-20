import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicra/youtube/innertube.dart';
import 'package:musicra/youtube/youtube_repository.dart';

/// Every InnerTube call fails as if the phone were offline.
class _OfflineTube extends InnerTube {
  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> body,
          {YtClient client = YtClient.webRemix,
          Map<String, String>? query,
          Duration timeout = const Duration(seconds: 20)}) async =>
      throw const SocketException('Failed host lookup');
}

void main() {
  // Under the test binding every HttpClient request gets a 400, so the
  // youtube_explode fallback fails too without touching the network.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed playlist load is reported, not returned as an empty playlist', () async {
    final repo = YouTubeRepository(tube: _OfflineTube());
    await expectLater(repo.collection('PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI'),
        throwsA(isA<SocketException>()));
  });
}
