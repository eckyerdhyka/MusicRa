import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicra/lyrics/lyrics.dart';
import 'package:musicra/player/audio_handler.dart';
import 'package:musicra/providers.dart';
import 'package:musicra/ui/screens/lyrics_screen.dart';
import 'package:musicra/youtube/models.dart';
import 'package:rxdart/rxdart.dart';

const _song = Song(id: 'aaaaaaaaaaa', title: 'Lagu A', artist: 'Penyanyi', durationSec: 200);

const _synced = Lyrics(
  synced: true,
  source: 'LRCLIB',
  lines: [
    LyricLine(Duration(seconds: 10), 'Baris satu'),
    LyricLine(Duration(seconds: 20), 'Baris dua'),
    LyricLine(Duration(seconds: 30), 'Baris tiga'),
  ],
);

void main() {
  late _FakeHandler handler;
  late StreamController<Duration> position;

  Future<void> pumpLyrics(WidgetTester tester, Lyrics? lyrics) async {
    handler = _FakeHandler();
    position = StreamController<Duration>.broadcast();
    addTearDown(position.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        mediaItemProvider.overrideWith((_) => Stream.value(
            const MediaItem(id: 'aaaaaaaaaaa', title: 'Lagu A', artist: 'Penyanyi', duration: Duration(seconds: 200)))),
        positionProvider.overrideWith((_) => position.stream),
        playbackStateProvider.overrideWith((_) => Stream.value(PlaybackState(playing: true))),
        lyricsProvider.overrideWith((ref, song) async => lyrics),
      ],
      child: const MaterialApp(home: LyricsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  // Nearest one: Material higher up has its own.
  Color? colorOf(WidgetTester tester, String text) => tester
      .widgetList<AnimatedDefaultTextStyle>(
          find.ancestor(of: find.text(text), matching: find.byType(AnimatedDefaultTextStyle)))
      .first
      .style
      .color;

  testWidgets('lights up the line being sung', (tester) async {
    await pumpLyrics(tester, _synced);
    expect(find.text('Baris satu'), findsOneWidget);
    expect(find.text('Lirik dari LRCLIB'), findsOneWidget);

    position.add(const Duration(seconds: 21));
    await tester.pumpAndSettle();

    expect(colorOf(tester, 'Baris dua'), Colors.white);
    expect(colorOf(tester, 'Baris satu'), isNot(Colors.white));
    expect(colorOf(tester, 'Baris tiga'), isNot(Colors.white));
  });

  testWidgets('tapping a line jumps there', (tester) async {
    await pumpLyrics(tester, _synced);
    await tester.tap(find.text('Baris tiga'));
    await tester.pump();
    expect(handler.seeks, [const Duration(seconds: 30)]);
  });

  testWidgets('says so when there are no lyrics', (tester) async {
    await pumpLyrics(tester, null);
    expect(find.text('Lirik belum tersedia'), findsOneWidget);
  });

  testWidgets('shows unsynced lyrics as text', (tester) async {
    await pumpLyrics(tester, Lyrics.plain('Satu\nDua', source: 'LyricFind via YouTube Music'));
    expect(find.text('Satu'), findsOneWidget);
    expect(find.text('Lirik ini tidak mengikuti waktu lagu.'), findsOneWidget);
    expect(find.text('Lirik dari LyricFind via YouTube Music'), findsOneWidget);
  });
}

class _FakeHandler implements MusicRaAudioHandler {
  final seeks = <Duration>[];

  @override
  Song? get currentSong => _song;

  @override
  Duration get position => Duration.zero;

  @override
  final BehaviorSubject<PlaybackState> playbackState = BehaviorSubject.seeded(PlaybackState(playing: true));

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
