import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../youtube/models.dart';
import 'screens/collection_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_results_screen.dart';

/// Pushes inside the current tab, so the tab bar and mini player stay.
Future<T?> pushInTab<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

void openPlayer(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => const PlayerScreen(),
    transitionsBuilder: (_, anim, __, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
      child: child,
    ),
  ));
}

/// What tapping a YouTube item does everywhere in the app.
void openYtItem(BuildContext context, WidgetRef ref, YtItem item, {List<Song>? queue, String? from}) {
  switch (item.type) {
    case YtItemType.song:
      final handler = ref.read(audioHandlerProvider);
      if (queue != null && queue.length > 1) {
        final i = queue.indexWhere((s) => s.id == item.id);
        handler.playSongs(queue, index: i < 0 ? 0 : i, from: from);
      } else {
        handler.playSong(item.song!);
      }
    case YtItemType.album:
    case YtItemType.playlist:
      pushInTab(
        context,
        CollectionScreen(
          source: RemoteCollection(item.id, title: item.title, thumbnail: item.thumbnail),
        ),
      );
    case YtItemType.artist:
      pushInTab(context, SearchResultsScreen(initialQuery: item.title));
  }
}
