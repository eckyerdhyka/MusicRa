import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yte;

import 'innertube.dart';
import 'models.dart';
import 'parsers.dart';
import 'playlist_link.dart';
import 'stream_resolver.dart';

/// Everything the app asks of YouTube, in app-level terms.
class YouTubeRepository {
  YouTubeRepository({InnerTube? tube}) : _tube = tube ?? InnerTube() {
    streams = StreamResolver(_tube);
  }

  final InnerTube _tube;
  late final StreamResolver streams;

  /// Home shelves; follows a couple of continuations for a fuller page.
  Future<List<HomeSection>> home({int pages = 3}) async {
    var feed = parseHome(await _tube.browse(browseId: 'FEmusic_home'));
    final sections = [...feed.sections];
    for (var i = 1; i < pages && feed.continuation != null; i++) {
      try {
        feed = parseHome(await _tube.browse(continuation: feed.continuation));
        sections.addAll(feed.sections);
      } catch (_) {
        break;
      }
    }
    return sections;
  }

  Future<SearchPage> search(String query, SearchFilter filter, {String? continuation}) async {
    final json = continuation == null
        ? await _tube.search(query: query, params: filter.params)
        : await _tube.search(continuation: continuation);
    final page = parseSearch(json);
    final wanted = switch (filter) {
      SearchFilter.songs || SearchFilter.videos => YtItemType.song,
      SearchFilter.albums => YtItemType.album,
      SearchFilter.playlists => YtItemType.playlist,
    };
    return SearchPage(
      items: page.items.where((i) => i.type == wanted).toList(),
      continuation: page.continuation,
    );
  }

  Future<List<String>> suggestions(String input) async {
    if (input.trim().isEmpty) return const [];
    return parseSuggestions(await _tube.suggestions(input));
  }

  /// Loads a playlist (`VL…` / playlist id), album (`MPREb_…`) or radio
  /// (`RD…`) with every song, following continuations up to [maxSongs].
  Future<CollectionPage> collection(String id, {int maxSongs = 5000}) async {
    final playlistId = id.startsWith('VL') ? id.substring(2) : id;
    if (!id.startsWith('MPRE') && isRadioPlaylist(playlistId)) {
      return _radioCollection(playlistId);
    }
    final browseId = id.startsWith('MPRE') || id.startsWith('VL') ? id : 'VL$id';

    CollectionPage? page;
    Object? browseError;
    StackTrace? browseStack;
    try {
      final first = parseCollection(await _tube.browse(browseId: browseId), browseId);
      final songs = [...first.page.songs];
      var cont = first.continuation;
      final seen = <String>{};
      while (cont != null && songs.length < maxSongs && seen.add(cont)) {
        final more = parseCollectionContinuation(await _tube.browse(continuation: cont));
        if (more.songs.isEmpty) break;
        songs.addAll(more.songs);
        cont = more.continuation;
      }
      page = CollectionPage(
        id: browseId,
        title: first.page.title,
        author: first.page.author,
        thumbnail: first.page.thumbnail,
        songs: _dedupe(songs),
        isAlbum: first.page.isAlbum,
      );
    } catch (e, st) {
      if (id.startsWith('MPRE')) rethrow;
      browseError = e;
      browseStack = st;
    }
    if (page != null && page.songs.isNotEmpty) return page;
    if (id.startsWith('MPRE')) return page!;
    // Curated YouTube Music playlists (RDCLAK…) come back empty from browse
    // for logged-out users but play fine as a watch queue.
    if (playlistId.startsWith('RD')) {
      final radio = await _radioCollection(playlistId);
      if (radio.songs.isNotEmpty) {
        final title = await _explodeTitle(playlistId);
        if (title == null) return radio;
        return CollectionPage(
          id: radio.id,
          title: title,
          songs: radio.songs,
          thumbnail: radio.thumbnail,
          author: 'YouTube Music',
        );
      }
    }
    // Some playlists (e.g. plain YouTube ones) are not served by the music
    // browse endpoint; youtube_explode reads them from youtube.com instead.
    // When browse itself failed (offline, rate limited) and the fallback has
    // nothing either, report that failure: an empty page would read as
    // "playlist is empty" on import and "already up to date" on sync.
    try {
      final fallback = await _collectionWithExplode(playlistId, fallbackTitle: page?.title);
      if (fallback.songs.isNotEmpty || browseError == null) return fallback;
    } catch (_) {
      if (browseError == null) rethrow;
    }
    Error.throwWithStackTrace(browseError, browseStack ?? StackTrace.current);
  }

  Future<CollectionPage> _radioCollection(String playlistId) async {
    final res = parseNext(await _tube.next(playlistId: playlistId));
    final songs = [...res.songs];
    var cont = res.continuation;
    // Mixes are endless; curated playlists end on their own.
    final maxPages = playlistId.startsWith('RDCLAK') ? 20 : 3;
    for (var i = 0; i < maxPages && cont != null; i++) {
      final more = parseNext(await _tube.next(playlistId: playlistId, continuation: cont));
      final before = songs.length;
      songs.addAll(more.songs.where((s) => !songs.contains(s)));
      if (songs.length == before) break;
      cont = more.continuation;
    }
    return CollectionPage(
      id: playlistId,
      title: (res.title?.isNotEmpty ?? false) ? res.title! : 'Mix',
      songs: _dedupe(songs),
      thumbnail: songs.isEmpty ? null : songs.first.thumbnail,
    );
  }

  Future<String?> _explodeTitle(String playlistId) async {
    final yt = yte.YoutubeExplode();
    try {
      final title = (await yt.playlists.get(playlistId)).title;
      return title.isEmpty ? null : title;
    } catch (_) {
      return null;
    } finally {
      yt.close();
    }
  }

  Future<CollectionPage> _collectionWithExplode(String playlistId, {String? fallbackTitle}) async {
    final yt = yte.YoutubeExplode();
    try {
      final meta = await yt.playlists.get(playlistId);
      final songs = <Song>[];
      await for (final v in yt.playlists.getVideos(playlistId)) {
        songs.add(Song(
          id: v.id.value,
          title: v.title,
          artist: v.author.replaceAll(RegExp(r'\s*-\s*Topic$'), ''),
          thumbnail: v.thumbnails.highResUrl,
          durationSec: v.duration?.inSeconds,
        ));
      }
      return CollectionPage(
        id: 'VL$playlistId',
        title: meta.title.isNotEmpty ? meta.title : (fallbackTitle ?? 'Playlist'),
        author: meta.author,
        thumbnail: songs.isEmpty ? null : songs.first.thumbnail,
        songs: _dedupe(songs),
      );
    } finally {
      yt.close();
    }
  }

  /// Songs related to [videoId] ("radio"), used for autoplay.
  Future<List<Song>> radio(String videoId) async {
    final res = parseNext(await _tube.next(videoId: videoId, playlistId: 'RDAMVM$videoId'));
    return res.songs.where((s) => s.id != videoId).toList();
  }

  /// Unsynced lyrics YouTube Music shows in its "Lirik" tab; null when the
  /// song has none.
  Future<({String text, String? source})?> lyrics(String videoId) async {
    final browseId = parseLyricsBrowseId(await _tube.next(videoId: videoId));
    if (browseId == null) return null;
    return parseLyrics(await _tube.browse(browseId: browseId));
  }

  Future<AudioStream> stream(String videoId, {bool forceRefresh = false}) =>
      streams.resolve(videoId, forceRefresh: forceRefresh);

  List<Song> _dedupe(List<Song> songs) {
    final seen = <String>{};
    return songs.where((s) => seen.add(s.id)).toList();
  }

  void close() {
    streams.close();
    _tube.close();
  }
}
