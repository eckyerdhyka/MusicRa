import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../youtube/models.dart';
import 'lyrics.dart';

typedef YouTubeLyricsFetcher = Future<({String text, String? source})?> Function(String videoId);

/// Finds lyrics for a song.
///
/// 1. LRCLIB (lrclib.net), a free community database with line-synced LRC:
///    an exact lookup on title + artist + duration, then a fuzzy search.
/// 2. YouTube Music's own "Lirik" tab (unsynced, usually from LyricFind).
///
/// Results are kept in memory and, when [cacheDir] is set, on disk, so lyrics
/// seen once (e.g. of downloaded songs) still show offline.
class LyricsRepository {
  LyricsRepository({
    this.youtube,
    http.Client? client,
    this.cacheDir,
    this.userAgent = 'musicRa/1.0 (Android)',
  }) : _http = client ?? http.Client();

  final YouTubeLyricsFetcher? youtube;
  final Directory? cacheDir;
  final String userAgent;
  final http.Client _http;

  static const _api = 'https://lrclib.net/api';

  /// Songs looked up this session; null means none of the sources had them.
  final _memory = <String, Lyrics?>{};
  final _inflight = <String, Future<Lyrics?>>{};

  /// Lyrics for [song], or null when no source has any. Throws only when
  /// every source failed (offline), so the caller can offer a retry.
  Future<Lyrics?> lyricsFor(Song song) {
    if (_memory.containsKey(song.id)) return Future.value(_memory[song.id]);
    return _inflight[song.id] ??= _load(song).then((l) {
      _memory[song.id] = l;
      return l;
    }).whenComplete(() {
      // Not an arrow: remove() returns this very future, which whenComplete
      // would then wait on forever.
      _inflight.remove(song.id);
    });
  }

  Future<Lyrics?> _load(Song song) async {
    final cached = await _readCache(song.id);
    if (cached != null) return cached;

    Object? error;
    var answered = false;

    try {
      final l = await _fromLrcLib(song);
      answered = true;
      if (l != null) return _writeCache(song.id, l);
    } catch (e) {
      error = e;
    }

    final yt = youtube;
    if (yt != null) {
      try {
        final r = await yt(song.id);
        answered = true;
        if (r != null) {
          final source = r.source == null ? 'YouTube Music' : '${r.source} via YouTube Music';
          return _writeCache(song.id, Lyrics.plain(r.text, source: source));
        }
      } catch (e) {
        error ??= e;
      }
    }

    if (!answered && error != null) throw error;
    return null;
  }

  Future<Lyrics?> _fromLrcLib(Song song) async {
    final title = cleanTitle(song.title, song.artist);
    final artist = song.artist.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '').trim();
    final primary = primaryArtist(artist);
    final secs = song.durationSec;

    if (secs != null && secs > 0) {
      for (final a in {artist, primary}) {
        final hit = await _get('get', {
          'track_name': title,
          'artist_name': a,
          'duration': '$secs',
        });
        if (hit is Map) {
          final l = _fromRecord(hit);
          if (l != null) return l;
        }
      }
    }

    final hits = await _get('search', {'track_name': title, 'artist_name': primary});
    if (hits is! List) return null;
    final candidates = hits.whereType<Map>().where((h) {
      if (secs == null) return true;
      final d = (h['duration'] as num?)?.toDouble();
      // Same song, different edit or a wrong match: lines would drift.
      return d != null && (d - secs).abs() <= 8;
    }).toList();
    if (candidates.isEmpty) return null;
    double gap(Map h) => secs == null ? 0 : (((h['duration'] as num?) ?? 0) - secs).abs().toDouble();
    candidates.sort((a, b) {
      final sa = _hasText(a['syncedLyrics']) ? 0 : 1;
      final sb = _hasText(b['syncedLyrics']) ? 0 : 1;
      return sa != sb ? sa - sb : gap(a).compareTo(gap(b));
    });
    for (final c in candidates) {
      final l = _fromRecord(c);
      if (l != null) return l;
    }
    return null;
  }

  static bool _hasText(Object? v) => v is String && v.trim().isNotEmpty;

  Lyrics? _fromRecord(Map record) {
    if (record['instrumental'] == true) {
      return const Lyrics(lines: [], synced: false, source: 'LRCLIB', instrumental: true);
    }
    final synced = record['syncedLyrics'];
    if (_hasText(synced)) {
      final lines = parseLrc(synced as String);
      if (lines.isNotEmpty) return Lyrics(lines: lines, synced: true, source: 'LRCLIB');
    }
    final plain = record['plainLyrics'];
    if (_hasText(plain)) return Lyrics.plain(plain as String, source: 'LRCLIB');
    return null;
  }

  /// JSON body of an LRCLIB call; null on 404 (not in the database).
  Future<Object?> _get(String path, Map<String, String> query) async {
    final res = await _http
        .get(Uri.parse('$_api/$path').replace(queryParameters: query), headers: {'User-Agent': userAgent})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw HttpException('LRCLIB HTTP ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  File? _cacheFile(String id) => cacheDir == null ? null : File('${cacheDir!.path}/$id.json');

  Future<Lyrics?> _readCache(String id) async {
    final f = _cacheFile(id);
    if (f == null) return null;
    try {
      if (!await f.exists()) return null;
      return Lyrics.fromJson(jsonDecode(await f.readAsString()) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  Future<Lyrics> _writeCache(String id, Lyrics l) async {
    final f = _cacheFile(id);
    if (f != null) {
      try {
        await f.parent.create(recursive: true);
        await f.writeAsString(jsonEncode(l.toJson()));
      } catch (_) {}
    }
    return l;
  }

  void close() => _http.close();
}
