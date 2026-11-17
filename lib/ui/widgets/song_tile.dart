import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../download/download_manager.dart';
import '../../providers.dart';
import '../../youtube/models.dart';
import 'artwork.dart';
import 'song_menu.dart';

class SongTile extends ConsumerWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.playlistId,
    this.showArt = true,
    this.number,
  });

  final Song song;
  final VoidCallback onTap;

  /// Set inside a local playlist so the menu can offer "remove".
  final int? playlistId;
  final bool showArt;

  /// Track number shown instead of art (albums).
  final int? number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(mediaItemProvider.select((m) => m.valueOrNull?.id == song.id));
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      onLongPress: () => showSongMenu(context, song, playlistId: playlistId),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 4, 7),
        child: Row(
          children: [
            if (showArt)
              Artwork(src: songArt(song), size: 50)
            else
              SizedBox(
                width: 28,
                child: Text('${number ?? ''}',
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: isCurrent ? AppColors.primary : AppColors.textMuted)),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? AppColors.primary : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      DownloadBadge(songId: song.id),
                      Expanded(
                        child: Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
              tooltip: 'Opsi',
              onPressed: () => showSongMenu(context, song, playlistId: playlistId),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small green arrow for downloaded songs, a ring while downloading.
class DownloadBadge extends ConsumerWidget {
  const DownloadBadge({super.key, required this.songId, this.size = 14});

  final String songId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(libraryProvider.select((l) => l.isDownloaded(songId)));
    final task = ref.watch(downloadsProvider.select((d) {
      final t = d.task(songId);
      return t == null ? null : (t.status, t.progress);
    }));
    Widget? icon;
    if (downloaded) {
      icon = Icon(Icons.arrow_circle_down_rounded, size: size, color: AppColors.primary);
    } else if (task != null && task.$1 == DownloadStatus.failed) {
      icon = Icon(Icons.error_outline_rounded, size: size, color: AppColors.error);
    } else if (task != null) {
      icon = SizedBox(
        width: size - 2,
        height: size - 2,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          value: task.$1 == DownloadStatus.queued || task.$2 == 0 ? null : task.$2,
        ),
      );
    }
    if (icon == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(right: 5), child: icon);
  }
}
