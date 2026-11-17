/// Pure-Dart data models shared by the YouTube layer, the database and the UI.
library;

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId,
    this.album,
    this.albumId,
    this.thumbnail,
    this.durationSec,
    this.localArt,
  });

  /// YouTube videoId.
  final String id;
  final String title;
  final String artist;
  final String? artistId;
  final String? album;
  final String? albumId;
  final String? thumbnail;
  final int? durationSec;

  /// Path of cover art saved next to a downloaded song, used offline.
  final String? localArt;

  Duration? get duration =>
      durationSec == null ? null : Duration(seconds: durationSec!);

  Song copyWith({
    String? title,
    String? artist,
    String? album,
    String? thumbnail,
    int? durationSec,
    String? localArt,
  }) =>
      Song(
        id: id,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        artistId: artistId,
        album: album ?? this.album,
        albumId: albumId,
        thumbnail: thumbnail ?? this.thumbnail,
        durationSec: durationSec ?? this.durationSec,
        localArt: localArt ?? this.localArt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artist_id': artistId,
        'album': album,
        'album_id': albumId,
        'thumbnail': thumbnail,
        'duration': durationSec,
        'local_art': localArt,
      };

  factory Song.fromMap(Map<String, Object?> m) => Song(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        artist: (m['artist'] as String?) ?? '',
        artistId: m['artist_id'] as String?,
        album: m['album'] as String?,
        albumId: m['album_id'] as String?,
        thumbnail: m['thumbnail'] as String?,
        durationSec: m['duration'] as int?,
        localArt: m['local_art'] as String?,
      );

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Song($id, $title — $artist)';
}

enum YtItemType { song, album, playlist, artist }

/// Anything YouTube Music shows in a shelf or a search result.
class YtItem {
  const YtItem({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.thumbnail,
    this.song,
  });

  final YtItemType type;

  /// videoId for songs, browseId for albums/artists, playlist browse id
  /// (`VL…`) or a radio playlistId (`RD…`) for playlists.
  final String id;
  final String title;
  final String subtitle;
  final String? thumbnail;

  /// Set when [type] is [YtItemType.song].
  final Song? song;
}

class HomeSection {
  const HomeSection({required this.title, required this.items});

  final String title;
  final List<YtItem> items;

  /// Shelves made of song rows ("Quick picks") render as a list grid.
  bool get isSongShelf =>
      items.isNotEmpty && items.every((i) => i.type == YtItemType.song);
}

class HomeFeed {
  const HomeFeed({required this.sections, this.continuation});

  final List<HomeSection> sections;
  final String? continuation;
}

class SearchPage {
  const SearchPage({required this.items, this.continuation});

  final List<YtItem> items;
  final String? continuation;
}

/// A YouTube playlist, album or radio, fully loaded.
class CollectionPage {
  const CollectionPage({
    required this.id,
    required this.title,
    required this.songs,
    this.author,
    this.thumbnail,
    this.isAlbum = false,
  });

  final String id;
  final String title;
  final String? author;
  final String? thumbnail;
  final List<Song> songs;
  final bool isAlbum;
}

enum SearchFilter {
  songs('EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D'),
  videos('EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D'),
  albums('EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D'),
  playlists('EgeKAQQoAEABagoQAxAEEAoQCRAF');

  const SearchFilter(this.params);

  final String params;
}

/// Asks the image CDN for a larger square copy of a YouTube Music thumbnail.
String? hiResThumb(String? url, {int size = 544}) {
  if (url == null || url.isEmpty) return url;
  if (url.contains('googleusercontent.com') || url.contains('ggpht.com')) {
    final sized = RegExp(r'=w\d+-h\d+');
    if (sized.hasMatch(url)) return url.replaceFirst(sized, '=w$size-h$size');
    final s = RegExp(r'=s\d+');
    if (s.hasMatch(url)) return url.replaceFirst(s, '=s$size');
  }
  if (url.contains('i.ytimg.com')) {
    return url.replaceFirst(
        RegExp(r'/(default|mqdefault|hqdefault|sddefault)\.jpg'),
        '/hqdefault.jpg');
  }
  return url;
}
