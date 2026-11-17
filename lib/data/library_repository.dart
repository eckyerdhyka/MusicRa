import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../youtube/models.dart';

class LocalPlaylist {
  const LocalPlaylist({
    required this.id,
    required this.name,
    required this.songCount,
    this.thumbnail,
    this.sourceId,
    this.covers = const [],
  });

  final int id;
  final String name;
  final int songCount;

  /// Cover from the imported YouTube playlist, if any.
  final String? thumbnail;

  /// YouTube playlist id it was imported from.
  final String? sourceId;

  /// Up to four song covers for a mosaic when there is no [thumbnail].
  final List<String> covers;
}

class DownloadRecord {
  const DownloadRecord({required this.songId, required this.path, required this.size});

  final String songId;
  final String path;
  final int size;
}

/// Everything the user keeps on the device: liked songs, playlists,
/// downloads, history. Notifies listeners after every write so Riverpod
/// providers that depend on it recompute.
class LibraryRepository extends ChangeNotifier {
  LibraryRepository._(this._db);

  final Database _db;
  final Set<String> _liked = {};
  final Map<String, DownloadRecord> _downloads = {};

  static Future<LibraryRepository> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), 'musicra.db');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        final batch = db.batch()
          ..execute('''CREATE TABLE songs(
            id TEXT PRIMARY KEY, title TEXT NOT NULL, artist TEXT NOT NULL,
            artist_id TEXT, album TEXT, album_id TEXT, thumbnail TEXT,
            duration INTEGER, local_art TEXT)''')
          ..execute('''CREATE TABLE playlists(
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
            thumbnail TEXT, source_id TEXT, created_at INTEGER NOT NULL)''')
          ..execute('''CREATE TABLE playlist_songs(
            playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
            song_id TEXT NOT NULL REFERENCES songs(id),
            position INTEGER NOT NULL,
            PRIMARY KEY(playlist_id, song_id))''')
          ..execute('CREATE TABLE liked(song_id TEXT PRIMARY KEY REFERENCES songs(id), liked_at INTEGER NOT NULL)')
          ..execute('''CREATE TABLE downloads(song_id TEXT PRIMARY KEY REFERENCES songs(id),
            path TEXT NOT NULL, size INTEGER NOT NULL, downloaded_at INTEGER NOT NULL)''')
          ..execute('''CREATE TABLE history(song_id TEXT PRIMARY KEY REFERENCES songs(id),
            played_at INTEGER NOT NULL, play_count INTEGER NOT NULL DEFAULT 1)''')
          ..execute('CREATE TABLE search_history(query TEXT PRIMARY KEY, searched_at INTEGER NOT NULL)');
        await batch.commit(noResult: true);
      },
    );
    final repo = LibraryRepository._(db);
    await repo._loadCaches();
    return repo;
  }

  Future<void> _loadCaches() async {
    _liked
      ..clear()
      ..addAll((await _db.query('liked', columns: ['song_id'])).map((r) => r['song_id'] as String));
    _downloads.clear();
    for (final r in await _db.query('downloads')) {
      final rec = DownloadRecord(
        songId: r['song_id'] as String,
        path: r['path'] as String,
        size: r['size'] as int,
      );
      _downloads[rec.songId] = rec;
    }
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ---- songs -------------------------------------------------------------

  /// Inserts or refreshes song metadata without losing saved cover art.
  Future<void> saveSongs(Iterable<Song> songs, {Transaction? txn}) async {
    final batch = (txn ?? _db).batch();
    for (final s in songs) {
      final map = s.toMap()..remove('local_art');
      batch.insert('songs', map, conflictAlgorithm: ConflictAlgorithm.ignore);
      final update = Map<String, Object?>.from(map)..remove('id');
      update.removeWhere((_, v) => v == null);
      batch.update('songs', update, where: 'id = ?', whereArgs: [s.id]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Song>> _songsQuery(String sql, [List<Object?>? args]) async =>
      (await _db.rawQuery(sql, args)).map(Song.fromMap).toList();

  // ---- liked ---------------------------------------------------------------

  bool isLiked(String songId) => _liked.contains(songId);

  Future<void> setLiked(Song song, bool liked) async {
    if (liked) {
      await saveSongs([song]);
      await _db.insert('liked', {'song_id': song.id, 'liked_at': _now},
          conflictAlgorithm: ConflictAlgorithm.replace);
      _liked.add(song.id);
    } else {
      await _db.delete('liked', where: 'song_id = ?', whereArgs: [song.id]);
      _liked.remove(song.id);
    }
    notifyListeners();
  }

  Future<List<Song>> likedSongs() => _songsQuery(
      'SELECT s.* FROM liked l JOIN songs s ON s.id = l.song_id ORDER BY l.liked_at DESC');

  int get likedCount => _liked.length;

  // ---- playlists -------------------------------------------------------------

  Future<List<LocalPlaylist>> playlists() async {
    final rows = await _db.rawQuery('''
      SELECT p.*, (SELECT COUNT(*) FROM playlist_songs ps WHERE ps.playlist_id = p.id) AS cnt
      FROM playlists p ORDER BY p.created_at DESC''');
    final out = <LocalPlaylist>[];
    for (final r in rows) {
      final id = r['id'] as int;
      final covers = (await _db.rawQuery('''
          SELECT s.thumbnail FROM playlist_songs ps JOIN songs s ON s.id = ps.song_id
          WHERE ps.playlist_id = ? AND s.thumbnail IS NOT NULL ORDER BY ps.position LIMIT 4''', [id]))
          .map((e) => e['thumbnail'] as String)
          .toList();
      out.add(LocalPlaylist(
        id: id,
        name: r['name'] as String,
        songCount: r['cnt'] as int,
        thumbnail: r['thumbnail'] as String?,
        sourceId: r['source_id'] as String?,
        covers: covers,
      ));
    }
    return out;
  }

  Future<LocalPlaylist?> playlist(int id) async =>
      (await playlists()).where((p) => p.id == id).firstOrNull;

  Future<int> createPlaylist(String name, {String? thumbnail, String? sourceId, List<Song> songs = const []}) async {
    late int id;
    await _db.transaction((txn) async {
      id = await txn.insert('playlists', {
        'name': name.trim().isEmpty ? 'Playlist baru' : name.trim(),
        'thumbnail': thumbnail,
        'source_id': sourceId,
        'created_at': _now,
      });
      if (songs.isNotEmpty) {
        await saveSongs(songs, txn: txn);
        final batch = txn.batch();
        for (var i = 0; i < songs.length; i++) {
          batch.insert('playlist_songs', {'playlist_id': id, 'song_id': songs[i].id, 'position': i},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await batch.commit(noResult: true);
      }
    });
    notifyListeners();
    return id;
  }

  Future<void> renamePlaylist(int id, String name) async {
    await _db.update('playlists', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> deletePlaylist(int id) async {
    await _db.delete('playlists', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<List<Song>> playlistSongs(int id) => _songsQuery('''
      SELECT s.* FROM playlist_songs ps JOIN songs s ON s.id = ps.song_id
      WHERE ps.playlist_id = ? ORDER BY ps.position''', [id]);

  /// Appends songs; returns how many were new to the playlist.
  Future<int> addToPlaylist(int playlistId, List<Song> songs) async {
    var added = 0;
    await _db.transaction((txn) async {
      await saveSongs(songs, txn: txn);
      final maxPos = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT MAX(position) FROM playlist_songs WHERE playlist_id = ?', [playlistId])) ??
          -1;
      var pos = maxPos + 1;
      for (final s in songs) {
        final r = await txn.insert(
            'playlist_songs', {'playlist_id': playlistId, 'song_id': s.id, 'position': pos},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (r != 0) {
          added++;
          pos++;
        }
      }
    });
    notifyListeners();
    return added;
  }

  Future<void> removeFromPlaylist(int playlistId, String songId) async {
    await _db.delete('playlist_songs',
        where: 'playlist_id = ? AND song_id = ?', whereArgs: [playlistId, songId]);
    notifyListeners();
  }

  // ---- history ---------------------------------------------------------------

  Future<void> recordPlay(Song song) async {
    await saveSongs([song]);
    // Update-then-insert instead of UPSERT: Android 9 ships SQLite < 3.24.
    final n = await _db.rawUpdate(
        'UPDATE history SET played_at = ?, play_count = play_count + 1 WHERE song_id = ?',
        [_now, song.id]);
    if (n == 0) {
      await _db.insert('history', {'song_id': song.id, 'played_at': _now, 'play_count': 1},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    notifyListeners();
  }

  Future<List<Song>> recentSongs({int limit = 20}) => _songsQuery(
      'SELECT s.* FROM history h JOIN songs s ON s.id = h.song_id ORDER BY h.played_at DESC LIMIT ?',
      [limit]);

  // ---- downloads -------------------------------------------------------------

  String? downloadPath(String songId) => _downloads[songId]?.path;

  bool isDownloaded(String songId) => _downloads.containsKey(songId);

  int get downloadCount => _downloads.length;

  Future<void> addDownload(Song song, String path, int size, {String? artPath}) async {
    await saveSongs([song]);
    if (artPath != null) {
      await _db.update('songs', {'local_art': artPath}, where: 'id = ?', whereArgs: [song.id]);
    }
    await _db.insert('downloads', {'song_id': song.id, 'path': path, 'size': size, 'downloaded_at': _now},
        conflictAlgorithm: ConflictAlgorithm.replace);
    _downloads[song.id] = DownloadRecord(songId: song.id, path: path, size: size);
    notifyListeners();
  }

  Future<void> removeDownload(String songId) async {
    final rec = _downloads.remove(songId);
    if (rec != null) {
      try {
        await File(rec.path).delete();
      } catch (_) {}
    }
    final art = Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM songs WHERE id = ? AND local_art IS NOT NULL', [songId]));
    if ((art ?? 0) > 0) {
      final row = await _db.query('songs', columns: ['local_art'], where: 'id = ?', whereArgs: [songId]);
      final path = row.firstOrNull?['local_art'] as String?;
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      await _db.update('songs', {'local_art': null}, where: 'id = ?', whereArgs: [songId]);
    }
    await _db.delete('downloads', where: 'song_id = ?', whereArgs: [songId]);
    notifyListeners();
  }

  Future<List<Song>> downloadedSongs() => _songsQuery(
      'SELECT s.* FROM downloads d JOIN songs s ON s.id = d.song_id ORDER BY d.downloaded_at DESC');

  int get downloadedBytes => _downloads.values.fold(0, (a, d) => a + d.size);

  /// Fills in local cover paths for songs that were downloaded.
  Future<List<Song>> withLocalArt(List<Song> songs) async {
    final ids = songs.where((s) => _downloads.containsKey(s.id)).map((s) => s.id).toList();
    if (ids.isEmpty) return songs;
    final rows = await _db.query('songs',
        columns: ['id', 'local_art'],
        where: 'id IN (${List.filled(ids.length, '?').join(',')}) AND local_art IS NOT NULL',
        whereArgs: ids);
    final art = {for (final r in rows) r['id'] as String: r['local_art'] as String};
    return songs.map((s) => art[s.id] == null ? s : s.copyWith(localArt: art[s.id])).toList();
  }

  // ---- search history --------------------------------------------------------

  Future<void> addSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    await _db.insert('search_history', {'query': q, 'searched_at': _now},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> removeSearch(String query) async {
    await _db.delete('search_history', where: 'query = ?', whereArgs: [query]);
    notifyListeners();
  }

  Future<List<String>> searchHistory({int limit = 15}) async =>
      (await _db.query('search_history', orderBy: 'searched_at DESC', limit: limit))
          .map((r) => r['query'] as String)
          .toList();
}
