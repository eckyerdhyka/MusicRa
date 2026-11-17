import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../youtube/models.dart';

/// A local cover path ("/data/…") or a remote URL.
ImageProvider artImageProvider(String src) =>
    src.startsWith('/') ? FileImage(File(src)) : CachedNetworkImageProvider(src);

/// Best source for a song's cover: saved file first, then the CDN copy.
String? songArt(Song song, {bool hiRes = false}) {
  final local = song.localArt;
  if (local != null && File(local).existsSync()) return local;
  return hiRes ? hiResThumb(song.thumbnail) : song.thumbnail;
}

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.src,
    this.size,
    this.radius = 4,
    this.circle = false,
    this.icon = Icons.music_note_rounded,
  });

  /// URL or local file path.
  final String? src;
  final double? size;
  final double radius;
  final bool circle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.surfaceHigher,
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.textFaint, size: (size ?? 48) * 0.42),
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cache = size == null ? null : (size! * dpr).round();
    Widget image;
    final s = src;
    if (s == null || s.isEmpty) {
      image = placeholder;
    } else if (s.startsWith('/')) {
      image = Image.file(File(s),
          fit: BoxFit.cover, cacheWidth: cache, errorBuilder: (_, __, ___) => placeholder);
    } else {
      image = CachedNetworkImage(
        imageUrl: s,
        fit: BoxFit.cover,
        memCacheWidth: cache,
        fadeInDuration: const Duration(milliseconds: 160),
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      );
    }
    final clipped = circle
        ? ClipOval(child: image)
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
    return SizedBox(width: size, height: size, child: clipped);
  }
}

/// Spotify-style 2×2 cover mosaic for local playlists without their own art.
class MosaicArtwork extends StatelessWidget {
  const MosaicArtwork({super.key, required this.covers, required this.size, this.radius = 4});

  final List<String> covers;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (covers.length < 4) {
      return Artwork(src: covers.firstOrNull, size: size, radius: radius, icon: Icons.queue_music_rounded);
    }
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Wrap(
          children: [for (final c in covers.take(4)) Artwork(src: c, size: half, radius: 0)],
        ),
      ),
    );
  }
}

/// Gradient tile used for "Lagu yang Disukai" and "Diunduh".
class GradientIconArt extends StatelessWidget {
  const GradientIconArt({
    super.key,
    required this.icon,
    required this.colors,
    required this.size,
    this.radius = 4,
  });

  final IconData icon;
  final List<Color> colors;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.42),
    );
  }
}

const likedGradient = [Color(0xFF0B6B3A), Color(0xFF2EE07A)];
const downloadsGradient = [Color(0xFF0F3D2B), Color(0xFF1FA67A)];
