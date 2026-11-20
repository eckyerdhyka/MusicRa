// Playback recovery when a stream dies mid-song. Runs MusicRaAudioHandler
// against a fake just_audio platform so a native player error can be fired
// on demand.
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:musicra/data/library_repository.dart';
import 'package:musicra/player/audio_handler.dart';
import 'package:musicra/youtube/innertube.dart';
import 'package:musicra/youtube/models.dart';
import 'package:musicra/youtube/stream_resolver.dart';
import 'package:musicra/youtube/youtube_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const audioSessionChannel = MethodChannel('com.ryanheise.audio_session');

  late _FakePlatform platform;
  late _FakeYouTube yt;
  late MusicRaAudioHandler handler;

  const a = Song(id: 'aaaaaaaaaaa', title: 'Lagu A', artist: 'X', durationSec: 200);
  const b = Song(id: 'bbbbbbbbbbb', title: 'Lagu B', artist: 'X', durationSec: 200);

  Future<void> settle([int ms = 150]) => Future<void>.delayed(Duration(milliseconds: ms));

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, (_) async => null);
    platform = _FakePlatform();
    JustAudioPlatform.instance = platform;
    yt = _FakeYouTube();
    handler = MusicRaAudioHandler(yt, _FakeLibrary())
      ..autoplay = false
      ..retryDelay = const Duration(milliseconds: 20);
    await handler.playSongs([a, b]);
    await settle();
  });

  test('resumes the same song from where the stream died', () async {
    expect(platform.player.loads.map((l) => l.songId), [a.id]);

    platform.player.dieAt(const Duration(seconds: 42));
    await settle(300);

    expect(handler.currentIndex, 0);
    final resume = platform.player.loads.last;
    expect(resume.songId, a.id);
    expect(resume.position, const Duration(seconds: 42));
    expect(handler.playbackState.value.playing, isTrue);
  });

  test('when resuming keeps failing it pauses, and play starts the song again', () async {
    final messages = <String>[];
    handler.messages.listen(messages.add);

    yt.online = false;
    platform.player.dieAt(const Duration(seconds: 42));
    await settle(600);

    // Gave up without skipping through the queue, on a play button.
    expect(handler.currentIndex, 0);
    final state = handler.playbackState.value;
    expect(state.playing, isFalse);
    expect(state.processingState, AudioProcessingState.ready);
    expect(messages.last, contains('Ketuk putar'));

    yt.online = true;
    final loadsBefore = platform.player.loads.length;
    await handler.play();
    await settle();

    expect(platform.player.loads.length, loadsBefore + 1);
    expect(platform.player.loads.last.songId, a.id);
    expect(platform.player.loads.last.position, const Duration(seconds: 42));
    expect(handler.currentIndex, 0);
    expect(handler.playbackState.value.playing, isTrue);
  });

  test('a failure while paused waits for play instead of resuming on its own', () async {
    await handler.pause();
    await settle();
    final loadsBefore = platform.player.loads.length;

    platform.player.dieAt(const Duration(seconds: 10));
    await settle(300);
    expect(platform.player.loads.length, loadsBefore);
    expect(handler.playbackState.value.playing, isFalse);

    await handler.play();
    await settle();
    expect(platform.player.loads.length, loadsBefore + 1);
    expect(platform.player.loads.last.position, const Duration(seconds: 10));
  });
}

class _FakeYouTube implements YouTubeRepository {
  bool online = true;

  @override
  final StreamResolver streams = StreamResolver(InnerTube());

  @override
  Future<AudioStream> stream(String videoId, {bool forceRefresh = false}) async {
    if (!online) throw StreamUnavailableException(videoId, 'offline');
    return AudioStream(
      url: 'https://example.com/$videoId.m4a',
      mimeType: 'audio/mp4',
      bitrate: 128000,
      userAgent: 'test',
      expiresAt: DateTime.now().add(const Duration(hours: 6)),
    );
  }

  @override
  Future<List<Song>> radio(String videoId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibrary implements LibraryRepository {
  @override
  String? downloadPath(String songId) => null;

  @override
  bool isDownloaded(String songId) => false;

  @override
  Future<void> recordPlay(Song song) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlatform extends JustAudioPlatform {
  late _FakePlayer player;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async => player = _FakePlayer(request.id);

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async =>
      DisposePlayerResponse();

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse();
}

typedef _Load = ({String songId, Duration position});

/// Mimics just_audio's Android side: a native error is sent as a stream error
/// and the last processing state (buffering) is left as it was.
class _FakePlayer extends AudioPlayerPlatform {
  _FakePlayer(super.id);

  final _events = StreamController<PlaybackEventMessage>.broadcast();
  final _data = StreamController<PlayerDataMessage>.broadcast();
  final loads = <_Load>[];
  var _state = ProcessingStateMessage.idle;
  var _position = Duration.zero;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _data.stream;

  void _emit() => _events.add(PlaybackEventMessage(
        processingState: _state,
        updateTime: DateTime.now(),
        updatePosition: _position,
        bufferedPosition: _position,
        duration: const Duration(seconds: 200),
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      ));

  /// The stream is cut at [at]: ExoPlayer buffers, gives up, reports an error.
  void dieAt(Duration at) {
    _position = at;
    _state = ProcessingStateMessage.buffering;
    _emit();
    _events.addError(PlatformException(code: '0', message: 'Source error'));
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final uri = (request.audioSourceMessage as UriAudioSourceMessage).uri;
    loads.add((
      songId: Uri.parse(uri).pathSegments.last.split('.').first,
      position: request.initialPosition ?? Duration.zero,
    ));
    _position = request.initialPosition ?? Duration.zero;
    _state = ProcessingStateMessage.ready;
    _emit();
    return LoadResponse(duration: const Duration(seconds: 200));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _data.add(PlayerDataMessage(playing: true));
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _data.add(PlayerDataMessage(playing: false));
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    _position = request.position ?? Duration.zero;
    _emit();
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async => SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse> setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest request) async =>
      SetAutomaticallyWaitsToMinimizeStallingResponse();

  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
      setCanUseNetworkResourcesForLiveStreamingWhilePaused(
              SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest request) async =>
          SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
          SetPreferredPeakBitRateRequest request) async =>
      SetPreferredPeakBitRateResponse();

  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
          SetAllowsExternalPlaybackRequest request) async =>
      SetAllowsExternalPlaybackResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async => DisposeResponse();
}
