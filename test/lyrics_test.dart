import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musicra/lyrics/lyrics.dart';
import 'package:musicra/lyrics/lyrics_repository.dart';
import 'package:musicra/youtube/models.dart';
import 'package:musicra/youtube/parsers.dart';

const _lrc = '''
[ar: Tulus]
[ti: Hati-Hati di Jalan]
[00:13.24] Perjalanan membawamu
[00:18.10] Bertemu <00:18.50>denganku
[00:26.58] Sepertimu yang kucari
[00:31.00]
[00:31.57] Konon aku juga
[00:40.32]
[00:53.11] Kukira kita
[01:02.5][01:30.000] Reff berulang
[01:40.00]
''';

void main() {
  group('parseLrc', () {
    final lines = parseLrc(_lrc);

    test('reads stamps, skips tags and strips word stamps', () {
      expect(lines.first, const LyricLine(Duration(seconds: 13, milliseconds: 240), 'Perjalanan membawamu'));
      expect(lines[1].text, 'Bertemu denganku');
      expect(lines.any((l) => l.text.contains('ar:')), isFalse);
    });

    test('expands a line with several stamps, in time order', () {
      final reff = lines.where((l) => l.text == 'Reff berulang').map((l) => l.time).toList();
      expect(reff, [const Duration(minutes: 1, seconds: 2, milliseconds: 500), const Duration(minutes: 1, seconds: 30)]);
      for (var i = 1; i < lines.length; i++) {
        expect(lines[i].time >= lines[i - 1].time, isTrue);
      }
    });

    test('keeps only long instrumental breaks, never a trailing one', () {
      // 00:31.00 → 00:31.57 is too short; 00:40.32 → 00:53.11 is a real break.
      expect(lines.where((l) => l.isGap).map((l) => l.time).toList(),
          [const Duration(seconds: 40, milliseconds: 320)]);
      expect(lines.last.isGap, isFalse);
    });
  });

  test('lineAt finds the line being sung', () {
    final l = Lyrics(lines: parseLrc(_lrc), synced: true, source: 'x');
    expect(l.lineAt(const Duration(seconds: 5)), -1);
    expect(l.lineAt(const Duration(seconds: 13, milliseconds: 240)), 0);
    expect(l.lineAt(const Duration(seconds: 20)), 1);
    expect(l.lines[l.lineAt(const Duration(minutes: 5))].text, 'Reff berulang');
    expect(Lyrics.plain('a\nb', source: 'x').lineAt(const Duration(seconds: 20)), -1);
  });

  test('plain lyrics drop blank edges and survive a JSON round trip', () {
    final l = Lyrics.plain('\n\nSatu\n\nDua\n\n', source: 'LRCLIB');
    expect(l.lines.map((e) => e.text).toList(), ['Satu', '', 'Dua']);
    final back = Lyrics.fromJson(jsonDecode(jsonEncode(l.toJson())) as Map<String, Object?>);
    expect(back.lines, l.lines);
    expect(back.synced, isFalse);
    expect(back.source, 'LRCLIB');
  });

  group('cleanTitle', () {
    test('removes video noise', () {
      expect(cleanTitle('Hati-Hati di Jalan (Official Music Video)', 'Tulus'), 'Hati-Hati di Jalan');
      expect(cleanTitle('Monokrom [Lirik]', 'Tulus'), 'Monokrom');
      expect(cleanTitle('Teh Hijau | Official Audio', 'Tulus'), 'Teh Hijau');
      expect(cleanTitle('Señorita (feat. Young Miko)', 'Wisin'), 'Señorita');
      expect(cleanTitle('Lagu ft. Orang Lain', 'X'), 'Lagu');
    });

    test('drops the "Artist - " prefix of video uploads only', () {
      expect(cleanTitle('Tulus - Hati-Hati di Jalan (Video Lirik)', 'Tulus'), 'Hati-Hati di Jalan');
      expect(cleanTitle('Bukan Cinta Biasa - Live', 'Afgan'), 'Bukan Cinta Biasa - Live');
    });

    test('keeps titles that are only brackets', () {
      expect(cleanTitle('(Official Video)', 'X'), '(Official Video)');
    });
  });

  test('primaryArtist takes the first credit', () {
    expect(primaryArtist('Wisin, Young Miko'), 'Wisin');
    expect(primaryArtist('Tulus & Teman'), 'Tulus');
    expect(primaryArtist('Max - Topic'), 'Max');
    expect(primaryArtist('Florence and the Machine'), 'Florence and the Machine');
  });

  group('YouTube lyrics parsers', () {
    test('find the lyrics tab', () {
      final next = {
        'tabs': [
          {'tabRenderer': {'title': 'Berikutnya'}},
          {'tabRenderer': {'endpoint': {'browseEndpoint': {'browseId': 'MPLYt_abc'}}}},
          {'tabRenderer': {'endpoint': {'browseEndpoint': {'browseId': 'MPTRt_abc'}}}},
        ],
      };
      expect(parseLyricsBrowseId(next), 'MPLYt_abc');
      expect(parseLyricsBrowseId({'tabs': []}), isNull);
    });

    test('read the text and the credit', () {
      final browse = {
        'contents': {
          'musicDescriptionShelfRenderer': {
            'description': {'runs': [{'text': 'Baris satu\nBaris dua'}]},
            'footer': {'runs': [{'text': 'Sumber: LyricFind'}]},
          },
        },
      };
      final r = parseLyrics(browse)!;
      expect(r.text, 'Baris satu\nBaris dua');
      expect(r.source, 'LyricFind');
    });
  });

  group('LyricsRepository', () {
    const song = Song(id: 'E7kHvjvU6JY', title: 'Hati-Hati di Jalan', artist: 'Tulus', durationSec: 242);
    final record = {
      'trackName': 'Hati-Hati di Jalan',
      'artistName': 'Tulus',
      'duration': 242.0,
      'instrumental': false,
      'plainLyrics': 'Perjalanan membawamu',
      'syncedLyrics': '[00:13.24] Perjalanan membawamu',
    };

    LyricsRepository repo(Future<http.Response> Function(http.Request) handler,
            {YouTubeLyricsFetcher? youtube, Directory? cacheDir}) =>
        LyricsRepository(client: MockClient(handler), youtube: youtube, cacheDir: cacheDir);

    test('uses the exact LRCLIB match with synced lines', () async {
      final asked = <Uri>[];
      final r = repo((req) async {
        asked.add(req.url);
        return http.Response(jsonEncode(record), 200);
      });
      final l = (await r.lyricsFor(song))!;
      expect(l.synced, isTrue);
      expect(l.source, 'LRCLIB');
      expect(l.lines.single.text, 'Perjalanan membawamu');
      expect(asked.single.path, '/api/get');
      expect(asked.single.queryParameters, containsPair('duration', '242'));

      await r.lyricsFor(song); // remembered
      expect(asked, hasLength(1));
    });

    test('falls back to search and picks the synced hit closest in length', () async {
      final r = repo((req) async {
        if (req.url.path.endsWith('/get')) return http.Response('{}', 404);
        return http.Response(
            jsonEncode([
              {...record, 'duration': 300.0, 'syncedLyrics': '[00:01.00] Versi lain'},
              {...record, 'duration': 243.0, 'syncedLyrics': null, 'plainLyrics': 'Tanpa waktu'},
              {...record, 'duration': 240.0, 'syncedLyrics': '[00:02.00] Yang benar'},
            ]),
            200);
      });
      final l = (await r.lyricsFor(song))!;
      expect(l.lines.single.text, 'Yang benar');
    });

    test('falls back to YouTube Music, then to nothing', () async {
      final notFound = repo((_) async => http.Response('[]', 404),
          youtube: (_) async => (text: 'Dari YouTube', source: 'LyricFind'));
      final l = (await notFound.lyricsFor(song))!;
      expect(l.synced, isFalse);
      expect(l.source, 'LyricFind via YouTube Music');

      final none = repo((_) async => http.Response('[]', 404), youtube: (_) async => null);
      expect(await none.lyricsFor(song), isNull);
    });

    test('throws when every source is unreachable, and can retry', () async {
      var online = false;
      final r = repo((_) async {
        if (!online) throw http.ClientException('Failed host lookup');
        return http.Response(jsonEncode(record), 200);
      }, youtube: (_) async => throw const SocketException('offline'));
      await expectLater(r.lyricsFor(song), throwsA(anything));
      online = true;
      expect(await r.lyricsFor(song), isNotNull);
    });

    test('serves lyrics from the disk cache when offline', () async {
      final dir = await Directory.systemTemp.createTemp('lyrics_test');
      addTearDown(() => dir.delete(recursive: true));
      await repo((_) async => http.Response(jsonEncode(record), 200), cacheDir: dir).lyricsFor(song);

      final offline = repo((_) async => throw http.ClientException('offline'), cacheDir: dir);
      final l = (await offline.lyricsFor(song))!;
      expect(l.synced, isTrue);
      expect(l.lines.single.text, 'Perjalanan membawamu');
    });
  });
}
