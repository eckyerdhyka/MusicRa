/// Recognises YouTube / YouTube Music playlist and album links pasted by the
/// user and returns the playlist id to import.
library;

/// Returns a playlist id (`PL…`, `OLAK5uy_…`, `RDCLAK…`, `RD…`, `LL`…) or
/// `null` when [input] is not a playlist link.
String? parsePlaylistId(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  // A bare id pasted on its own.
  final bare = RegExp(r'^(VL)?((PL|OLAK5uy_|RDCLAK|RD|UU|FL|OL)[\w-]{10,})$').firstMatch(text);
  if (bare != null) return bare.group(2);

  // Pull the first URL out of share text like "Check this out: https://…".
  final urlMatch = RegExp(r'(https?://)?[\w.-]*(youtube\.com|youtu\.be)/[^\s]*',
          caseSensitive: false)
      .firstMatch(text);
  if (urlMatch == null) return null;
  var raw = urlMatch.group(0)!;
  if (!raw.startsWith('http')) raw = 'https://$raw';
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;

  final list = uri.queryParameters['list'];
  if (list != null && list.isNotEmpty) return _stripVl(list);

  // music.youtube.com/browse/VLPL… (playlist pages opened from the app)
  final segments = uri.pathSegments;
  final browseIdx = segments.indexOf('browse');
  if (browseIdx != -1 && browseIdx + 1 < segments.length) {
    final id = segments[browseIdx + 1];
    if (id.startsWith('VL')) return id.substring(2);
  }
  return null;
}

String _stripVl(String id) => id.startsWith('VL') ? id.substring(2) : id;

/// Album browse ids (`MPREb_…`) are not playlists but can be imported too.
String? parseAlbumBrowseId(String input) {
  final m = RegExp(r'(MPREb_[\w-]+)').firstMatch(input);
  return m?.group(1);
}

/// Mixes (`RD…` except curated `RDCLAK…`) only exist as a radio queue.
bool isRadioPlaylist(String playlistId) =>
    playlistId.startsWith('RD') && !playlistId.startsWith('RDCLAK');
