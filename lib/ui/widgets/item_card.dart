import 'package:flutter/material.dart';

import '../../youtube/models.dart';
import 'artwork.dart';

/// Square (or round, for artists) card used in home carousels.
class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item, required this.onTap, this.width = 150});

  final YtItem item;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final round = item.type == YtItemType.artist;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Column(
          crossAxisAlignment: round ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Artwork(
              src: hiResThumb(item.thumbnail, size: 300),
              size: width,
              radius: 6,
              circle: round,
              icon: switch (item.type) {
                YtItemType.artist => Icons.person_rounded,
                YtItemType.album => Icons.album_rounded,
                YtItemType.playlist => Icons.queue_music_rounded,
                YtItemType.song => Icons.music_note_rounded,
              },
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: round ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              textAlign: round ? TextAlign.center : TextAlign.start,
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
            ),
            if (item.subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                round ? 'Artis' : item.subtitle,
                maxLines: round ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: round ? TextAlign.center : TextAlign.start,
                style: t.bodySmall?.copyWith(height: 1.3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
