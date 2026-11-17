import 'package:audio_service/audio_service.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import 'data/library_repository.dart';
import 'download/download_manager.dart';
import 'player/audio_handler.dart';
import 'ui/widgets/artwork.dart';
import 'youtube/models.dart';
import 'youtube/youtube_repository.dart';

// Singletons created in main() and injected via overrides.
final youtubeProvider = Provider<YouTubeRepository>((_) => throw UnimplementedError());
final libraryProvider = ChangeNotifierProvider<LibraryRepository>((_) => throw UnimplementedError());
final downloadsProvider = ChangeNotifierProvider<DownloadManager>((_) => throw UnimplementedError());
final audioHandlerProvider = Provider<MusicRaAudioHandler>((_) => throw UnimplementedError());

// ---- YouTube ------------------------------------------------------------------

final homeProvider = FutureProvider<List<HomeSection>>(
  (ref) => ref.watch(youtubeProvider).home(),
);

final searchProvider = FutureProvider.autoDispose.family<SearchPage, (String, SearchFilter)>(
  (ref, args) => ref.watch(youtubeProvider).search(args.$1, args.$2),
);

final suggestionsProvider = FutureProvider.autoDispose.family<List<String>, String>((ref, q) async {
  // Debounce typing: wait, and bail out if the query changed meanwhile.
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  await Future<void>.delayed(const Duration(milliseconds: 220));
  if (cancelled) return const [];
  return ref.watch(youtubeProvider).suggestions(q);
});

final collectionProvider = FutureProvider.autoDispose.family<CollectionPage, String>((ref, id) {
  ref.keepAlive();
  return ref.watch(youtubeProvider).collection(id);
});

// ---- Library ------------------------------------------------------------------

final recentProvider = FutureProvider<List<Song>>(
  (ref) => ref.watch(libraryProvider).recentSongs(limit: 8),
);

final playlistsProvider = FutureProvider<List<LocalPlaylist>>(
  (ref) => ref.watch(libraryProvider).playlists(),
);

final playlistSongsProvider = FutureProvider.family<List<Song>, int>(
  (ref, id) => ref.watch(libraryProvider).playlistSongs(id),
);

final likedSongsProvider = FutureProvider<List<Song>>(
  (ref) => ref.watch(libraryProvider).likedSongs(),
);

final downloadedSongsProvider = FutureProvider<List<Song>>(
  (ref) => ref.watch(libraryProvider).downloadedSongs(),
);

final searchHistoryProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(libraryProvider).searchHistory(),
);

// ---- Player ---------------------------------------------------------------------

final mediaItemProvider = StreamProvider<MediaItem?>(
  (ref) => ref.watch(audioHandlerProvider).mediaItem,
);

final playbackStateProvider = StreamProvider<PlaybackState>(
  (ref) => ref.watch(audioHandlerProvider).playbackState,
);

final queueProvider = StreamProvider<List<MediaItem>>(
  (ref) => ref.watch(audioHandlerProvider).queue,
);

final positionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioHandlerProvider).positionStream,
);

final playSourceProvider = StreamProvider<String?>(
  (ref) => ref.watch(audioHandlerProvider).source,
);

/// Accent colour pulled from a cover, used for player and header gradients.
final paletteProvider = FutureProvider.family<Color?, String>((ref, url) async {
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      ResizeImage(artImageProvider(url), width: 96, height: 96),
      maximumColorCount: 16,
    );
    final c = palette.vibrantColor?.color ??
        palette.dominantColor?.color ??
        palette.mutedColor?.color;
    if (c == null) return null;
    // Keep it dark enough for white text on top.
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness(hsl.lightness.clamp(0.22, 0.38)).withSaturation((hsl.saturation * 0.9).clamp(0.0, 0.85)).toColor();
  } catch (_) {
    return null;
  }
});
