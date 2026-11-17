// Live smoke test for the YouTube layer: `dart run tool/smoke_youtube.dart`.
// Hits music.youtube.com anonymously and prints what each call returns.
import 'dart:io';

import 'package:musicra/youtube/models.dart';
import 'package:musicra/youtube/playlist_link.dart';
import 'package:musicra/youtube/youtube_repository.dart';

Future<void> main(List<String> args) async {
  final repo = YouTubeRepository();
  var failures = 0;

  Future<T?> step<T>(String name, Future<T> Function() run, String Function(T) describe) async {
    final sw = Stopwatch()..start();
    try {
      final r = await run();
      stdout.writeln('OK   $name (${sw.elapsedMilliseconds} ms): ${describe(r)}');
      return r;
    } catch (e, st) {
      failures++;
      stdout.writeln('FAIL $name: $e');
      stdout.writeln(st.toString().split('\n').take(4).join('\n'));
      return null;
    }
  }

  await step('home', () => repo.home(), (List<HomeSection> s) =>
      '${s.length} sections: ${s.map((x) => '${x.title}(${x.items.length}${x.isSongShelf ? ',songs' : ''})').join(' | ')}');

  final songs = await step('search songs', () => repo.search('tulus hati-hati di jalan', SearchFilter.songs),
      (SearchPage p) => '${p.items.length} items, cont=${p.continuation != null}; first=${p.items.firstOrNull?.song}'
          ' dur=${p.items.firstOrNull?.song?.durationSec} album=${p.items.firstOrNull?.song?.album} thumb=${p.items.firstOrNull?.thumbnail}');

  if (songs?.continuation != null) {
    await step('search songs page 2', () => repo.search('tulus', SearchFilter.songs, continuation: songs!.continuation),
        (SearchPage p) => '${p.items.length} items');
  }

  await step('search videos', () => repo.search('tulus', SearchFilter.videos),
      (SearchPage p) => '${p.items.length} items; first=${p.items.firstOrNull?.song}');

  final albums = await step('search albums', () => repo.search('tulus manusia', SearchFilter.albums),
      (SearchPage p) => '${p.items.length} items; first=${p.items.firstOrNull?.id} ${p.items.firstOrNull?.title} / ${p.items.firstOrNull?.subtitle}');

  final playlists = await step('search playlists', () => repo.search('lagu indonesia hits', SearchFilter.playlists),
      (SearchPage p) => '${p.items.length} items; first=${p.items.firstOrNull?.id} ${p.items.firstOrNull?.title} / ${p.items.firstOrNull?.subtitle}');

  await step('suggestions', () => repo.suggestions('tul'), (List<String> s) => s.join(', '));

  final albumId = albums?.items.firstOrNull?.id;
  if (albumId != null) {
    await step('album $albumId', () => repo.collection(albumId), (CollectionPage p) =>
        '"${p.title}" by ${p.author}, ${p.songs.length} songs, thumb=${p.thumbnail != null}; first=${p.songs.firstOrNull} art=${p.songs.firstOrNull?.thumbnail != null}');
  }

  final playlistId = playlists?.items.firstOrNull?.id;
  if (playlistId != null) {
    await step('playlist $playlistId', () => repo.collection(playlistId), (CollectionPage p) =>
        '"${p.title}" by ${p.author}, ${p.songs.length} songs; first=${p.songs.firstOrNull} dur=${p.songs.firstOrNull?.durationSec}');
  }

  for (final link in args) {
    final id = parsePlaylistId(link);
    stdout.writeln('link "$link" -> $id');
    if (id != null) {
      await step('import $id', () => repo.collection(id), (CollectionPage p) =>
          '"${p.title}" ${p.songs.length} songs; last=${p.songs.lastOrNull}');
    }
  }

  final firstSong = songs?.items.firstOrNull?.song;
  if (firstSong != null) {
    await step('radio ${firstSong.id}', () => repo.radio(firstSong.id),
        (List<Song> s) => '${s.length} songs; first=${s.firstOrNull}');
    final stream = await step('stream ${firstSong.id}', () => repo.stream(firstSong.id),
        (s) => '${s.source} ${s.mimeType} ${s.bitrate}bps len=${s.contentLength}');
    final second = songs!.items.length > 1 ? songs.items[1].song : null;
    if (second != null) {
      await step('stream (sticky client) ${second.id}', () => repo.stream(second.id),
          (s) => '${s.source} ${s.mimeType}');
    }
    if (stream != null) {
      await step('range download 1 MB', () async {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse(stream.url));
        req.headers.set('User-Agent', stream.userAgent);
        req.headers.set('Range', 'bytes=0-1048575');
        final res = await req.close();
        final bytes = await res.fold<int>(0, (n, chunk) => n + chunk.length);
        client.close();
        if (res.statusCode != 206) throw 'HTTP ${res.statusCode}';
        return bytes;
      }, (int n) => '$n bytes');
    }
  }

  repo.close();
  stdout.writeln(failures == 0 ? '\nALL OK' : '\n$failures FAILED');
  exit(failures == 0 ? 0 : 1);
}
