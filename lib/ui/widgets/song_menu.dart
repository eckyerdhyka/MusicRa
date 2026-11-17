import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../youtube/models.dart';
import 'artwork.dart';
import 'playlist_sheets.dart';

Future<void> showSongMenu(BuildContext context, Song song, {int? playlistId}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _SongMenu(
      song: song,
      playlistId: playlistId,
      hostContext: context,
      messenger: ScaffoldMessenger.of(context),
    ),
  );
}

class _SongMenu extends ConsumerWidget {
  const _SongMenu({
    required this.song,
    required this.hostContext,
    required this.messenger,
    this.playlistId,
  });

  final Song song;
  final int? playlistId;
  final BuildContext hostContext;

  /// Captured up front: the tile that opened the menu may be gone by the
  /// time an action finishes (e.g. after "remove from playlist").
  final ScaffoldMessengerState messenger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final downloads = ref.watch(downloadsProvider);
    final handler = ref.read(audioHandlerProvider);
    final liked = lib.isLiked(song.id);
    final downloaded = lib.isDownloaded(song.id);
    final downloading = downloads.task(song.id) != null;
    final t = Theme.of(context).textTheme;

    void done(String? message) {
      Navigator.pop(context);
      if (message != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
      }
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Artwork(src: songArt(song), size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                      const SizedBox(height: 2),
                      Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                _Action(
                  icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  iconColor: liked ? AppColors.primary : null,
                  label: liked ? 'Hapus dari Lagu yang Disukai' : 'Tambahkan ke Lagu yang Disukai',
                  onTap: () async {
                    await lib.setLiked(song, !liked);
                    done(liked ? 'Dihapus dari Lagu yang Disukai' : 'Ditambahkan ke Lagu yang Disukai');
                  },
                ),
                _Action(
                  icon: Icons.playlist_add_rounded,
                  label: 'Tambahkan ke playlist',
                  onTap: () {
                    Navigator.pop(context);
                    if (hostContext.mounted) showAddToPlaylistSheet(hostContext, [song]);
                  },
                ),
                _Action(
                  icon: Icons.low_priority_rounded,
                  label: 'Putar berikutnya',
                  onTap: () {
                    handler.playNext(song);
                    done('Diputar berikutnya');
                  },
                ),
                _Action(
                  icon: Icons.queue_music_rounded,
                  label: 'Tambahkan ke antrean',
                  onTap: () {
                    handler.addToQueue(song);
                    done('Ditambahkan ke antrean');
                  },
                ),
                if (downloaded)
                  _Action(
                    icon: Icons.delete_outline_rounded,
                    label: 'Hapus unduhan',
                    onTap: () async {
                      await downloads.delete(song.id);
                      done('Unduhan dihapus');
                    },
                  )
                else if (downloading)
                  _Action(
                    icon: Icons.cancel_outlined,
                    label: 'Batalkan unduhan',
                    onTap: () {
                      downloads.cancel(song.id);
                      done('Unduhan dibatalkan');
                    },
                  )
                else
                  _Action(
                    icon: Icons.download_rounded,
                    label: 'Unduh',
                    onTap: () {
                      downloads.enqueue([song]);
                      done('Mengunduh "${song.title}"');
                    },
                  ),
                _Action(
                  icon: Icons.sensors_rounded,
                  label: 'Putar radio lagu ini',
                  onTap: () {
                    handler.playSong(song);
                    done(null);
                  },
                ),
                if (playlistId != null)
                  _Action(
                    icon: Icons.remove_circle_outline_rounded,
                    label: 'Hapus dari playlist ini',
                    onTap: () async {
                      await lib.removeFromPlaylist(playlistId!, song.id);
                      done('Dihapus dari playlist');
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.iconColor});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: iconColor ?? AppColors.textMuted),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        visualDensity: VisualDensity.compact,
      );
}
