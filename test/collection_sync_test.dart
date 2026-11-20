// Syncing an imported playlist from the playlist page's ⋮ menu.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicra/data/library_repository.dart';
import 'package:musicra/download/download_manager.dart';
import 'package:musicra/providers.dart';
import 'package:musicra/ui/screens/collection_screen.dart';
import 'package:musicra/ui/widgets/states.dart';
import 'package:musicra/youtube/models.dart';
import 'package:musicra/youtube/youtube_repository.dart';

const _a = Song(id: 'aaaaaaaaaaa', title: 'Lagu A', artist: 'X');
const _b = Song(id: 'bbbbbbbbbbb', title: 'Lagu B', artist: 'X');
const _c = Song(id: 'ccccccccccc', title: 'Lagu C', artist: 'X');

void main() {
  late _FakeLibrary lib;
  late _FakeYouTube yt;

  /// Opens the playlist page from a home page, like a tab navigator does.
  Future<void> pumpPage(WidgetTester tester) async {
    lib = _FakeLibrary([_a]);
    yt = _FakeYouTube();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryProvider.overrideWith((_) => lib),
        youtubeProvider.overrideWithValue(yt),
        downloadsProvider.overrideWith((_) => DownloadManager(yt, lib)),
        mediaItemProvider.overrideWith((_) => Stream.value(null)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const CollectionScreen(source: LocalPlaylistCollection(1)))),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSync(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinkronkan dari YouTube'));
    await tester.pump();
  }

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('adds the new songs, says how many, and the page stays up', (tester) async {
    await pumpPage(tester);
    expect(find.text('Lagu A'), findsOneWidget);

    await tapSync(tester);
    expect(find.text('Menyinkronkan dari YouTube…'), findsOneWidget);
    yt.reply([_a, _b, _c]);
    // Writing to the library must not swap the page for a spinner, not even
    // for a frame (that reset the scroll position and dropped the menu).
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(LoadingView), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    }

    await pumpFrames(tester);
    expect(lib.songs, [_a, _b, _c]);
    expect(find.text('2 lagu baru ditambahkan di akhir playlist'), findsOneWidget);
    expect(find.text('Playlist • 3 lagu'), findsOneWidget);
  });

  testWidgets('says when there is nothing new', (tester) async {
    await pumpPage(tester);
    await tapSync(tester);
    yt.reply([_a]);
    await pumpFrames(tester);

    expect(find.textContaining('Sudah paling baru'), findsOneWidget);
  });

  testWidgets('still reports the result after leaving the page', (tester) async {
    await pumpPage(tester);
    await tapSync(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('buka'), findsOneWidget);

    yt.reply([_a, _b]);
    await pumpFrames(tester);
    expect(lib.songs, [_a, _b]);
    expect(find.text('1 lagu baru ditambahkan di akhir playlist'), findsOneWidget);
  });

  testWidgets('shows an error instead of "up to date" when YouTube fails', (tester) async {
    await pumpPage(tester);
    await tapSync(tester);
    yt.fail(Exception('SocketException: Failed host lookup'));
    await pumpFrames(tester);

    expect(find.text('Tidak ada koneksi internet.'), findsOneWidget);
    expect(find.textContaining('Sudah paling baru'), findsNothing);
  });
}

/// Answers `collection` when the test says so.
class _FakeYouTube implements YouTubeRepository {
  Completer<CollectionPage>? _pending;

  void reply(List<Song> songs) =>
      _pending!.complete(CollectionPage(id: 'VLPLtest', title: 'Impor', songs: songs));

  void fail(Object error) => _pending!.completeError(error);

  @override
  Future<CollectionPage> collection(String id, {int maxSongs = 5000}) =>
      (_pending = Completer()).future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One imported playlist (id 1) kept in memory; notifies like the real one.
class _FakeLibrary extends ChangeNotifier implements LibraryRepository {
  _FakeLibrary(List<Song> songs) : songs = List.of(songs);

  final List<Song> songs;

  @override
  Future<List<LocalPlaylist>> playlists() async => [
        LocalPlaylist(id: 1, name: 'Impor', songCount: songs.length, sourceId: 'PLtest'),
      ];

  @override
  Future<List<Song>> playlistSongs(int id) async => List.of(songs);

  @override
  Future<int> addToPlaylist(int playlistId, List<Song> add) async {
    final fresh = add.where((s) => !songs.contains(s)).toList();
    songs.addAll(fresh);
    notifyListeners();
    return fresh.length;
  }

  @override
  bool isDownloaded(String songId) => false;

  @override
  bool isLiked(String songId) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
