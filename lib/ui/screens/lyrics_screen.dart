import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../lyrics/lyrics.dart';
import '../../providers.dart';
import '../../youtube/models.dart';
import '../widgets/states.dart';

void openLyrics(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => const LyricsScreen(),
    transitionsBuilder: (_, anim, __, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
      child: child,
    ),
  ));
}

/// Full-screen lyrics of the song that is playing. Synced lyrics follow the
/// music and a tap on a line jumps there; unsynced ones are shown as text.
class LyricsScreen extends ConsumerWidget {
  const LyricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(mediaItemProvider).valueOrNull;
    if (item == null) return const Scaffold(body: SizedBox.shrink());
    final current = ref.read(audioHandlerProvider).currentSong;
    var song = current != null && current.id == item.id
        ? current
        : Song(id: item.id, title: item.title, artist: item.artist ?? '', album: item.album);
    if (song.durationSec == null && item.duration != null) {
      song = song.copyWith(durationSec: item.duration!.inSeconds);
    }
    final artSrc = item.artUri == null
        ? null
        : (item.artUri!.isScheme('file') ? item.artUri!.toFilePath() : item.artUri.toString());
    final tint = artSrc == null ? null : ref.watch(paletteProvider(artSrc)).valueOrNull;
    final bg = Color.lerp(tint ?? AppColors.primaryDeep, Colors.black, 0.1)!;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        Text(item.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodyMedium?.copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _LyricsBody(key: ValueKey(song.id), song: song)),
            _Controls(duration: item.duration),
          ],
        ),
      ),
    );
  }
}

class _LyricsBody extends ConsumerStatefulWidget {
  const _LyricsBody({super.key, required this.song});

  final Song song;

  @override
  ConsumerState<_LyricsBody> createState() => _LyricsBodyState();
}

class _LyricsBodyState extends ConsumerState<_LyricsBody> {
  /// Keys of the rendered lines, to scroll the sung one into view.
  List<GlobalKey> _keys = const [];
  int _active = -1;

  /// Auto-scroll pauses for a moment while the user reads ahead or back.
  DateTime _userScrolledAt = DateTime(0);

  /// Sung lines light up slightly early, like reading along.
  static const _lead = Duration(milliseconds: 250);

  void _follow({bool jump = false}) {
    if (!jump && DateTime.now().difference(_userScrolledAt) < const Duration(seconds: 3)) return;
    final i = _active < 0 ? 0 : _active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || i >= _keys.length) return;
      final ctx = _keys[i].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: jump ? Duration.zero : const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _seekTo(LyricLine line) {
    final handler = ref.read(audioHandlerProvider);
    handler.seek(line.time);
    if (!handler.playbackState.value.playing) handler.play();
    _userScrolledAt = DateTime(0);
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = ref.watch(lyricsProvider(widget.song));

    ref.listen<AsyncValue<Duration>>(positionProvider, (_, next) {
      final l = ref.read(lyricsProvider(widget.song)).valueOrNull;
      final pos = next.valueOrNull;
      if (l == null || !l.synced || pos == null) return;
      final i = l.lineAt(pos + _lead);
      if (i != _active) {
        setState(() => _active = i);
        _follow();
      }
    });

    return lyrics.when(
      loading: () => const _Message(icon: Icons.lyrics_outlined, title: 'Mencari lirik…', loading: true),
      error: (e, _) => Center(
        child: ErrorView(error: e, onRetry: () => ref.invalidate(lyricsProvider(widget.song))),
      ),
      data: (l) {
        if (l == null) {
          return const _Message(
            icon: Icons.lyrics_outlined,
            title: 'Lirik belum tersedia',
            message: 'Belum ada lirik untuk lagu ini.',
          );
        }
        if (l.instrumental) {
          return const _Message(icon: Icons.music_note_rounded, title: 'Lagu instrumental');
        }
        if (_keys.length != l.lines.length) {
          _keys = List.generate(l.lines.length, (_) => GlobalKey());
          if (l.synced) {
            _active = l.lineAt(ref.read(audioHandlerProvider).position + _lead);
            _follow(jump: true);
          }
        }
        return _buildLines(l);
      },
    );
  }

  Widget _buildLines(Lyrics l) {
    final t = Theme.of(context).textTheme;
    final base = t.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w800, height: 1.3);
    return NotificationListener<UserScrollNotification>(
      // Only drags send these (not our own ensureVisible), including the
      // final idle one, so the pause counts from when the finger lifts.
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        return false;
      },
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.sizeOf(context).height * 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!l.synced)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text('Lirik ini tidak mengikuti waktu lagu.',
                    style: t.bodySmall?.copyWith(color: Colors.white60)),
              ),
            for (var i = 0; i < l.lines.length; i++)
              l.synced
                  ? GestureDetector(
                      key: _keys[i],
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _seekTo(l.lines[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 260),
                          style: base!.copyWith(
                            color: i == _active
                                ? Colors.white
                                : (i < _active ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.35)),
                          ),
                          child: Text(l.lines[i].isGap ? '♪' : l.lines[i].text),
                        ),
                      ),
                    )
                  : Padding(
                      key: _keys[i],
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(l.lines[i].text,
                          style: base?.copyWith(fontSize: 20, color: Colors.white.withOpacity(0.9))),
                    ),
            const SizedBox(height: 28),
            Text('Lirik dari ${l.source}', style: t.bodySmall?.copyWith(color: Colors.white60)),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, this.message, this.loading = false});

  final IconData icon;
  final String title;
  final String? message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading
                ? const SizedBox(
                    width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
                : Icon(icon, size: 52, color: Colors.white54),
            const SizedBox(height: 16),
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: t.bodyMedium?.copyWith(color: Colors.white70), textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

/// Progress and play/pause, so the lyrics page works on its own.
class _Controls extends ConsumerWidget {
  const _Controls({this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final playing = ref.watch(playbackStateProvider.select((s) => s.valueOrNull?.playing ?? false));
    final handler = ref.read(audioHandlerProvider);
    final total = duration ?? Duration.zero;
    final value = total.inMilliseconds <= 0 ? 0.0 : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 3,
              backgroundColor: Colors.white24,
              color: Colors.white,
            ),
          ),
          Row(
            children: [
              Text(formatDuration(pos), style: small),
              const Spacer(),
              IconButton(
                iconSize: 44,
                tooltip: playing ? 'Jeda' : 'Putar',
                icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                onPressed: playing ? handler.pause : handler.play,
              ),
              const Spacer(),
              Text(total.inMilliseconds <= 0 ? '--:--' : formatDuration(total), style: small),
            ],
          ),
        ],
      ),
    );
  }
}
