import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../youtube/models.dart';
import '../../youtube/playlist_link.dart';
import 'artwork.dart';
import 'states.dart';

/// Asks for a playlist name. Returns null when cancelled.
Future<String?> showPlaylistNameDialog(BuildContext context,
    {String title = 'Beri nama playlist', String initial = '', String action = 'Buat'}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Playlist saya'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal', style: TextStyle(color: AppColors.textMuted)),
        ),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            Navigator.pop(ctx, v.isEmpty ? null : v);
          },
          child: Text(action),
        ),
      ],
    ),
  );
}

Future<void> showAddToPlaylistSheet(BuildContext context, List<Song> songs) {
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _AddToPlaylistSheet(songs: songs, messenger: messenger),
  );
}

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.songs, required this.messenger});

  final List<Song> songs;
  final ScaffoldMessengerState messenger;

  void _snack(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final lib = ref.read(libraryProvider);
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tambahkan ke playlist', style: t.titleMedium),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigher,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.add_rounded),
              ),
              title: const Text('Playlist baru', style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () async {
                final name = await showPlaylistNameDialog(context);
                if (name == null) return;
                await lib.createPlaylist(name, songs: songs);
                if (context.mounted) Navigator.pop(context);
                _snack('Ditambahkan ke "$name"');
              },
            ),
            Flexible(
              child: playlists.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(error: e),
                data: (list) => ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in list)
                      ListTile(
                        leading: p.thumbnail != null
                            ? Artwork(src: p.thumbnail, size: 48)
                            : MosaicArtwork(covers: p.covers, size: 48),
                        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${p.songCount} lagu', style: t.bodySmall),
                        onTap: () async {
                          final added = await lib.addToPlaylist(p.id, songs);
                          if (context.mounted) Navigator.pop(context);
                          _snack(added == 0
                              ? 'Sudah ada di "${p.name}"'
                              : 'Ditambahkan ke "${p.name}"');
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paste-a-link import. Resolves to the id of the new local playlist.
Future<int?> showImportPlaylistSheet(BuildContext context, {String? initialText}) {
  return showModalBottomSheet<int>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => ImportPlaylistSheet(initialText: initialText),
  );
}

class ImportPlaylistSheet extends ConsumerStatefulWidget {
  const ImportPlaylistSheet({super.key, this.initialText});

  final String? initialText;

  @override
  ConsumerState<ImportPlaylistSheet> createState() => _ImportPlaylistSheetState();
}

class _ImportPlaylistSheetState extends ConsumerState<ImportPlaylistSheet> {
  final _controller = TextEditingController();
  bool _fromClipboard = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _controller.text = widget.initialText!;
    } else {
      _readClipboard(auto: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String? _idFrom(String text) => parsePlaylistId(text) ?? parseAlbumBrowseId(text);

  Future<void> _readClipboard({bool auto = false}) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (_idFrom(text) != null) {
      setState(() {
        _controller.text = text;
        _fromClipboard = auto;
        _error = null;
      });
    } else if (!auto) {
      setState(() => _error = 'Clipboard tidak berisi link playlist.');
    }
  }

  Future<void> _import() async {
    final text = _controller.text.trim();
    final id = _idFrom(text);
    if (id == null) {
      setState(() => _error = 'Link tidak dikenali. Gunakan link playlist atau album dari YouTube / YouTube Music.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await ref.read(youtubeProvider).collection(id);
      if (page.songs.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'Playlist kosong, privat, atau tidak tersedia.';
        });
        return;
      }
      final name = page.title.trim().isEmpty ? 'Playlist impor' : page.title.trim();
      final playlistId = await ref.read(libraryProvider).createPlaylist(
            name,
            thumbnail: hiResThumb(page.thumbnail),
            sourceId: id,
            songs: page.songs,
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, playlistId);
      messenger.showSnackBar(SnackBar(content: Text('"$name" diimpor • ${page.songs.length} lagu')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '${describeError(e)} Playlist privat tidak bisa diimpor.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const GradientIconArt(icon: Icons.link_rounded, colors: likedGradient, size: 44, radius: 10),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Impor playlist YouTube', style: t.titleLarge),
                        Text('Tempel link, jadi playlist di musicRa', style: t.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                enabled: !_busy,
                minLines: 1,
                maxLines: 3,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {
                  _fromClipboard = false;
                  _error = null;
                }),
                onSubmitted: (_) => _import(),
                decoration: InputDecoration(
                  hintText: 'https://music.youtube.com/playlist?list=…',
                  suffixIcon: IconButton(
                    tooltip: 'Tempel',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: _busy ? null : () => _readClipboard(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Text(_error!, style: t.bodySmall?.copyWith(color: AppColors.error))
              else if (_fromClipboard)
                Row(children: [
                  const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text('Link playlist terdeteksi dari clipboard',
                      style: t.bodySmall?.copyWith(color: AppColors.primary)),
                ])
              else
                Text('Mendukung link playlist, album, dan mix dari YouTube & YouTube Music.',
                    style: t.bodySmall),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy || _controller.text.trim().isEmpty ? null : _import,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                        )
                      : const Icon(Icons.playlist_add_rounded),
                  label: Text(_busy ? 'Mengambil daftar lagu…' : 'Impor playlist'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
