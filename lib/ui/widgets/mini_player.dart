import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../navigation.dart';
import 'artwork.dart';

/// Floating now-playing bar above the tab bar; tints itself with the cover.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(mediaItemProvider).valueOrNull;
    if (item == null) return const SizedBox.shrink();
    final state = ref.watch(playbackStateProvider).valueOrNull;
    final handler = ref.read(audioHandlerProvider);
    final art = item.artUri?.toString();
    final artSrc = art == null ? null : (item.artUri!.isScheme('file') ? item.artUri!.toFilePath() : art);
    final tint = artSrc == null ? null : ref.watch(paletteProvider(artSrc)).valueOrNull;
    final playing = state?.playing ?? false;
    final loading = state?.processingState == AudioProcessingState.loading ||
        state?.processingState == AudioProcessingState.buffering;
    final t = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => openPlayer(context),
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) openPlayer(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        height: 58,
        decoration: BoxDecoration(
          color: Color.lerp(tint ?? AppColors.surfaceHigher, Colors.black, 0.25),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 4, 9),
              child: Row(
                children: [
                  Hero(tag: 'now-playing-art', child: Artwork(src: artSrc, size: 40)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(item.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall?.copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                  _LikeButton(songId: item.id),
                  SizedBox(
                    width: 44,
                    // Stays tappable while loading, so a stalled song can
                    // always be started again.
                    child: IconButton(
                      tooltip: playing ? 'Jeda' : 'Putar',
                      onPressed: playing ? handler.pause : handler.play,
                      icon: loading && !playing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                            )
                          : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 0,
              child: _ProgressLine(duration: item.duration),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressLine extends ConsumerWidget {
  const _ProgressLine({this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final total = duration?.inMilliseconds ?? 0;
    final value = total <= 0 ? 0.0 : (pos.inMilliseconds / total).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 2,
        backgroundColor: Colors.white24,
        color: Colors.white,
      ),
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
      tooltip: liked ? 'Hapus dari disukai' : 'Suka',
      icon: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: liked ? AppColors.primary : Colors.white,
      ),
      onPressed: () {
        final song = ref.read(audioHandlerProvider).currentSong;
        if (song != null) ref.read(libraryProvider).setLiked(song, !liked);
      },
    );
  }
}
