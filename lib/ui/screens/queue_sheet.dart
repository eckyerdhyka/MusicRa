import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../widgets/artwork.dart';

Future<void> showQueueSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => const _QueueSheet(),
    );

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider).valueOrNull ?? const [];
    final current = ref.watch(playbackStateProvider.select((s) => s.valueOrNull?.queueIndex)) ?? 0;
    final handler = ref.read(audioHandlerProvider);
    final t = Theme.of(context).textTheme;
    final upcoming = queue.length - current - 1;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(child: Text('Antrean', style: t.titleLarge)),
                Text('$upcoming berikutnya', style: t.bodySmall),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: queue.length,
              buildDefaultDragHandles: false,
              onReorder: (from, to) {
                // ReorderableListView reports the target before removal.
                handler.moveQueueItem(from, to > from ? to - 1 : to);
              },
              itemBuilder: (context, i) {
                final m = queue[i];
                final isCurrent = i == current;
                final art = m.artUri == null
                    ? null
                    : (m.artUri!.isScheme('file') ? m.artUri!.toFilePath() : m.artUri.toString());
                final tile = ListTile(
                  key: ValueKey('${m.id}-$i'),
                  contentPadding: const EdgeInsets.only(left: 20, right: 8),
                  leading: Artwork(src: art, size: 44),
                  title: Text(
                    m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? AppColors.primary : (i < current ? AppColors.textFaint : null),
                    ),
                  ),
                  subtitle: Text(m.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                  onTap: () => handler.skipToQueueItem(i),
                  trailing: isCurrent
                      ? const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Icon(Icons.graphic_eq_rounded, color: AppColors.primary),
                        )
                      : ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.drag_handle_rounded, color: AppColors.textMuted),
                          ),
                        ),
                );
                if (isCurrent) return KeyedSubtree(key: ValueKey('${m.id}-$i'), child: tile);
                return Dismissible(
                  key: ValueKey('${m.id}-$i'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: AppColors.error.withOpacity(0.25),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                  onDismissed: (_) => handler.removeFromQueue(i),
                  child: tile,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
