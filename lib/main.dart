import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/theme.dart';
import 'data/library_repository.dart';
import 'download/download_manager.dart';
import 'player/audio_handler.dart';
import 'providers.dart';
import 'ui/shell.dart';
import 'youtube/youtube_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Load the UI font before the first frame; text measured with a fallback
  // font and painted with the real one gets clipped (e.g. filter chips).
  // Cached on disk after the first run; offline it gives up after 4 s.
  buildTheme();
  try {
    await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 4));
  } catch (_) {}

  final youtube = YouTubeRepository();
  final library = await LibraryRepository.open();
  final downloads = DownloadManager(youtube, library);

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  final handler = await AudioService.init(
    builder: () => MusicRaAudioHandler(youtube, library),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.musicra.app.playback',
      androidNotificationChannelName: 'Pemutaran musik',
      androidNotificationChannelDescription: 'Kontrol musik yang sedang diputar',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_stat_musicra',
      notificationColor: AppColors.primary,
    ),
  );

  runApp(ProviderScope(
    overrides: [
      youtubeProvider.overrideWithValue(youtube),
      libraryProvider.overrideWith((_) => library),
      downloadsProvider.overrideWith((_) => downloads),
      audioHandlerProvider.overrideWithValue(handler),
    ],
    child: const MusicRaApp(),
  ));
}

class MusicRaApp extends StatelessWidget {
  const MusicRaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'musicRa',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: const RootShell(),
    );
  }
}
