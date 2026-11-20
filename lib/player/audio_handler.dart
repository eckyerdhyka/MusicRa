import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../data/library_repository.dart';
import '../youtube/models.dart';
import '../youtube/youtube_repository.dart';

/// Owns playback. Runs inside audio_service's foreground service, so music
/// keeps playing when the app is minimised or the screen is off, with
/// notification, lock-screen and headset controls.
///
/// The queue is kept here (not in a just_audio playlist) so each song's
/// stream URL is resolved right before it plays and never goes stale.
class MusicRaAudioHandler extends BaseAudioHandler with SeekHandler {
  MusicRaAudioHandler(this._yt, this._lib) {
    _init();
  }

  final YouTubeRepository _yt;
  final LibraryRepository _lib;
  final AudioPlayer _player = AudioPlayer(useProxyForRequestHeaders: false);

  List<Song> _songs = [];
  List<Song>? _unshuffled;
  int _index = -1;
  int _loadToken = 0;
  int _queueGen = 0;
  int? _errorHandledFor;
  int _consecutiveErrors = 0;
  bool _resolving = false;
  bool _fetchingRadio = false;

  /// The native player stopped on an error and holds a dead source. just_audio
  /// keeps reporting it as playing/buffering, so [play] and [seek] must reload
  /// the song (from [_resumeAt]) instead of poking the dead player.
  bool _failed = false;
  Duration _resumeAt = Duration.zero;

  /// Automatic resume attempts for the current song, see [_onFailure].
  int _retries = 0;
  Duration? _lastFailurePos;
  Timer? _retryTimer;
  static const _maxRetries = 3;

  /// Wait before the first automatic resume; doubles on each further attempt.
  @visibleForTesting
  Duration retryDelay = const Duration(seconds: 1);

  /// Pause was pressed while a song was still loading.
  bool _pauseAfterLoad = false;
  bool _shuffle = false;
  AudioServiceRepeatMode _repeat = AudioServiceRepeatMode.none;

  /// Keep playing related songs when the queue runs out (Spotify's autoplay).
  bool autoplay = true;

  /// Where the current queue came from, e.g. a playlist name.
  final source = BehaviorSubject<String?>.seeded(null);

  /// One-off messages for the UI (snackbars).
  final messages = PublishSubject<String>();

  List<Song> get songs => List.unmodifiable(_songs);
  int get currentIndex => _index;
  Song? get currentSong => _index >= 0 && _index < _songs.length ? _songs[_index] : null;
  Stream<Duration> get positionStream => _player.positionStream;
  Duration get position => _player.position;

  void _init() {
    _player.playbackEventStream.listen((_) => _broadcast(), onError: _onPlayerError);
    _player.playingStream.listen((_) => _broadcast());
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.ready) _consecutiveErrors = 0;
      if (state == ProcessingState.completed) _onCompleted();
    });
    _player.durationStream.listen((d) {
      final item = mediaItem.value;
      if (d != null && item != null && item.duration != d) {
        mediaItem.add(item.copyWith(duration: d));
      }
    });
  }

  // ---- public API used by the UI ---------------------------------------------

  /// Replaces the queue with [list] and starts at [index].
  Future<void> playSongs(List<Song> list, {int index = 0, String? from, bool shuffle = false}) async {
    if (list.isEmpty) return;
    _queueGen++;
    _songs = List.of(list);
    _unshuffled = null;
    _shuffle = false;
    _index = shuffle ? Random().nextInt(list.length) : index.clamp(0, list.length - 1);
    source.add(from);
    if (shuffle) _applyShuffle(true);
    _consecutiveErrors = 0;
    await _load(_index);
  }

  /// Plays one song and fills the queue with its radio.
  Future<void> playSong(Song song, {String? from}) async {
    await playSongs([song], from: from ?? 'Radio "${song.title}"');
    unawaited(_appendRadio(seed: song));
  }

  void playNext(Song song) {
    if (currentSong == null) {
      playSongs([song]);
      return;
    }
    if (song == currentSong) return;
    _songs.remove(song);
    _index = _songs.indexOf(currentSong!);
    _songs.insert(_index + 1, song);
    _unshuffled?.add(song);
    _publishQueue();
  }

  void addToQueue(Song song) {
    if (currentSong == null) {
      playSongs([song]);
      return;
    }
    if (_songs.contains(song)) return;
    _songs.add(song);
    _unshuffled?.add(song);
    _publishQueue();
  }

  void removeFromQueue(int i) {
    if (i < 0 || i >= _songs.length || i == _index) return;
    final s = _songs.removeAt(i);
    _unshuffled?.remove(s);
    if (i < _index) _index--;
    _publishQueue();
  }

  void moveQueueItem(int from, int to) {
    if (from == to || from < 0 || from >= _songs.length) return;
    final current = currentSong;
    final s = _songs.removeAt(from);
    _songs.insert(to.clamp(0, _songs.length), s);
    if (current != null) _index = _songs.indexOf(current);
    _publishQueue();
  }

  bool get shuffleEnabled => _shuffle;
  AudioServiceRepeatMode get repeatMode => _repeat;

  // ---- audio_service callbacks (UI, notification, headset) --------------------

  @override
  Future<void> play() async {
    if (_resolving) {
      // The song being loaded starts on its own once ready.
      _pauseAfterLoad = false;
      return;
    }
    if (currentSong != null && (_failed || _player.processingState == ProcessingState.idle)) {
      // The user asked again: start with a fresh retry budget.
      _retries = 0;
      _lastFailurePos = null;
      return _load(_index, at: _failed ? _resumeAt : _player.position, retry: true);
    }
    return _player.play();
  }

  @override
  Future<void> pause() async {
    if (_resolving) _pauseAfterLoad = true;
    _retryTimer?.cancel();
    await _player.pause();
    _broadcast();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_failed && currentSong != null && !_resolving) {
      _retries = 0;
      _lastFailurePos = null;
      return _load(_index, at: position, retry: true);
    }
    return _player.seek(position);
  }

  @override
  Future<void> stop() async {
    _loadToken++;
    _retryTimer?.cancel();
    // A load cut short here never clears this flag itself; left set, it made
    // play() a no-op until the app was restarted.
    _resolving = false;
    await _player.stop();
    _broadcast();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (_index + 1 < _songs.length) return _load(_index + 1);
    if (_repeat == AudioServiceRepeatMode.all && _songs.isNotEmpty) return _load(0);
    if (autoplay && await _appendRadio() && _index + 1 < _songs.length) return _load(_index + 1);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 3) || _index <= 0) {
      return seek(Duration.zero);
    }
    return _load(_index - 1);
  }

  @override
  Future<void> skipToQueueItem(int index) => _load(index);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeat = repeatMode;
    _broadcast();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _applyShuffle(shuffleMode != AudioServiceShuffleMode.none);
  }

  @override
  Future<void> onTaskRemoved() async {
    // Swiping the app away keeps music going; a paused player shuts down.
    if (!_player.playing) await stop();
  }

  // ---- internals ---------------------------------------------------------------

  Future<void> _load(int i, {Duration? at, bool retry = false}) async {
    if (i < 0 || i >= _songs.length) return;
    final token = ++_loadToken;
    _retryTimer?.cancel();
    _index = i;
    if (!retry) {
      _retries = 0;
      _lastFailurePos = null;
      _pauseAfterLoad = false;
    }
    final song = _songs[i];
    mediaItem.add(_toItem(song));
    _publishQueue();
    _resolving = true;
    _broadcast();
    try {
      final src = await _sourceFor(song, refresh: retry);
      if (token != _loadToken) return;
      await _player.setAudioSource(src, initialPosition: at);
      if (token != _loadToken) return;
      _resolving = false;
      _failed = false;
      if (_pauseAfterLoad) {
        _pauseAfterLoad = false;
        await _player.pause();
        _broadcast();
      } else {
        unawaited(_player.play());
      }
      if (!retry) unawaited(_lib.recordPlay(song).catchError((_) {}));
      _prefetch(i + 1);
      if (autoplay && _repeat == AudioServiceRepeatMode.none && i >= _songs.length - 2) {
        unawaited(_appendRadio());
      }
    } catch (e) {
      if (token != _loadToken) return;
      _errorHandledFor = token;
      _resolving = false;
      _yt.streams.invalidate(song.id);
      if (retry) {
        // Resuming mid-song (connection dropped, URL expired): keep the song
        // and its position instead of skipping ahead.
        await _onFailure(song, at ?? Duration.zero, wantPlay: !_pauseAfterLoad);
        return;
      }
      messages.add('Tidak bisa memutar "${song.title}"');
      _consecutiveErrors++;
      // Stop after a few failures in a row (e.g. offline) instead of
      // racing through the whole queue.
      if (_consecutiveErrors < 3 && i + 1 < _songs.length) {
        await _load(i + 1);
      } else {
        // Silence whatever was still playing and let play() try this song again.
        _failed = true;
        _resumeAt = Duration.zero;
        await _player.pause();
        _broadcast();
      }
    }
  }

  Future<AudioSource> _sourceFor(Song song, {bool refresh = false}) async {
    final local = _lib.downloadPath(song.id);
    if (local != null && await File(local).exists()) return AudioSource.file(local);
    final s = await _yt.stream(song.id, forceRefresh: refresh);
    return AudioSource.uri(Uri.parse(s.url), headers: {'User-Agent': s.userAgent});
  }

  void _prefetch(int i) {
    if (i < 0 || i >= _songs.length) return;
    final s = _songs[i];
    if (_lib.isDownloaded(s.id)) return;
    unawaited(_yt.stream(s.id).then((_) {}, onError: (_) {}));
  }

  void _onPlayerError(Object e, StackTrace st) {
    final song = currentSong;
    if (song == null || _errorHandledFor == _loadToken || _resolving) return;
    _errorHandledFor = _loadToken;
    _yt.streams.invalidate(song.id);
    unawaited(_onFailure(song, _player.position, wantPlay: _player.playing));
  }

  /// The current song stopped on an error: the stream was cut off, its URL
  /// expired, or the connection dropped. ExoPlayer then sits on a dead source
  /// that just_audio still reports as playing/buffering, which used to leave
  /// the song stuck with no way to start it again.
  ///
  /// Streams are resumed from the same spot a few times with a growing pause
  /// (1 s, 2 s, 4 s), then the player is paused so the play button can pick it
  /// up later. A broken downloaded file is skipped instead.
  Future<void> _onFailure(Song song, Duration at, {required bool wantPlay}) async {
    _failed = true;
    _resumeAt = at;
    if (!wantPlay) {
      // Failed while paused: nothing to resume now, play() reloads it.
      _broadcast();
      return;
    }

    if (_lib.isDownloaded(song.id)) {
      messages.add('File "${song.title}" tidak bisa diputar, dilewati');
      final before = _index;
      await skipToNext();
      if (_index == before) {
        await _player.pause();
        _broadcast();
      }
      return;
    }

    // Playing on since the last failure earns a fresh budget; a stream that
    // keeps dying at the same spot does not loop forever.
    final last = _lastFailurePos;
    if (last == null || (at - last).abs() > const Duration(seconds: 20)) _retries = 0;
    _lastFailurePos = at;

    if (_retries < _maxRetries) {
      _retries++;
      final token = _loadToken;
      _retryTimer?.cancel();
      _retryTimer = Timer(retryDelay * (1 << (_retries - 1)), () {
        if (token == _loadToken && _failed) _load(_index, at: at, retry: true);
      });
      _broadcast();
      return;
    }

    _retryTimer?.cancel();
    await _player.pause();
    messages.add('Pemutaran "${song.title}" terhenti. Ketuk putar untuk melanjutkan.');
    _broadcast();
  }

  Future<void> _onCompleted() async {
    if (_repeat == AudioServiceRepeatMode.one) {
      await _player.seek(Duration.zero);
      unawaited(_player.play());
      return;
    }
    if (_index + 1 < _songs.length) return _load(_index + 1);
    if (_repeat == AudioServiceRepeatMode.all && _songs.isNotEmpty) return _load(0);
    if (autoplay && await _appendRadio() && _index + 1 < _songs.length) {
      return _load(_index + 1);
    }
    await _player.pause();
    await _player.seek(Duration.zero);
  }

  /// Appends songs related to [seed] (default: last in queue). Returns
  /// whether anything was added.
  Future<bool> _appendRadio({Song? seed}) async {
    final s = seed ?? (_songs.isEmpty ? null : _songs.last);
    if (s == null || _fetchingRadio) return false;
    _fetchingRadio = true;
    final gen = _queueGen;
    try {
      final related = await _yt.radio(s.id);
      if (gen != _queueGen) return false; // queue replaced meanwhile
      final existing = _songs.map((e) => e.id).toSet();
      final fresh = related.where((r) => !existing.contains(r.id)).toList();
      if (fresh.isEmpty) return false;
      _songs.addAll(fresh);
      _unshuffled?.addAll(fresh);
      _publishQueue();
      return true;
    } catch (_) {
      return false;
    } finally {
      _fetchingRadio = false;
    }
  }

  void _applyShuffle(bool on) {
    final current = currentSong;
    if (on && !_shuffle) {
      _unshuffled = List.of(_songs);
      final rest = List.of(_songs)
        ..remove(current)
        ..shuffle();
      _songs = [if (current != null) current, ...rest];
      _index = current == null ? -1 : 0;
    } else if (!on && _unshuffled != null) {
      _songs = _unshuffled!;
      _unshuffled = null;
      _index = current == null ? -1 : _songs.indexOf(current);
    }
    _shuffle = on;
    _publishQueue();
    _broadcast();
  }

  MediaItem _toItem(Song s) {
    final art = s.localArt != null
        ? Uri.file(s.localArt!)
        : (s.thumbnail != null ? Uri.tryParse(hiResThumb(s.thumbnail)!) : null);
    return MediaItem(
      id: s.id,
      title: s.title,
      artist: s.artist,
      album: s.album,
      duration: s.duration,
      artUri: art,
      extras: {'thumb': s.thumbnail},
    );
  }

  void _publishQueue() => queue.add(_songs.map(_toItem).toList());

  void _broadcast() {
    final playing = _player.playing;
    final state = _resolving || (_retryTimer?.isActive ?? false)
        ? AudioProcessingState.loading
        : _failed
            // Paused on a dead source: show a play button that reloads it.
            // Not idle, which would make audio_service tear down the service.
            ? AudioProcessingState.ready
            : const {
                ProcessingState.idle: AudioProcessingState.idle,
                ProcessingState.loading: AudioProcessingState.loading,
                ProcessingState.buffering: AudioProcessingState.buffering,
                ProcessingState.ready: AudioProcessingState.ready,
                ProcessingState.completed: AudioProcessingState.completed,
              }[_player.processingState]!;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToQueueItem,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: state,
      playing: playing,
      updatePosition: _failed ? _resumeAt : _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _index < 0 ? null : _index,
      repeatMode: _repeat,
      shuffleMode: _shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    ));
  }
}
