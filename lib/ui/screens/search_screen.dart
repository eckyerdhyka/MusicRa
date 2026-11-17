import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../youtube/models.dart';
import '../navigation.dart';
import 'search_results_screen.dart';

class _Genre {
  const _Genre(this.title, this.query, this.color, this.icon);

  final String title;
  final String query;
  final Color color;
  final IconData icon;
}

const _genres = [
  _Genre('Pop Indonesia', 'lagu pop indonesia terpopuler', Color(0xFF16834A), Icons.mic_external_on_rounded),
  _Genre('Hits Terbaru', 'lagu hits terbaru', Color(0xFFD6245F), Icons.local_fire_department_rounded),
  _Genre('Galau', 'lagu galau indonesia', Color(0xFF3E6F8E), Icons.water_drop_rounded),
  _Genre('Dangdut', 'dangdut hits', Color(0xFFC94A0E), Icons.celebration_rounded),
  _Genre('K-Pop', 'kpop hits', Color(0xFF8559A5), Icons.auto_awesome_rounded),
  _Genre('Hip-Hop', 'hip hop hits', Color(0xFFA85A0B), Icons.headphones_rounded),
  _Genre('Indie', 'indie indonesia', Color(0xFF4A6F96), Icons.forest_rounded),
  _Genre('Rock', 'rock indonesia', Color(0xFFC81D2D), Icons.bolt_rounded),
  _Genre('Santai & Lo-fi', 'lofi santai', Color(0xFF117A3E), Icons.nightlight_round),
  _Genre('Olahraga', 'lagu semangat olahraga', Color(0xFF5F6B66), Icons.directions_run_rounded),
  _Genre('Jazz', 'jazz santai', Color(0xFF223A6B), Icons.piano_rounded),
  _Genre('Religi', 'lagu religi islami', Color(0xFF237A63), Icons.mosque_rounded),
  _Genre('Akustik', 'lagu akustik indonesia', Color(0xFF8A6A2E), Icons.music_note_rounded),
  _Genre('EDM', 'edm hits', Color(0xFF1162C9), Icons.equalizer_rounded),
];

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Text('Cari', style: t.headlineMedium),
            ),
          ),
          SliverPersistentHeader(pinned: true, delegate: _SearchBoxHeader()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Text('Jelajahi semua', style: t.titleMedium),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.75,
              ),
              itemCount: _genres.length,
              itemBuilder: (_, i) => _GenreCard(genre: _genres[i]),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _SearchBoxHeader extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 64;

  @override
  double get maxExtent => 64;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // A persistent header's child must fill the extent it declares.
    return Container(
      height: maxExtent,
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => pushInTab(context, const SearchResultsScreen()),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: Colors.black87, size: 26),
                SizedBox(width: 10),
                Text('Mau dengar apa?',
                    style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchBoxHeader old) => false;
}

class _GenreCard extends StatelessWidget {
  const _GenreCard({required this.genre});

  final _Genre genre;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: genre.color,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => pushInTab(
          context,
          SearchResultsScreen(
            initialQuery: genre.query,
            initialFilter: SearchFilter.playlists,
            title: genre.title,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -14,
              bottom: -10,
              child: Transform.rotate(
                angle: 0.42,
                child: Icon(genre.icon, size: 74, color: Colors.white.withOpacity(0.28)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                genre.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
