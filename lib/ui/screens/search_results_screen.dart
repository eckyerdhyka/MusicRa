import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../youtube/models.dart';
import '../../youtube/playlist_link.dart';
import '../navigation.dart';
import '../widgets/artwork.dart';
import '../widgets/playlist_sheets.dart';
import '../widgets/song_tile.dart';
import '../widgets/states.dart';
import 'collection_screen.dart';

const _filterLabels = {
  SearchFilter.songs: 'Lagu',
  SearchFilter.videos: 'Video',
  SearchFilter.albums: 'Album',
  SearchFilter.playlists: 'Playlist',
};

/// Search box with suggestions/history while typing and filtered results
/// after submitting.
class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({
    super.key,
    this.initialQuery,
    this.initialFilter = SearchFilter.songs,
    this.title,
  });

  final String? initialQuery;
  final SearchFilter initialFilter;

  /// Shown instead of the text field when opened from a genre card.
  final String? title;

  @override
  ConsumerState<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  late SearchFilter _filter = widget.initialFilter;
  String _query = '';
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery?.trim() ?? '';
    _controller = TextEditingController(text: widget.title == null ? _query : '');
    _editing = _query.isEmpty;
    _focus.addListener(() {
      if (_focus.hasFocus && !_editing) setState(() => _editing = true);
    });
    if (_editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String q) {
    final query = q.trim();
    if (query.isEmpty) return;
    // A pasted playlist link goes straight to import.
    if (parsePlaylistId(query) != null || parseAlbumBrowseId(query) != null) {
      _focus.unfocus();
      showImportPlaylistSheet(context, initialText: query).then((id) {
        if (id != null && mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => CollectionScreen(source: LocalPlaylistCollection(id)),
          ));
        }
      });
      return;
    }
    _controller.text = query;
    _focus.unfocus();
    ref.read(libraryProvider).addSearch(query);
    setState(() {
      _query = query;
      _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showTitle = widget.title != null && !_editing;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: showTitle
            ? Text(widget.title!)
            : TextField(
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                onSubmitted: _submit,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Lagu, artis, album, atau link playlist',
                  filled: true,
                  fillColor: AppColors.surfaceHigher,
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 22),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            _controller.clear();
                            _focus.requestFocus();
                            setState(() => _editing = true);
                          },
                        ),
                ),
              ),
        actions: [
          if (showTitle)
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => setState(() {
                _editing = true;
                _focus.requestFocus();
              }),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
      body: _editing ? _buildSuggestions() : _buildResults(),
    );
  }

  Widget _buildSuggestions() {
    final text = _controller.text.trim();
    final t = Theme.of(context).textTheme;
    if (text.isEmpty) {
      final history = ref.watch(searchHistoryProvider).valueOrNull ?? const [];
      if (history.isEmpty) {
        return const EmptyView(
          icon: Icons.manage_search_rounded,
          title: 'Cari lagu favoritmu',
          message: 'Ketik judul, artis, atau tempel link playlist YouTube.',
        );
      }
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Pencarian terakhir', style: t.titleMedium),
          ),
          for (final h in history)
            ListTile(
              leading: const Icon(Icons.history_rounded, color: AppColors.textMuted),
              title: Text(h),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted),
                onPressed: () => ref.read(libraryProvider).removeSearch(h),
              ),
              onTap: () => _submit(h),
            ),
        ],
      );
    }
    final looksLikeLink = parsePlaylistId(text) != null || parseAlbumBrowseId(text) != null;
    final suggestions = looksLikeLink ? const <String>[] : (ref.watch(suggestionsProvider(text)).valueOrNull ?? const []);
    return ListView(
      children: [
        if (looksLikeLink)
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded, color: AppColors.primary),
            title: const Text('Impor playlist dari link ini', style: TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => _submit(text),
          ),
        for (final s in suggestions)
          ListTile(
            leading: const Icon(Icons.search_rounded, color: AppColors.textMuted),
            title: Text(s),
            trailing: IconButton(
              icon: const Icon(Icons.north_west_rounded, size: 18, color: AppColors.textMuted),
              onPressed: () {
                _controller.text = s;
                _controller.selection = TextSelection.collapsed(offset: s.length);
                setState(() {});
              },
            ),
            onTap: () => _submit(s),
          ),
      ],
    );
  }

  Widget _buildResults() {
    final results = ref.watch(searchProvider((_query, _filter)));
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final f in SearchFilter.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(_filterLabels[f]!),
                    selected: f == _filter,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: results.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(searchProvider((_query, _filter))),
            ),
            data: (page) {
              if (page.items.isEmpty) {
                return EmptyView(
                  icon: Icons.search_off_rounded,
                  title: 'Tidak ada hasil untuk "$_query"',
                  message: 'Coba kata kunci lain atau filter berbeda.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: page.items.length,
                itemBuilder: (_, i) {
                  final item = page.items[i];
                  if (item.type == YtItemType.song) {
                    return SongTile(song: item.song!, onTap: () => openYtItem(context, ref, item));
                  }
                  return _CollectionRow(item: item);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CollectionRow extends ConsumerWidget {
  const _CollectionRow({required this.item});

  final YtItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => openYtItem(context, ref, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            Artwork(src: item.thumbnail, size: 56, circle: item.type == YtItemType.artist),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    '${item.type == YtItemType.album ? 'Album' : 'Playlist'} • ${item.subtitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}
