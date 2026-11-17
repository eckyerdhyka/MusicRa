import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/library_repository.dart';
import '../youtube/models.dart';
import '../youtube/youtube_repository.dart';

enum DownloadStatus { queued, downloading, failed }

class DownloadTask {
  DownloadTask(this.song);

  final Song song;
  DownloadStatus status = DownloadStatus.queued;
  double progress = 0;
  String? error;
  bool cancelled = false;
}

/// Saves songs into the app's private storage for offline playback.
///
/// googlevideo throttles single long requests, so files are fetched in
/// 2 MB Range chunks (what Convx/NewPipe do). An expired or rejected URL is
/// re-resolved and the download resumes from the last byte written.
class DownloadManager extends ChangeNotifier {
  DownloadManager(this._yt, this._lib);

  final YouTubeRepository _yt;
  final LibraryRepository _lib;
  final http.Client _http = http.Client();

  static const _chunk = 2 * 1024 * 1024;
  static const _maxParallel = 2;

  final Map<String, DownloadTask> _tasks = {};
  final Queue<String> _queue = Queue();
  int _active = 0;
  Directory? _dir;

  /// Tasks still queued, running or failed (finished ones live in the library).
  Map<String, DownloadTask> get tasks => UnmodifiableMapView(_tasks);

  DownloadTask? task(String songId) => _tasks[songId];

  int get pendingCount =>
      _tasks.values.where((t) => t.status != DownloadStatus.failed).length;

  /// Queues songs that are not already downloaded or pending; returns how
  /// many were queued.
  int enqueue(Iterable<Song> songs) {
    var n = 0;
    for (final s in songs) {
      if (_lib.isDownloaded(s.id)) continue;
      final existing = _tasks[s.id];
      if (existing != null && existing.status != DownloadStatus.failed) continue;
      _tasks[s.id] = DownloadTask(s);
      _queue.add(s.id);
      n++;
    }
    if (n > 0) {
      notifyListeners();
      _pump();
    }
    return n;
  }

  void cancel(String songId) {
    final t = _tasks.remove(songId);
    if (t == null) return;
    t.cancelled = true;
    _queue.remove(songId);
    notifyListeners();
  }

  void cancelAll() {
    for (final id in _tasks.keys.toList()) {
      cancel(id);
    }
  }

  Future<void> delete(String songId) async {
    cancel(songId);
    await _lib.removeDownload(songId);
  }

  void _pump() {
    while (_active < _maxParallel && _queue.isNotEmpty) {
      final id = _queue.removeFirst();
      final task = _tasks[id];
      if (task == null) continue;
      _active++;
      _run(task).whenComplete(() {
        _active--;
        _pump();
      });
    }
  }

  Future<Directory> _downloadsDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/downloads');
    await Directory('${dir.path}/art').create(recursive: true);
    return _dir = dir;
  }

  Future<void> _run(DownloadTask task) async {
    final song = task.song;
    task.status = DownloadStatus.downloading;
    notifyListeners();
    File? part;
    try {
      final dir = await _downloadsDir();
      var stream = await _yt.stream(song.id);
      final ext = stream.extension;
      part = File('${dir.path}/${song.id}.$ext.part');
      final sink = part.openWrite();
      var written = 0;
      var total = stream.contentLength ?? await _contentLength(stream.url, stream.userAgent);
      var lastNotify = DateTime.now();
      var retries = 0;
      try {
        while (total == null || written < total) {
          if (task.cancelled) throw _Cancelled();
          final end = total == null ? null : min(written + _chunk, total) - 1;
          final req = http.Request('GET', Uri.parse(stream.url))
            ..headers['User-Agent'] = stream.userAgent
            ..headers['Range'] = 'bytes=$written-${end ?? ''}';
          try {
            final res = await _http.send(req).timeout(const Duration(seconds: 30));
            if (res.statusCode != 206 && res.statusCode != 200) {
              await res.stream.drain<void>();
              // Expired or rejected URL: resolve a fresh one and resume.
              if (++retries > 3) throw _Fatal('HTTP ${res.statusCode}');
              stream = await _yt.stream(song.id, forceRefresh: true);
              total ??= stream.contentLength;
              continue;
            }
            if (res.statusCode == 200 && written > 0) {
              // Server ignored Range; appending would corrupt the file.
              await res.stream.drain<void>();
              throw _Fatal('Server tidak mendukung unduhan bertahap');
            }
            await for (final bytes in res.stream.timeout(const Duration(seconds: 30))) {
              if (task.cancelled) throw _Cancelled();
              sink.add(bytes);
              written += bytes.length;
              if (total != null && DateTime.now().difference(lastNotify).inMilliseconds > 250) {
                task.progress = written / total;
                lastNotify = DateTime.now();
                notifyListeners();
              }
            }
          } on _Cancelled {
            rethrow;
          } on _Fatal {
            rethrow;
          } catch (e) {
            // Dropped connection or timeout: retry from the bytes we have.
            if (++retries > 5) throw _Fatal('Koneksi terputus');
            await Future<void>.delayed(Duration(seconds: retries));
            continue;
          }
          if (total == null) break; // single unbounded request finished
        }
      } finally {
        await sink.close();
      }

      final file = await part.rename('${dir.path}/${song.id}.$ext');
      final art = await _saveArt(song, dir);
      await _lib.addDownload(song, file.path, written, artPath: art);
      _tasks.remove(song.id);
      notifyListeners();
    } on _Cancelled {
      await _silentDelete(part);
    } catch (e) {
      await _silentDelete(part);
      if (task.cancelled) return;
      task
        ..status = DownloadStatus.failed
        ..error = e.toString();
      notifyListeners();
    }
  }

  Future<int?> _contentLength(String url, String ua) async {
    try {
      final req = http.Request('HEAD', Uri.parse(url))..headers['User-Agent'] = ua;
      final res = await _http.send(req).timeout(const Duration(seconds: 10));
      await res.stream.drain<void>();
      return res.contentLength;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _saveArt(Song song, Directory dir) async {
    final url = hiResThumb(song.thumbnail);
    if (url == null) return null;
    try {
      final res = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final f = File('${dir.path}/art/${song.id}.jpg');
      await f.writeAsBytes(res.bodyBytes);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _silentDelete(File? f) async {
    try {
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}

class _Cancelled implements Exception {}

class _Fatal implements Exception {
  _Fatal(this.message);

  final String message;

  @override
  String toString() => message;
}
