import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/library_repository.dart';
import '../../providers.dart';
import '../navigation.dart';
import '../widgets/artwork.dart';
import '../widgets/playlist_sheets.dart';
import '../widgets/states.dart';
import 'collection_screen.dart';

enum _Filter { playlists, downloads }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _Filter? _filter;

  Future<void> _import() async {
    final id = await showImportPlaylistSheet(context);
    if (id != null && mounted) {
      pushInTab(context, CollectionScreen(source: LocalPlaylistCollection(id)));
    }
  }

  Future<void> _create() async {
    final name = await showPlaylistNameDialog(context);
    if (name == null) return;
    final id = await ref.read(libraryProvider).createPlaylist(name);
    if (mounted) pushInTab(context, CollectionScreen(source: LocalPlaylistCollection(id)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lib = ref.watch(libraryProvider);
    final playlists = ref.watch(playlistsProvider);
    final pending = ref.watch(downloadsProvider.select((d) => d.pendingCount));
    final showPlaylists = _filter != _Filter.downloads;
    final showDownloads = _filter != _Filter.playlists;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 4, 6),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.primary,
                      child: Text('R',
                          style: TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Koleksi Kamu', style: t.headlineSmall)),
                    IconButton(
                      tooltip: 'Tempel link playlist',
                      icon: const Icon(Icons.add_link_rounded),
                      onPressed: _import,
                    ),
                    IconButton(
                      tooltip: 'Buat playlist',
                      icon: const Icon(Icons.add_rounded, size: 28),
                      onPressed: _create,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Row(
                  children: [
                    if (_filter != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ActionChip(
                          label: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(() => _filter = null),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    for (final f in _Filter.values)
                      if (_filter == null || _filter == f)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(f == _Filter.playlists ? 'Playlist' : 'Diunduh'),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = _filter == f ? null : f),
                          ),
                        ),
                  ],
                ),
              ),
            ),
            if (showPlaylists)
              SliverToBoxAdapter(
                child: _LibraryRow(
                  art: const GradientIconArt(icon: Icons.favorite_rounded, colors: likedGradient, size: 64),
                  title: 'Lagu yang Disukai',
                  subtitle: 'Playlist • ${lib.likedCount} lagu',
                  onTap: () => pushInTab(context, const CollectionScreen(source: LikedCollection())),
                ),
              ),
            if (showDownloads)
              SliverToBoxAdapter(
                child: _LibraryRow(
                  art: const GradientIconArt(icon: Icons.download_rounded, colors: downloadsGradient, size: 64),
                  title: 'Diunduh',
                  subtitle: pending > 0
                      ? 'Mengunduh $pending lagu…'
                      : '${lib.downloadCount} lagu • ${formatBytes(lib.downloadedBytes)}',
                  subtitleColor: pending > 0 ? AppColors.primary : null,
                  onTap: () => pushInTab(context, const CollectionScreen(source: DownloadsCollection())),
                ),
              ),
            if (showPlaylists)
              ...playlists.when(
                loading: () => [const SliverToBoxAdapter(child: LoadingView())],
                error: (e, _) => [SliverToBoxAdapter(child: ErrorView(error: e))],
                data: (list) => [
                  SliverList.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => _PlaylistRow(playlist: list[i]),
                  ),
                  if (list.isEmpty) SliverToBoxAdapter(child: _ImportCallout(onTap: _import)),
                ],
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.art,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.subtitleColor,
  });

  final Widget art;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            art,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: subtitleColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist});

  final LocalPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final p = playlist;
    return _LibraryRow(
      art: p.thumbnail != null
          ? Artwork(src: p.thumbnail, size: 64)
          : MosaicArtwork(covers: p.covers, size: 64),
      title: p.name,
      subtitle: [
        'Playlist',
        '${p.songCount} lagu',
        if (p.sourceId != null) 'dari YouTube',
      ].join(' • '),
      onTap: () => pushInTab(context, CollectionScreen(source: LocalPlaylistCollection(p.id))),
    );
  }
}

class _ImportCallout extends StatelessWidget {
  const _ImportCallout({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFF103D25), AppColors.surfaceHigh],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Punya playlist di YouTube?', style: t.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Salin link playlist dari YouTube atau YouTube Music, lalu tempel di sini. '
              'Semua lagunya langsung jadi playlist di musicRa — tanpa login.',
              style: t.bodySmall?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.content_paste_rounded, size: 18),
              label: const Text('Tempel link playlist'),
            ),
          ],
        ),
      ),
    );
  }
}
