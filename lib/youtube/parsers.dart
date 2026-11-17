/// Turns raw InnerTube (YouTube Music WEB_REMIX) JSON into [models].
///
/// YouTube reshuffles its response layout often, so these parsers locate
/// renderers by name anywhere in the tree instead of following one fixed path.
library;

import 'models.dart';

typedef Json = Map<String, dynamic>;

Object? dig(Object? node, List<Object> path) {
  var cur = node;
  for (final key in path) {
    if (key is int) {
      if (cur is List && key >= 0 && key < cur.length) {
        cur = cur[key];
      } else {
        return null;
      }
    } else {
      if (cur is Map && cur.containsKey(key)) {
        cur = cur[key];
      } else {
        return null;
      }
    }
  }
  return cur;
}

String? digStr(Object? node, List<Object> path) {
  final v = dig(node, path);
  return v is String ? v : null;
}

/// Every value stored under [key], depth-first, anywhere below [node].
List<Object?> findAll(Object? node, String key, {bool descendIntoMatches = false}) {
  final out = <Object?>[];
  void walk(Object? n) {
    if (n is Map) {
      for (final entry in n.entries) {
        if (entry.key == key) {
          out.add(entry.value);
          if (descendIntoMatches) walk(entry.value);
        } else {
          walk(entry.value);
        }
      }
    } else if (n is List) {
      for (final e in n) {
        walk(e);
      }
    }
  }

  walk(node);
  return out;
}

Object? findFirst(Object? node, String key) {
  if (node is Map) {
    if (node.containsKey(key)) return node[key];
    for (final v in node.values) {
      final r = findFirst(v, key);
      if (r != null) return r;
    }
  } else if (node is List) {
    for (final e in node) {
      final r = findFirst(e, key);
      if (r != null) return r;
    }
  }
  return null;
}

String runsText(Object? runsOrText) {
  if (runsOrText is Map) {
    if (runsOrText['simpleText'] is String) return runsOrText['simpleText'];
    return runsText(runsOrText['runs']);
  }
  if (runsOrText is! List) return '';
  return runsOrText
      .map((r) => r is Map ? (r['text'] ?? '') : '')
      .join();
}

/// Largest thumbnail URL below [node].
String? bestThumb(Object? node) {
  final lists = findAll(node, 'thumbnails');
  for (final l in lists) {
    if (l is List && l.isNotEmpty) {
      Map? best;
      var bestW = -1;
      for (final t in l) {
        if (t is Map && t['url'] is String) {
          final w = (t['width'] as num?)?.toInt() ?? 0;
          if (w >= bestW) {
            best = t;
            bestW = w;
          }
        }
      }
      var url = best?['url'] as String?;
      if (url != null && url.startsWith('//')) url = 'https:$url';
      if (url != null) return url;
    }
  }
  return null;
}

// With hl=id YouTube writes durations as "4.02" instead of "4:02".
final _durationRe = RegExp(r'^\d{1,2}([:.]\d{2}){1,2}$');

int? parseDuration(String? text) {
  if (text == null) return null;
  final t = text.trim();
  if (!_durationRe.hasMatch(t)) return null;
  return t.split(RegExp('[:.]')).fold<int>(0, (acc, p) => acc * 60 + int.parse(p));
}

String? continuationOf(Object? node) {
  final next = findFirst(node, 'nextContinuationData');
  if (next is Map && next['continuation'] is String) return next['continuation'];
  final radio = findFirst(node, 'nextRadioContinuationData');
  if (radio is Map && radio['continuation'] is String) return radio['continuation'];
  final cmd = findFirst(node, 'continuationCommand');
  if (cmd is Map && cmd['token'] is String) return cmd['token'];
  return null;
}

String? _pageType(Object? browseEndpoint) => digStr(browseEndpoint, [
      'browseEndpointContextSupportedConfigs',
      'browseEndpointContextMusicConfig',
      'pageType'
    ]);

bool _isArtistRun(Map run) {
  final id = digStr(run, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
  return id != null && id.startsWith('UC');
}

bool _isAlbumRun(Map run) {
  final id = digStr(run, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
  return id != null && id.startsWith('MPRE');
}

/// Pulls artist / album / duration out of a "Artist • Album • 3:21" line.
({String artist, String? artistId, String? album, String? albumId, int? duration})
    _bylineInfo(List runs) {
  final maps = runs.whereType<Map>().toList();
  final artistRuns = maps.where(_isArtistRun).toList();
  String artist;
  String? artistId;
  if (artistRuns.isNotEmpty) {
    artist = artistRuns.map((r) => r['text'] as String? ?? '').join(', ');
    artistId = digStr(artistRuns.first, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
  } else {
    // Unlinked byline: take the first meaningful chunk that is not a label,
    // a duration or a view count.
    final parts = runsText(runs)
        .split(RegExp(r'\s[•·]\s'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    artist = parts.firstWhere(
      (p) =>
          !_typeLabels.contains(p.toLowerCase()) &&
          parseDuration(p) == null &&
          !RegExp(r'\d').hasMatch(p.split(' ').first),
      orElse: () => '',
    );
  }
  final albumRun = maps.where(_isAlbumRun).firstOrNull;
  int? duration;
  for (final r in maps.reversed) {
    duration = parseDuration(r['text'] as String?);
    if (duration != null) break;
  }
  return (
    artist: artist,
    artistId: artistId,
    album: albumRun?['text'] as String?,
    albumId: albumRun == null
        ? null
        : digStr(albumRun, ['navigationEndpoint', 'browseEndpoint', 'browseId']),
    duration: duration,
  );
}

const _typeLabels = {
  'song', 'lagu', 'video', 'album', 'single', 'ep', 'playlist', 'artist',
  'artis', 'episode', 'podcast', 'profile', 'profil',
};

String _subtitleWithoutLabel(List runs) {
  final text = runsText(runs);
  final parts = text.split(RegExp(r'\s[•·]\s'));
  if (parts.length > 1 && _typeLabels.contains(parts.first.trim().toLowerCase())) {
    return parts.skip(1).join(' • ');
  }
  return text;
}

YtItem? _browseItem(Object? browse, String title, String subtitle, String? thumb) {
  final id = digStr(browse, ['browseId']);
  if (id == null) return null;
  final pageType = _pageType(browse) ?? '';
  YtItemType? type;
  if (pageType.contains('ALBUM') || id.startsWith('MPRE')) {
    type = YtItemType.album;
  } else if (pageType.contains('PLAYLIST') || id.startsWith('VL')) {
    type = YtItemType.playlist;
  } else if (pageType.contains('ARTIST') || pageType.contains('USER_CHANNEL') || id.startsWith('UC')) {
    type = YtItemType.artist;
  }
  if (type == null) return null; // podcasts, episodes, moods…
  return YtItem(type: type, id: id, title: title, subtitle: subtitle, thumbnail: thumb);
}

/// `musicResponsiveListItemRenderer` → item (search rows, playlist tracks,
/// quick picks).
YtItem? parseResponsiveItem(Json r, {String? fallbackThumb, String? fallbackArtist}) {
  final flex = (r['flexColumns'] as List?) ?? const [];
  List runsAt(int i) =>
      (dig(flex, [i, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs']) as List?) ??
      const [];
  final titleRuns = runsAt(0);
  final title = runsText(titleRuns);
  if (title.isEmpty) return null;
  final subtitleRuns = <dynamic>[];
  for (var i = 1; i < flex.length; i++) {
    final runs = runsAt(i);
    if (runs.isEmpty) continue;
    if (subtitleRuns.isNotEmpty) subtitleRuns.add({'text': ' • '});
    subtitleRuns.addAll(runs);
  }
  final thumb = bestThumb(r['thumbnail']) ?? fallbackThumb;

  final videoId = digStr(r, ['playlistItemData', 'videoId']) ??
      digStr(titleRuns, [0, 'navigationEndpoint', 'watchEndpoint', 'videoId']) ??
      digStr(r, [
        'overlay', 'musicItemThumbnailOverlayRenderer', 'content',
        'musicPlayButtonRenderer', 'playNavigationEndpoint', 'watchEndpoint', 'videoId'
      ]);

  final browse = dig(r, ['navigationEndpoint', 'browseEndpoint']);
  if (videoId == null || browse != null) {
    if (browse == null) return null;
    return _browseItem(browse, title, _subtitleWithoutLabel(subtitleRuns), thumb);
  }

  final info = _bylineInfo(subtitleRuns);
  final fixedDuration = parseDuration(runsText(dig(r, [
    'fixedColumns', 0, 'musicResponsiveListItemFixedColumnRenderer', 'text'
  ])));
  final song = Song(
    id: videoId,
    title: title,
    artist: info.artist.isNotEmpty ? info.artist : (fallbackArtist ?? ''),
    artistId: info.artistId,
    album: info.album,
    albumId: info.albumId,
    thumbnail: thumb,
    durationSec: fixedDuration ?? info.duration,
  );
  return YtItem(
    type: YtItemType.song,
    id: videoId,
    title: title,
    subtitle: song.artist,
    thumbnail: thumb,
    song: song,
  );
}

/// `musicTwoRowItemRenderer` → item (home carousels).
YtItem? parseTwoRowItem(Json r) {
  final title = runsText(dig(r, ['title']));
  if (title.isEmpty) return null;
  final subtitleRuns = (dig(r, ['subtitle', 'runs']) as List?) ?? const [];
  final subtitle = _subtitleWithoutLabel(subtitleRuns);
  final thumb = bestThumb(r['thumbnailRenderer']);
  final nav = r['navigationEndpoint'];

  final watch = dig(nav, ['watchEndpoint']);
  final videoId = digStr(watch, ['videoId']);
  if (videoId != null) {
    final info = _bylineInfo(subtitleRuns);
    final song = Song(
      id: videoId,
      title: title,
      artist: info.artist,
      artistId: info.artistId,
      album: info.album,
      albumId: info.albumId,
      thumbnail: thumb,
      durationSec: info.duration,
    );
    return YtItem(
        type: YtItemType.song, id: videoId, title: title,
        subtitle: info.artist.isEmpty ? subtitle : info.artist,
        thumbnail: thumb, song: song);
  }

  final browse = dig(nav, ['browseEndpoint']);
  if (browse != null) return _browseItem(browse, title, subtitle, thumb);

  final watchPlaylist = digStr(nav, ['watchPlaylistEndpoint', 'playlistId']);
  if (watchPlaylist != null) {
    return YtItem(
        type: YtItemType.playlist, id: watchPlaylist, title: title,
        subtitle: subtitle, thumbnail: thumb);
  }
  return null;
}

List<YtItem> _itemsOf(List contents, {String? fallbackThumb, String? fallbackArtist}) {
  final items = <YtItem>[];
  for (final c in contents) {
    if (c is! Map) continue;
    YtItem? item;
    final two = c['musicTwoRowItemRenderer'];
    final resp = c['musicResponsiveListItemRenderer'];
    if (two is Map) item = parseTwoRowItem(two.cast());
    if (resp is Map) {
      item = parseResponsiveItem(resp.cast(),
          fallbackThumb: fallbackThumb, fallbackArtist: fallbackArtist);
    }
    if (item != null) items.add(item);
  }
  return items;
}

HomeFeed parseHome(Json json) {
  final sections = <HomeSection>[];
  for (final shelf in findAll(json, 'musicCarouselShelfRenderer')) {
    if (shelf is! Map) continue;
    final title = runsText(dig(shelf, ['header', 'musicCarouselShelfBasicHeaderRenderer', 'title']));
    final items = _itemsOf((shelf['contents'] as List?) ?? const []);
    if (title.isEmpty || items.isEmpty) continue;
    sections.add(HomeSection(title: title, items: items));
  }
  final sectionList = findFirst(json, 'sectionListRenderer') ??
      findFirst(json, 'sectionListContinuation');
  String? cont;
  final conts = dig(sectionList, ['continuations']);
  if (conts != null) cont = continuationOf(conts);
  return HomeFeed(sections: sections, continuation: cont);
}

SearchPage parseSearch(Json json) {
  final items = <YtItem>[];
  String? cont;
  final shelves = [
    ...findAll(json, 'musicShelfRenderer'),
    ...findAll(json, 'musicShelfContinuation'),
  ];
  for (final shelf in shelves) {
    if (shelf is! Map) continue;
    items.addAll(_itemsOf((shelf['contents'] as List?) ?? const []));
    cont ??= continuationOf(shelf['continuations']) ??
        continuationOf((shelf['contents'] as List?)?.lastOrNull);
  }
  return SearchPage(items: items, continuation: cont);
}

/// First page of a playlist / album browse response.
({CollectionPage page, String? continuation}) parseCollection(Json json, String id) {
  final header = findFirst(json, 'musicResponsiveHeaderRenderer') ??
      findFirst(json, 'musicDetailHeaderRenderer') ??
      findFirst(json, 'musicImmersiveHeaderRenderer') ??
      findFirst(json, 'musicVisualHeaderRenderer');
  final title = runsText(dig(header, ['title']));
  final author = [
    runsText(dig(header, ['straplineTextOne'])),
    digStr(findFirst(header, 'avatarStackViewModel'), ['text', 'content']) ?? '',
    runsText(dig(header, ['subtitle'])),
  ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
  final thumb = bestThumb(dig(header, ['thumbnail'])) ?? bestThumb(header);

  final shelf = findFirst(json, 'musicPlaylistShelfRenderer') ??
      findFirst(json, 'musicShelfRenderer');
  final contents = (dig(shelf, ['contents']) as List?) ?? const [];
  final isAlbum = id.startsWith('MPRE');
  final songs = _songsFrom(contents,
      fallbackThumb: isAlbum ? thumb : null,
      fallbackArtist: isAlbum ? _cleanAuthor(author) : null);
  final cont = continuationOf(dig(shelf, ['continuations'])) ??
      continuationOf(contents.lastOrNull) ??
      continuationOf(dig(json, ['contents', 'twoColumnBrowseResultsRenderer', 'secondaryContents']));
  return (
    page: CollectionPage(
      id: id,
      title: title,
      author: _cleanAuthor(author),
      thumbnail: thumb,
      songs: songs,
      isAlbum: isAlbum,
    ),
    continuation: cont,
  );
}

String _cleanAuthor(String author) => author.split(RegExp(r'\s[•·]\s')).first.trim();

/// Songs from a playlist/album continuation response.
({List<Song> songs, String? continuation}) parseCollectionContinuation(Json json) {
  final contents = <dynamic>[
    ...?(dig(json, ['continuationContents', 'musicPlaylistShelfContinuation', 'contents']) as List?),
    ...?(dig(json, ['continuationContents', 'musicShelfContinuation', 'contents']) as List?),
  ];
  for (final action in (json['onResponseReceivedActions'] as List?) ?? const []) {
    final items = dig(action, ['appendContinuationItemsAction', 'continuationItems']);
    if (items is List) contents.addAll(items);
  }
  final cont = continuationOf(dig(json, ['continuationContents'])) ??
      continuationOf(contents.lastOrNull);
  return (songs: _songsFrom(contents), continuation: cont);
}

List<Song> _songsFrom(List contents, {String? fallbackThumb, String? fallbackArtist}) =>
    _itemsOf(contents, fallbackThumb: fallbackThumb, fallbackArtist: fallbackArtist)
        .map((i) => i.song)
        .whereType<Song>()
        .toList();

/// Radio / watch-next queue from the `next` endpoint.
({List<Song> songs, String? continuation, String? title}) parseNext(Json json) {
  final panel = findFirst(json, 'playlistPanelRenderer') ??
      findFirst(json, 'playlistPanelContinuation');
  final songs = <Song>[];
  for (final c in (dig(panel, ['contents']) as List?) ?? const []) {
    final v = dig(c, ['playlistPanelVideoRenderer']) ??
        dig(c, ['playlistPanelVideoWrapperRenderer', 'primaryRenderer', 'playlistPanelVideoRenderer']);
    if (v is! Map) continue;
    final id = v['videoId'] as String?;
    final title = runsText(v['title']);
    if (id == null || title.isEmpty) continue;
    final info = _bylineInfo((dig(v, ['longBylineText', 'runs']) as List?) ?? const []);
    songs.add(Song(
      id: id,
      title: title,
      artist: info.artist.isNotEmpty ? info.artist : runsText(v['shortBylineText']),
      artistId: info.artistId,
      album: info.album,
      albumId: info.albumId,
      thumbnail: bestThumb(v['thumbnail']),
      durationSec: parseDuration(runsText(v['lengthText'])),
    ));
  }
  final title = dig(panel, ['title']);
  return (
    songs: songs,
    continuation: continuationOf(dig(panel, ['continuations'])),
    title: title is String ? title : (title == null ? null : runsText(title)),
  );
}

List<String> parseSuggestions(Json json) {
  final out = <String>[];
  for (final key in ['searchSuggestionRenderer', 'historySuggestionRenderer']) {
    for (final s in findAll(json, key)) {
      final text = runsText(dig(s, ['suggestion']));
      if (text.isNotEmpty && !out.contains(text)) out.add(text);
    }
  }
  return out;
}
