import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
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
  bool _retriedCurrent = false;
  bool _fetchingRadio = false;
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
    if (currentSong != null && _player.processingState == ProcessingState.idle && !_resolving) {
      return _load(_index, at: _player.position, retry: true);
    }
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    _loadToken++;
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
      return _player.seek(Duration.zero);
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
    _index = i;
    if (!retry) _retriedCurrent = false;
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
      unawaited(_player.play());
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
      messages.add('Tidak bisa memutar "${song.title}"');
      _consecutiveErrors++;
      // Stop after a few failures in a row (e.g. offline) instead of
      // racing through the whole queue.
      if (_consecutiveErrors < 3 && i + 1 < _songs.length) {
        await _load(i + 1);
      } else {
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
    if (!_retriedCurrent && !_lib.isDownloaded(song.id)) {
      // Usually an expired/blocked URL: resolve a fresh one and resume.
      _retriedCurrent = true;
      _yt.streams.invalidate(song.id);
      _load(_index, at: _player.position, retry: true);
      return;
    }
    _errorHandledFor = _loadToken;
    messages.add('Pemutaran "${song.title}" terhenti');
    skipToNext();
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
    final state = _resolving
        ? AudioProcessingState.loading
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
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _index < 0 ? null : _index,
      repeatMode: _repeat,
      shuffleMode: _shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    ));
  }
}
