/// Lyrics model, LRC parsing and the title clean-up used to look songs up.
/// Pure Dart.
library;

class LyricLine {
  const LyricLine(this.time, this.text);

  /// When the line starts. Always zero for unsynced lyrics.
  final Duration time;
  final String text;

  /// An instrumental break between sung lines.
  bool get isGap => text.trim().isEmpty;

  @override
  bool operator ==(Object other) => other is LyricLine && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);

  @override
  String toString() => 'LyricLine($time, $text)';
}

class Lyrics {
  const Lyrics({
    required this.lines,
    required this.synced,
    required this.source,
    this.instrumental = false,
  });

  /// Plain text, one line per row.
  factory Lyrics.plain(String text, {required String source}) => Lyrics(
        lines: _trimBlankEdges(text.replaceAll('\r', '').split('\n'))
            .map((l) => LyricLine(Duration.zero, l.trim()))
            .toList(),
        synced: false,
        source: source,
      );

  final List<LyricLine> lines;

  /// Each line carries the time it is sung.
  final bool synced;

  /// Where they came from, shown under the lyrics.
  final String source;

  /// The track has no vocals.
  final bool instrumental;

  /// Index of the line being sung at [position], or -1 before the first one.
  int lineAt(Duration position) {
    if (!synced || lines.isEmpty || position < lines.first.time) return -1;
    var lo = 0, hi = lines.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (lines[mid].time <= position) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  Map<String, Object?> toJson() => {
        'synced': synced,
        'source': source,
        'instrumental': instrumental,
        'lines': [for (final l in lines) [l.time.inMilliseconds, l.text]],
      };

  factory Lyrics.fromJson(Map<String, Object?> json) => Lyrics(
        synced: json['synced'] == true,
        source: (json['source'] as String?) ?? '',
        instrumental: json['instrumental'] == true,
        lines: [
          for (final l in (json['lines'] as List?) ?? const [])
            if (l is List && l.length == 2)
              LyricLine(Duration(milliseconds: (l[0] as num).toInt()), '${l[1]}'),
        ],
      );
}

List<String> _trimBlankEdges(List<String> lines) {
  var start = 0, end = lines.length;
  while (start < end && lines[start].trim().isEmpty) {
    start++;
  }
  while (end > start && lines[end - 1].trim().isEmpty) {
    end--;
  }
  return lines.sublist(start, end);
}

final _stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
final _wordStamp = RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>');

/// Instrumental breaks shorter than this are dropped: a "♪" flashing between
/// two sung lines is just noise.
const _minGap = Duration(seconds: 4);

/// Parses line-synced LRC (`[mm:ss.xx] text`). Tag lines such as `[ar:…]`
/// carry no timestamp and are skipped; a line may have several stamps
/// (repeated chorus) and enhanced word stamps (`<mm:ss.xx>`) are removed.
List<LyricLine> parseLrc(String lrc) {
  final all = <LyricLine>[];
  for (final raw in lrc.split('\n')) {
    final line = raw.trim();
    final times = <Duration>[];
    var rest = line;
    while (true) {
      final m = _stamp.matchAsPrefix(rest);
      if (m == null) break;
      final frac = m.group(3) ?? '0';
      final ms = switch (frac.length) { 1 => int.parse(frac) * 100, 2 => int.parse(frac) * 10, _ => int.parse(frac) };
      times.add(Duration(minutes: int.parse(m.group(1)!), seconds: int.parse(m.group(2)!), milliseconds: ms));
      rest = rest.substring(m.end);
    }
    if (times.isEmpty) continue;
    final text = rest.replaceAll(_wordStamp, '').replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final t in times) {
      all.add(LyricLine(t, text));
    }
  }
  all.sort((a, b) => a.time.compareTo(b.time));

  final out = <LyricLine>[];
  for (var i = 0; i < all.length; i++) {
    final l = all[i];
    if (l.isGap) {
      if (out.isEmpty) continue; // nothing to mark before the first line
      if (out.last.isGap) continue;
      final next = i + 1 < all.length ? all[i + 1] : null;
      if (next != null && next.time - l.time < _minGap) continue;
    }
    out.add(l);
  }
  while (out.isNotEmpty && out.last.isGap) {
    out.removeLast();
  }
  return out;
}

// "(Official Music Video)", "[Lirik]", "(feat. X)", "(Video Lirik)", "(Audio)", …
final _bracketNoise = RegExp(
  r'\s*[(\[【][^)\]】]*\b(official|video|audio|lyrics?|lirik|lyrical|visuali[sz]er|mv|m/v|hd|hq|4k|explicit|remaster(?:ed)?|from|feat\.?|ft\.?|prod\.?)\b[^)\]】]*[)\]】]',
  caseSensitive: false,
);
final _featTail = RegExp(r'\s+(feat\.?|ft\.?)\s.*$', caseSensitive: false);

/// The plain song name LRCLIB indexes, from a YouTube title such as
/// `Tulus - Hati-Hati di Jalan (Official Music Video) | 2022`.
String cleanTitle(String title, String artist) {
  var t = title.split(' | ').first;
  t = t.replaceAll(_bracketNoise, '').replaceAll(_featTail, '');
  // Video uploads are often titled "Artist - Song".
  final dash = t.indexOf(' - ');
  if (dash > 0) {
    final left = t.substring(0, dash).toLowerCase().trim();
    final a = primaryArtist(artist).toLowerCase();
    if (a.isNotEmpty && (left.contains(a) || a.contains(left))) t = t.substring(dash + 3);
  }
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? title.trim() : t;
}

/// First credited artist: "Wisin, Young Miko" → "Wisin".
String primaryArtist(String artist) {
  final a = artist
      .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
      .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
      .split(RegExp(r'\s*(,|&|\bx\b|\bfeat\.?|\bft\.?)\s*', caseSensitive: false))
      .first
      .trim();
  return a.isEmpty ? artist.trim() : a;
}
