import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../download/download_manager.dart';
import '../../providers.dart';
import '../../youtube/models.dart';
import '../widgets/artwork.dart';
import '../widgets/playlist_sheets.dart';
import '../widgets/song_tile.dart';
import '../widgets/states.dart';

sealed class CollectionSource {
  const CollectionSource();
}

class RemoteCollection extends CollectionSource {
  const RemoteCollection(this.id, {this.title, this.thumbnail});

  /// `VL…` playlist browse id, `MPREb_…` album id or `RD…` radio id.
  final String id;
  final String? title;
  final String? thumbnail;
}

class LocalPlaylistCollection extends CollectionSource {
  const LocalPlaylistCollection(this.id);

  final int id;
}

class LikedCollection extends CollectionSource {
  const LikedCollection();
}

class DownloadsCollection extends CollectionSource {
  const DownloadsCollection();
}

class _Data {
  const _Data({
    required this.title,
    required this.songs,
    this.subtitle,
    this.cover,
    this.covers = const [],
    this.icon,
    this.gradient,
    this.isAlbum = false,
    this.label = 'Playlist',
    this.sourceId,
  });

  final String title;
  final String? subtitle;
  final String? cover;
  final List<String> covers;
  final IconData? icon;
  final List<Color>? gradient;
  final List<Song> songs;
  final bool isAlbum;
  final String label;

  /// YouTube playlist id a local playlist was imported from.
  final String? sourceId;
}

String _normalizeId(String id) => id.startsWith('VL') ? id.substring(2) : id;

class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, required this.source});

  final CollectionSource source;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  final _scrolled = ValueNotifier<double>(0);

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  /// Turns a provider value into page data, keeping the last value on screen
  /// while the provider reloads. `whenData` drops it on reload, which swapped
  /// the whole page for a spinner after every library write and unmounted the
  /// header mid-action (the sync result, for one, was never shown).
  static AsyncValue<_Data> _present<T>(AsyncValue<T> v, _Data Function(T value) build) {
    if (v.hasValue) return AsyncData(build(v.requireValue));
    if (v.hasError) return AsyncError(v.error!, v.stackTrace ?? StackTrace.current);
    return const AsyncLoading();
  }

  AsyncValue<_Data> _watchData() {
    switch (widget.source) {
      case RemoteCollection(:final id, :final title, :final thumbnail):
        return _present(ref.watch(collectionProvider(id)), (p) => _Data(
              title: p.title.isNotEmpty ? p.title : (title ?? ''),
              subtitle: p.author,
              cover: hiResThumb(p.thumbnail ?? thumbnail),
              songs: p.songs,
              isAlbum: p.isAlbum,
              label: p.isAlbum ? 'Album' : 'Playlist',
            ));
      case LocalPlaylistCollection(:final id):
        final songs = ref.watch(playlistSongsProvider(id));
        final playlists = ref.watch(playlistsProvider);
        if (!playlists.hasValue) {
          return playlists.hasError
              ? AsyncError(playlists.error!, playlists.stackTrace ?? StackTrace.current)
              : const AsyncLoading();
        }
        final p = playlists.requireValue.where((p) => p.id == id).firstOrNull;
        return _present(songs, (s) => _Data(
              title: p?.name ?? 'Playlist',
              subtitle: p?.sourceId != null ? 'Diimpor dari YouTube' : 'Playlist kamu',
              cover: p?.thumbnail,
              covers: p?.covers ?? const [],
              songs: s,
              sourceId: p?.sourceId,
            ));
      case LikedCollection():
        return _present(ref.watch(likedSongsProvider), (s) => _Data(
              title: 'Lagu yang Disukai',
              subtitle: 'Disimpan di perangkat ini',
              icon: Icons.favorite_rounded,
              gradient: likedGradient,
              songs: s,
            ));
      case DownloadsCollection():
        final bytes = ref.watch(libraryProvider.select((l) => l.downloadedBytes));
        return _present(ref.watch(downloadedSongsProvider), (s) => _Data(
              title: 'Diunduh',
              subtitle: 'Bisa diputar tanpa internet • ${formatBytes(bytes)}',
              icon: Icons.download_rounded,
              gradient: downloadsGradient,
              songs: s,
            ));
    }
  }

  void _play(_Data d, {int index = 0, bool shuffle = false}) {
    if (d.songs.isEmpty) return;
    ref.read(audioHandlerProvider).playSongs(d.songs, index: index, from: d.title, shuffle: shuffle);
  }

  @override
  Widget build(BuildContext context) {
    final data = _watchData();
    final d = data.valueOrNull;
    final coverSrc = d?.cover ?? d?.covers.firstOrNull ??
        (widget.source is RemoteCollection ? (widget.source as RemoteCollection).thumbnail : null);
    final tint = d?.gradient?.first ??
        (coverSrc == null ? null : ref.watch(paletteProvider(coverSrc)).valueOrNull) ??
        AppColors.surfaceHigher;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ValueListenableBuilder<double>(
          valueListenable: _scrolled,
          builder: (_, offset, __) {
            final p = ((offset - 220) / 80).clamp(0.0, 1.0);
            return AppBar(
              backgroundColor: Color.lerp(Colors.transparent, Color.lerp(tint, Colors.black, 0.45), p),
              title: Opacity(opacity: p, child: Text(d?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis)),
            );
          },
        ),
      ),
      body: data.when(
        loading: () => Center(child: Padding(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          child: const LoadingView(),
        )),
        error: (e, _) => Center(
          child: ErrorView(
            error: e,
            onRetry: () {
              final s = widget.source;
              if (s is RemoteCollection) ref.invalidate(collectionProvider(s.id));
            },
          ),
        ),
        data: (d) => NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.depth == 0) _scrolled.value = n.metrics.pixels;
            return false;
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(data: d, tint: tint, source: widget.source, onPlay: _play)),
              if (widget.source is DownloadsCollection) const SliverToBoxAdapter(child: _ActiveDownloads()),
              if (d.songs.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyView(
                    icon: d.icon ?? Icons.queue_music_rounded,
                    title: switch (widget.source) {
                      LikedCollection() => 'Belum ada lagu yang disukai',
                      DownloadsCollection() => 'Belum ada unduhan',
                      _ => 'Playlist ini masih kosong',
                    },
                    message: switch (widget.source) {
                      LikedCollection() => 'Ketuk ikon hati pada lagu untuk menyimpannya di sini.',
                      DownloadsCollection() => 'Unduh lagu atau satu playlist sekaligus agar bisa diputar tanpa internet.',
                      _ => 'Tambahkan lagu dari menu ⋮ di setiap lagu.',
                    },
                  ),
                )
              else
                SliverList.builder(
                  itemCount: d.songs.length,
                  itemBuilder: (_, i) => SongTile(
                    song: d.songs[i],
                    showArt: !d.isAlbum,
                    number: i + 1,
                    playlistId: switch (widget.source) {
                      LocalPlaylistCollection(:final id) => id,
                      _ => null,
                    },
                    onTap: () => _play(d, index: i),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: d.songs.isEmpty
                      ? null
                      : Text('${d.songs.length} lagu', style: t.bodySmall),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.data, required this.tint, required this.source, required this.onPlay});

  final _Data data;
  final Color tint;
  final CollectionSource source;
  final void Function(_Data d, {int index, bool shuffle}) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final total = data.songs.fold<int>(0, (a, s) => a + (s.durationSec ?? 0));
    final meta = [
      data.label,
      '${data.songs.length} lagu',
      if (total > 0) formatTotal(total),
    ].join(' • ');

    Widget cover;
    if (data.icon != null) {
      cover = GradientIconArt(icon: data.icon!, colors: data.gradient!, size: 200, radius: 6);
    } else if (data.cover != null) {
      cover = Artwork(src: data.cover, size: 220, radius: 6);
    } else {
      cover = MosaicArtwork(covers: data.covers, size: 220, radius: 6);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint, AppColors.bg],
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, top, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              decoration: const BoxDecoration(
                boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 12))],
              ),
              child: cover,
            ),
          ),
          const SizedBox(height: 18),
          Text(data.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.headlineSmall),
          if (data.subtitle != null && data.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(data.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 4),
          Text(meta, style: t.bodySmall),
          const SizedBox(height: 6),
          Row(
            children: [
              _DownloadAllButton(songs: data.songs),
              if (source is RemoteCollection) _SaveButton(source: source as RemoteCollection, data: data),
              if (source is LocalPlaylistCollection)
                _PlaylistMenu(id: (source as LocalPlaylistCollection).id, data: data),
              const Spacer(),
              IconButton(
                iconSize: 28,
                tooltip: 'Putar acak',
                icon: const Icon(Icons.shuffle_rounded, color: AppColors.textMuted),
                onPressed: data.songs.isEmpty ? null : () => onPlay(data, shuffle: true),
              ),
              const SizedBox(width: 4),
              _PlayButton(onTap: data.songs.isEmpty ? null : () => onPlay(data)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null ? AppColors.surfaceHigher : AppColors.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 56,
          height: 56,
          child: Icon(Icons.play_arrow_rounded, size: 34, color: AppColors.onPrimary),
        ),
      ),
    );
  }
}

class _DownloadAllButton extends ConsumerWidget {
  const _DownloadAllButton({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final downloads = ref.watch(downloadsProvider);
    if (songs.isEmpty) return const SizedBox.shrink();
    final done = songs.where((s) => lib.isDownloaded(s.id)).length;
    final pending = songs.where((s) {
      final task = downloads.task(s.id);
      return task != null && task.status != DownloadStatus.failed;
    }).length;

    if (done == songs.length) {
      return IconButton(
        iconSize: 28,
        tooltip: 'Semua lagu sudah diunduh',
        icon: const Icon(Icons.arrow_circle_down_rounded, color: AppColors.primary),
        onPressed: () => showSnack(context, 'Semua lagu sudah tersedia offline'),
      );
    }
    if (pending > 0) {
      return IconButton(
        tooltip: 'Batalkan unduhan',
        icon: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.6, value: done / songs.length),
        ),
        onPressed: () {
          for (final s in songs) {
            downloads.cancel(s.id);
          }
          showSnack(context, 'Unduhan dibatalkan');
        },
      );
    }
    return IconButton(
      iconSize: 28,
      tooltip: 'Unduh semua',
      icon: const Icon(Icons.download_for_offline_outlined, color: AppColors.textMuted),
      onPressed: () {
        final n = downloads.enqueue(songs);
        showSnack(context, 'Mengunduh $n lagu');
      },
    );
  }
}

class _SaveButton extends ConsumerWidget {
  const _SaveButton({required this.source, required this.data});

  final RemoteCollection source;
  final _Data data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(playlistsProvider).valueOrNull?.any(
              (p) => p.sourceId != null && _normalizeId(p.sourceId!) == _normalizeId(source.id),
            ) ??
        false;
    return IconButton(
      iconSize: 28,
      tooltip: saved ? 'Sudah ada di Koleksi' : 'Simpan ke Koleksi',
      icon: Icon(
        saved ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
        color: saved ? AppColors.primary : AppColors.textMuted,
      ),
      onPressed: saved || data.songs.isEmpty
          ? null
          : () async {
              await ref.read(libraryProvider).createPlaylist(
                    data.title,
                    thumbnail: data.cover,
                    sourceId: _normalizeId(source.id),
                    songs: data.songs,
                  );
              if (context.mounted) showSnack(context, 'Disimpan ke Koleksi');
            },
    );
  }
}

class _PlaylistMenu extends ConsumerStatefulWidget {
  const _PlaylistMenu({required this.id, required this.data});

  final int id;
  final _Data data;

  @override
  ConsumerState<_PlaylistMenu> createState() => _PlaylistMenuState();
}

class _PlaylistMenuState extends ConsumerState<_PlaylistMenu> {
  bool _syncing = false;

  /// Pulls the YouTube playlist again and appends songs that are new.
  Future<void> _sync() async {
    if (_syncing) return;
    // Everything used after the await is taken now: the user may leave the
    // page while the playlist loads, and the sync should still finish and
    // report back (the messenger and repositories outlive this widget).
    final messenger = ScaffoldMessenger.of(context);
    final yt = ref.read(youtubeProvider);
    final lib = ref.read(libraryProvider);
    final playlistId = widget.id;
    final sourceId = widget.data.sourceId!;
    void snack(String text, {Duration duration = const Duration(seconds: 3)}) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: duration));

    setState(() => _syncing = true);
    snack('Menyinkronkan dari YouTube…', duration: const Duration(minutes: 2));
    try {
      final page = await yt.collection(sourceId);
      if (page.songs.isEmpty) {
        snack('Playlist di YouTube kosong, privat, atau tidak tersedia.');
        return;
      }
      final added = await lib.addToPlaylist(playlistId, page.songs);
      snack(added == 0
          ? 'Sudah paling baru • ${page.songs.length} lagu di YouTube'
          : '$added lagu baru ditambahkan di akhir playlist');
    } catch (e) {
      snack(describeError(e));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final data = widget.data;
    final lib = ref.read(libraryProvider);
    if (_syncing) {
      return const IconButton(
        tooltip: 'Menyinkronkan…',
        onPressed: null,
        icon: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
      color: AppColors.surfaceHigher,
      onSelected: (v) async {
        switch (v) {
          case 'sync':
            await _sync();
          case 'rename':
            final name = await showPlaylistNameDialog(context,
                title: 'Ganti nama playlist', initial: data.title, action: 'Simpan');
            if (name != null) await lib.renamePlaylist(id, name);
          case 'delete':
            final ok = await showDialog<bool>(
              context: context,
              useRootNavigator: true,
              builder: (ctx) => AlertDialog(
                title: const Text('Hapus playlist?'),
                content: Text('"${data.title}" akan dihapus dari Koleksi. Lagu yang sudah diunduh tetap tersimpan.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal', style: TextStyle(color: AppColors.textMuted)),
                  ),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
                ],
              ),
            );
            if (ok == true) {
              await lib.deletePlaylist(id);
              if (context.mounted) Navigator.of(context).pop();
            }
        }
      },
      itemBuilder: (_) => [
        if (data.sourceId != null)
          const PopupMenuItem(value: 'sync', child: Text('Sinkronkan dari YouTube')),
        const PopupMenuItem(value: 'rename', child: Text('Ganti nama')),
        const PopupMenuItem(value: 'delete', child: Text('Hapus playlist')),
      ],
    );
  }
}

/// Queue of running/failed downloads shown on top of the Diunduh page.
class _ActiveDownloads extends ConsumerWidget {
  const _ActiveDownloads();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsProvider);
    final tasks = downloads.tasks.values.toList();
    if (tasks.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 2),
              child: Row(
                children: [
                  Expanded(child: Text('Sedang diunduh (${tasks.length})', style: t.titleSmall)),
                  TextButton(onPressed: downloads.cancelAll, child: const Text('Batalkan semua')),
                ],
              ),
            ),
            for (final task in tasks.take(30))
              ListTile(
                dense: true,
                leading: Artwork(src: task.song.thumbnail, size: 38),
                title: Text(task.song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: task.status == DownloadStatus.failed
                    ? Text('Gagal: ${task.error ?? ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: AppColors.error))
                    : LinearProgressIndicator(
                        value: task.status == DownloadStatus.queued ? 0 : task.progress,
                        minHeight: 3,
                        backgroundColor: AppColors.surfaceHigher,
                      ),
                trailing: task.status == DownloadStatus.failed
                    ? IconButton(
                        tooltip: 'Coba lagi',
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: () => downloads.enqueue([task.song]),
                      )
                    : IconButton(
                        tooltip: 'Batalkan',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => downloads.cancel(task.song.id),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
