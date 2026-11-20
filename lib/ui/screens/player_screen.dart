import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../download/download_manager.dart';
import '../../providers.dart';
import '../../youtube/models.dart';
import '../widgets/artwork.dart';
import '../widgets/song_menu.dart';
import 'lyrics_screen.dart';
import 'queue_sheet.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(mediaItemProvider).valueOrNull;
    if (item == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final handler = ref.read(audioHandlerProvider);
    final artSrc = item.artUri == null
        ? null
        : (item.artUri!.isScheme('file') ? item.artUri!.toFilePath() : item.artUri.toString());
    final tint = artSrc == null ? null : ref.watch(paletteProvider(artSrc)).valueOrNull;
    final from = ref.watch(playSourceProvider).valueOrNull;
    final t = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);
    final artSize = min(size.width - 48, size.height * 0.42);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [tint ?? AppColors.primaryDeep, Color.lerp(tint ?? AppColors.primaryDeep, AppColors.bg, 0.7)!, AppColors.bg],
              stops: const [0, 0.55, 1],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text('MEMUTAR DARI',
                                style: t.labelSmall?.copyWith(letterSpacing: 1.2, color: Colors.white70)),
                            Text(from ?? 'musicRa',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded),
                        tooltip: 'Opsi',
                        onPressed: () {
                          final song = handler.currentSong;
                          if (song != null) showSongMenu(context, song);
                        },
                      ),
                    ],
                  ),
                  const Spacer(),
                  Hero(
                    tag: 'now-playing-art',
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 32, offset: Offset(0, 14))],
                      ),
                      child: Artwork(
                        src: artSrc,
                        size: artSize,
                        radius: 8,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.headlineSmall?.copyWith(fontSize: 22)),
                            const SizedBox(height: 4),
                            Text(item.artist ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodyLarge?.copyWith(color: Colors.white70)),
                          ],
                        ),
                      ),
                      _DownloadButton(item: item),
                      _LikeButton(songId: item.id),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SeekBar(duration: item.duration),
                  const SizedBox(height: 6),
                  const _Controls(),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        onPressed: () => openLyrics(context),
                        icon: const Icon(Icons.lyrics_outlined),
                        label: const Text('Lirik', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Antrean',
                        icon: const Icon(Icons.queue_music_rounded),
                        onPressed: () => showQueueSheet(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar({this.duration});

  final Duration? duration;

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final total = widget.duration ?? Duration.zero;
    final max = total.inMilliseconds.toDouble();
    final value = (_dragValue ?? pos.inMilliseconds.toDouble()).clamp(0.0, max <= 0 ? 1.0 : max);
    final shown = Duration(milliseconds: value.round());
    final t = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70);
    return Column(
      children: [
        SizedBox(
          height: 28,
          child: Slider(
            min: 0,
            max: max <= 0 ? 1 : max,
            value: max <= 0 ? 0 : value,
            onChanged: max <= 0 ? null : (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) {
              ref.read(audioHandlerProvider).seek(Duration(milliseconds: v.round()));
              setState(() => _dragValue = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(shown), style: t),
              Text(max <= 0 ? '--:--' : formatDuration(total), style: t),
            ],
          ),
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackStateProvider).valueOrNull;
    final handler = ref.read(audioHandlerProvider);
    final playing = state?.playing ?? false;
    final loading = state?.processingState == AudioProcessingState.loading ||
        state?.processingState == AudioProcessingState.buffering;
    final shuffle = state?.shuffleMode == AudioServiceShuffleMode.all;
    final repeat = state?.repeatMode ?? AudioServiceRepeatMode.none;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ToggleIcon(
          icon: Icons.shuffle_rounded,
          active: shuffle,
          tooltip: 'Acak',
          onTap: () => handler.setShuffleMode(
              shuffle ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all),
        ),
        IconButton(
          iconSize: 40,
          tooltip: 'Sebelumnya',
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: handler.skipToPrevious,
        ),
        GestureDetector(
          onTap: playing ? handler.pause : handler.play,
          child: Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: loading && !playing
                ? const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.black),
                  )
                : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 38),
          ),
        ),
        IconButton(
          iconSize: 40,
          tooltip: 'Berikutnya',
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: handler.skipToNext,
        ),
        _ToggleIcon(
          icon: repeat == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
          active: repeat != AudioServiceRepeatMode.none,
          tooltip: 'Ulangi',
          onTap: () => handler.setRepeatMode(switch (repeat) {
            AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
            AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
            _ => AudioServiceRepeatMode.none,
          }),
        ),
      ],
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  const _ToggleIcon({required this.icon, required this.active, required this.onTap, required this.tooltip});

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: active ? AppColors.primary : Colors.white),
          onPressed: onTap,
        ),
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.primary : Colors.transparent,
          ),
        ),
      ],
    );
  }
}

class _LikeButton extends ConsumerWidget {
  const _LikeButton({required this.songId});

  final String songId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(libraryProvider.select((l) => l.isLiked(songId)));
    return IconButton(
      iconSize: 28,
      tooltip: liked ? 'Hapus dari disukai' : 'Suka',
      icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: liked ? AppColors.primary : Colors.white),
      onPressed: () {
        final song = ref.read(audioHandlerProvider).currentSong;
        if (song != null) ref.read(libraryProvider).setLiked(song, !liked);
      },
    );
  }
}

class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(libraryProvider.select((l) => l.isDownloaded(item.id)));
    final task = ref.watch(downloadsProvider.select((d) {
      final t = d.task(item.id);
      return t == null ? null : (t.status, t.progress);
    }));
    final downloads = ref.read(downloadsProvider);

    if (task != null && task.$1 != DownloadStatus.failed) {
      return IconButton(
        tooltip: 'Batalkan unduhan',
        onPressed: () => downloads.cancel(item.id),
        icon: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            value: task.$1 == DownloadStatus.queued || task.$2 == 0 ? null : task.$2,
          ),
        ),
      );
    }
    return IconButton(
      iconSize: 28,
      tooltip: downloaded ? 'Sudah diunduh' : 'Unduh',
      icon: Icon(
        downloaded ? Icons.arrow_circle_down_rounded : Icons.download_for_offline_outlined,
        color: downloaded ? AppColors.primary : Colors.white,
      ),
      onPressed: () {
        if (downloaded) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Lagu ini sudah tersedia offline')));
          return;
        }
        final song = ref.read(audioHandlerProvider).currentSong ??
            Song(id: item.id, title: item.title, artist: item.artist ?? '', thumbnail: item.extras?['thumb'] as String?);
        downloads.enqueue([song]);
      },
    );
  }
}
