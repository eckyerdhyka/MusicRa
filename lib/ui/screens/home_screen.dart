import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../../youtube/models.dart';
import '../navigation.dart';
import '../widgets/artwork.dart';
import '../widgets/item_card.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_tile.dart';
import '../widgets/states.dart';
import 'collection_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final recent = ref.watch(recentProvider).valueOrNull ?? const [];
    final t = Theme.of(context).textTheme;
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        edgeOffset: top,
        onRefresh: () async {
          ref.invalidate(homeProvider);
          try {
            await ref.read(homeProvider.future);
          } catch (_) {}
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0F3A22), AppColors.bg],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(16, top + 14, 8, 8),
                child: Row(
                  children: [
                    Expanded(child: Text(greeting(), style: t.headlineSmall)),
                    IconButton(
                      tooltip: 'Diunduh',
                      icon: const Icon(Icons.download_for_offline_outlined),
                      onPressed: () => pushInTab(context, const CollectionScreen(source: DownloadsCollection())),
                    ),
                    IconButton(
                      tooltip: 'Lagu yang Disukai',
                      icon: const Icon(Icons.favorite_border_rounded),
                      onPressed: () => pushInTab(context, const CollectionScreen(source: LikedCollection())),
                    ),
                  ],
                ),
              ),
            ),
            if (recent.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    mainAxisExtent: 56,
                  ),
                  itemCount: recent.length.clamp(0, 8),
                  itemBuilder: (_, i) => _QuickTile(
                    song: recent[i],
                    onTap: () => ref
                        .read(audioHandlerProvider)
                        .playSongs(recent, index: i, from: 'Baru diputar'),
                  ),
                ),
              ),
            ...home.when(
              loading: () => [const SliverToBoxAdapter(child: LoadingView())],
              error: (e, _) => [
                SliverToBoxAdapter(
                  child: ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(homeProvider),
                    secondaryLabel: 'Putar lagu unduhan',
                    onSecondary: () => pushInTab(context, const CollectionScreen(source: DownloadsCollection())),
                  ),
                ),
              ],
              data: (sections) => [
                for (final s in sections) SliverToBoxAdapter(child: _Section(section: s)),
              ],
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

/// Spotify's compact "recently played" tile.
class _QuickTile extends ConsumerWidget {
  const _QuickTile({required this.song, required this.onTap});

  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrent = ref.watch(mediaItemProvider.select((m) => m.valueOrNull?.id == song.id));
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => showSongMenu(context, song),
        child: Row(
          children: [
            Artwork(src: songArt(song), size: 56, radius: 0),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isCurrent ? AppColors.primary : AppColors.text,
                      height: 1.25,
                    ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _Section extends ConsumerWidget {
  const _Section({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final songs = section.items.map((i) => i.song).whereType<Song>().toList();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(section.title, style: t.titleLarge),
          ),
          if (section.isSongShelf)
            _SongShelf(songs: songs, title: section.title)
          else
            SizedBox(
              height: 248,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: section.items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) {
                  final item = section.items[i];
                  return ItemCard(
                    item: item,
                    onTap: () => openYtItem(context, ref, item, queue: songs, from: section.title),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// "Quick picks" style shelf: columns of four song rows, scrolled sideways.
class _SongShelf extends ConsumerWidget {
  const _SongShelf({required this.songs, required this.title});

  final List<Song> songs;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const rows = 4;
    final columns = (songs.length / rows).ceil();
    final width = MediaQuery.sizeOf(context).width * 0.86;
    return SizedBox(
      height: rows * 64.0,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const PageScrollPhysics(),
        itemCount: columns,
        itemBuilder: (_, c) => SizedBox(
          width: width,
          child: Column(
            children: [
              for (var r = 0; r < rows && c * rows + r < songs.length; r++)
                SizedBox(
                  height: 64,
                  child: SongTile(
                    song: songs[c * rows + r],
                    onTap: () => ref
                        .read(audioHandlerProvider)
                        .playSongs(songs, index: c * rows + r, from: title),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
