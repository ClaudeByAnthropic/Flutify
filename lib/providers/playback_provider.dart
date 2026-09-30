import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../core/constants/mock_spotify_data.dart';
import '../models/playback_context.dart';
import '../models/playback_state.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/protocol/track_audio_loader.dart';
import '../services/storage_service.dart';

/// 队列条目：[uid] 在所属列表中唯一，用作拖拽排序时的稳定 Key
/// （同一首歌可能被多次加入队列）。
class QueueEntry {
  final int uid;
  final SpotifyTrack track;

  const QueueEntry(this.uid, this.track);
}

/// 播放状态与队列管理。
///
/// 性能约定：
/// - 播放进度（每秒多次）只写入 [positionNotifier]，**不会**调用 notifyListeners，
///   需要进度的组件通过 ValueListenableBuilder 局部重建。
/// - 其余低频状态（切歌、播放/暂停、随机、循环、队列、音量）走 notifyListeners，
///   组件应使用 `context.select` 只订阅自己关心的字段。
///
/// 队列语义与 Spotify 一致：
/// - [userQueue]：用户手动 "Add to queue" 的曲目，优先播放（Next in queue）。
/// - [upNext]：当前上下文（歌单/专辑等）中剩余的曲目（Next from: ...）。
class PlaybackProvider extends ChangeNotifier {
  final AudioPlayerService _audio;
  final StorageService _storage;

  /// 协议链路完整曲目加载器；为空时回退预览 / Mock 音源。
  final TrackAudioLoader? audioLoader;
  final Random _random;

  /// 协议加载代次号：连续切歌时丢弃过期的加载结果，避免串音。
  int _loadGeneration = 0;

  /// 高频进度通知器，独立于 ChangeNotifier。
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);

  SpotifyTrack? _currentTrack;
  PlaybackContext _context = PlaybackContext.none;

  /// 上下文原始曲目顺序。
  List<SpotifyTrack> _contextTracks = [];

  /// 实际播放顺序（指向 [_contextTracks] 的下标），随机播放时为洗牌后的顺序。
  List<int> _order = [];

  /// 当前上下文曲目在 [_order] 中的位置。
  int _orderPos = 0;

  final List<QueueEntry> _userQueue = [];
  int _nextQueueUid = 0;

  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _duration = Duration.zero;
  bool _shuffle = false;
  SpotifyRepeatMode _repeatMode = SpotifyRepeatMode.off;
  double _volume;
  double _volumeBeforeMute;
  ProcessingState? _lastProcessingState;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  PlaybackProvider(this._audio, this._storage, {Random? random, this.audioLoader})
      : _random = random ?? Random(),
        _volume = _storage.volume,
        _volumeBeforeMute = _storage.volume > 0 ? _storage.volume : 0.8 {
    _initAudioListeners();
    _audio.setVolume(_volume);

    // 默认上下文：Today's Top Hits，停在 Blinding Lights（未加载音源，点击播放后才开始缓冲）
    final defaultPlaylist = MockSpotifyData.playlistTodaysTopHits;
    final startIndex = defaultPlaylist.tracks.indexWhere((t) => t.id == MockSpotifyData.trackBlindingLights.id);
    _contextTracks = List.of(defaultPlaylist.tracks);
    _context = PlaybackContext.playlist(defaultPlaylist.name, uri: defaultPlaylist.uri);
    _rebuildOrder(startIndex < 0 ? 0 : startIndex);
    _currentTrack = _contextTracks[_order[_orderPos]];
    _duration = Duration(milliseconds: _currentTrack!.durationMs);
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  SpotifyTrack? get currentTrack => _currentTrack;
  PlaybackContext get playbackContext => _context;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  Duration get position => positionNotifier.value;
  Duration get duration => _duration;
  bool get shuffle => _shuffle;
  SpotifyRepeatMode get repeatMode => _repeatMode;
  double get volume => _volume;

  /// 用户手动添加的待播队列（只读）。
  List<QueueEntry> get userQueue => List.unmodifiable(_userQueue);

  /// 上下文中接下来要播放的曲目（按实际播放顺序），uid 为其在上下文中的下标。
  List<QueueEntry> get upNext {
    if (_order.isEmpty || _orderPos + 1 >= _order.length) return const [];
    return [
      for (final i in _order.sublist(_orderPos + 1)) QueueEntry(i, _contextTracks[i]),
    ];
  }

  bool isCurrent(String trackId) => _currentTrack?.id == trackId;

  /// 当前是否正在播放给定上下文（用于详情页大播放按钮的 播放/暂停 状态）。
  bool isPlayingContext(String contextUri) =>
      _isPlaying && contextUri.isNotEmpty && _context.uri == contextUri;

  // ---------------------------------------------------------------------------
  // Audio engine listeners
  // ---------------------------------------------------------------------------
  void _initAudioListeners() {
    _posSub = _audio.positionStream.listen((pos) {
      positionNotifier.value = pos;
    });

    _durSub = _audio.durationStream.listen((dur) {
      if (dur != null && dur != Duration.zero && dur != _duration) {
        _duration = dur;
        notifyListeners();
      }
    });

    _stateSub = _audio.playerStateStream.listen((state) {
      final ps = state.processingState;
      final playing = state.playing && ps != ProcessingState.completed;
      final buffering = ps == ProcessingState.loading || ps == ProcessingState.buffering;

      if (_isPlaying != playing || _isBuffering != buffering) {
        _isPlaying = playing;
        _isBuffering = buffering;
        notifyListeners();
      }

      // 只在「进入 completed」的那一刻处理，避免重复事件导致连跳多首。
      if (ps == ProcessingState.completed && _lastProcessingState != ProcessingState.completed) {
        _handleTrackEnded();
      }
      _lastProcessingState = ps;
    });
  }

  void _handleTrackEnded() {
    if (_repeatMode == SpotifyRepeatMode.track) {
      seekTo(Duration.zero);
      _audio.play();
    } else {
      nextTrack();
    }
  }

  // ---------------------------------------------------------------------------
  // Order helpers
  // ---------------------------------------------------------------------------

  /// 以 [currentIndex] 为当前曲目重建播放顺序。
  /// 随机模式：当前曲目置顶，其余洗牌；顺序模式：自然顺序。
  void _rebuildOrder(int currentIndex) {
    final n = _contextTracks.length;
    if (n == 0) {
      _order = [];
      _orderPos = 0;
      return;
    }
    if (_shuffle) {
      final rest = [for (var i = 0; i < n; i++) if (i != currentIndex) i]..shuffle(_random);
      _order = [currentIndex, ...rest];
      _orderPos = 0;
    } else {
      _order = List.generate(n, (i) => i);
      _orderPos = currentIndex;
    }
  }

  Future<void> _startTrack(SpotifyTrack track) async {
    _currentTrack = track;
    _duration = Duration(milliseconds: track.durationMs);
    positionNotifier.value = Duration.zero;
    notifyListeners();
    await _playAudio(track);
  }

  /// 真实曲目（22 位 base62 ID）优先走协议链路拉完整版全曲；
  /// 未登录 / 加载失败时回退预览或 Mock 音频。
  Future<void> _playAudio(SpotifyTrack track) async {
    final generation = ++_loadGeneration;
    final loader = audioLoader;
    if (loader != null && _isRealSpotifyId(track.id)) {
      try {
        final audio = await loader.load(track.id);
        if (generation != _loadGeneration) return; // 已切歌，丢弃
        await _audio.playFile(audio.path);
        return;
      } catch (_) {
        // 回退到预览 / Mock 音源
      }
    }
    if (generation != _loadGeneration) return;
    if (track.audioUrl.isNotEmpty) {
      await _audio.playUrl(track.audioUrl);
    }
  }

  static bool _isRealSpotifyId(String id) {
    if (id.length != 22) return false;
    for (final c in id.codeUnits) {
      final isBase62 = (c >= 0x30 && c <= 0x39) ||
          (c >= 0x61 && c <= 0x7a) ||
          (c >= 0x41 && c <= 0x5a);
      if (!isBase62) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Playback commands
  // ---------------------------------------------------------------------------

  /// 播放指定曲目。[contextQueue] 为所在列表（歌单/专辑/搜索结果），
  /// 未提供时以单曲作为上下文。
  Future<void> playTrack(
    SpotifyTrack track, {
    List<SpotifyTrack>? contextQueue,
    PlaybackContext? context,
  }) async {
    var tracks = (contextQueue == null || contextQueue.isEmpty) ? [track] : List.of(contextQueue);
    var index = tracks.indexWhere((t) => t.id == track.id);
    if (index == -1) {
      tracks = [track, ...tracks];
      index = 0;
    }
    _contextTracks = tracks;
    _context = context ?? PlaybackContext.none;
    _rebuildOrder(index);
    await _startTrack(track);
  }

  /// 从头播放整个上下文（详情页大播放按钮）。随机模式下从随机曲目开始。
  Future<void> playContext(List<SpotifyTrack> tracks, PlaybackContext context) async {
    if (tracks.isEmpty) return;
    final start = _shuffle ? _random.nextInt(tracks.length) : 0;
    await playTrack(tracks[start], contextQueue: tracks, context: context);
  }

  Future<void> togglePlayPause() async {
    final track = _currentTrack;
    if (track == null) return;

    if (_isPlaying) {
      await _audio.pause();
    } else if (!_audio.hasSource) {
      await _playAudio(track);
    } else {
      await _audio.play();
    }
  }

  Future<void> nextTrack() async {
    if (_userQueue.isNotEmpty) {
      await _startTrack(_userQueue.removeAt(0).track);
      return;
    }

    if (_orderPos + 1 < _order.length) {
      _orderPos++;
      await _startTrack(_contextTracks[_order[_orderPos]]);
      return;
    }

    if (_repeatMode == SpotifyRepeatMode.context && _order.isNotEmpty) {
      if (_shuffle) _order.shuffle(_random);
      _orderPos = 0;
      await _startTrack(_contextTracks[_order[_orderPos]]);
      return;
    }

    // 上下文播放完毕：停在当前曲目开头
    await _audio.pause();
    await seekTo(Duration.zero);
  }

  Future<void> previousTrack() async {
    if (position.inSeconds > 3 || _orderPos == 0 || _order.isEmpty) {
      await seekTo(Duration.zero);
      return;
    }
    _orderPos--;
    await _startTrack(_contextTracks[_order[_orderPos]]);
  }

  Future<void> seekTo(Duration pos) async {
    final maxMs = _duration.inMilliseconds;
    final clamped = Duration(milliseconds: pos.inMilliseconds.clamp(0, maxMs > 0 ? maxMs : pos.inMilliseconds));
    positionNotifier.value = clamped;
    await _audio.seek(clamped);
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_order.isNotEmpty) _rebuildOrder(_order[_orderPos]);
    notifyListeners();
  }

  void cycleRepeatMode() {
    _repeatMode = switch (_repeatMode) {
      SpotifyRepeatMode.off => SpotifyRepeatMode.context,
      SpotifyRepeatMode.context => SpotifyRepeatMode.track,
      SpotifyRepeatMode.track => SpotifyRepeatMode.off,
    };
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Volume
  // ---------------------------------------------------------------------------

  /// 拖动过程中 [persist] 为 false，松手时再写盘，避免每帧写 SharedPreferences。
  void setVolume(double value, {bool persist = false}) {
    _volume = value.clamp(0.0, 1.0);
    if (_volume > 0) _volumeBeforeMute = _volume;
    _audio.setVolume(_volume);
    if (persist) _storage.setVolume(_volume);
    notifyListeners();
  }

  void toggleMute() {
    setVolume(_volume > 0 ? 0 : _volumeBeforeMute, persist: true);
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------
  void addToQueue(SpotifyTrack track) {
    _userQueue.add(QueueEntry(_nextQueueUid++, track));
    notifyListeners();
  }

  void clearUserQueue() {
    if (_userQueue.isEmpty) return;
    _userQueue.clear();
    notifyListeners();
  }

  void removeFromUserQueue(int index) {
    if (index < 0 || index >= _userQueue.length) return;
    _userQueue.removeAt(index);
    notifyListeners();
  }

  /// [newIndex] 为移除原条目后的目标位置（与 SliverReorderableList.onReorderItem 一致）。
  void reorderUserQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _userQueue.length) return;
    final item = _userQueue.removeAt(oldIndex);
    _userQueue.insert(newIndex.clamp(0, _userQueue.length), item);
    notifyListeners();
  }

  /// 从上下文待播列表中移除（仅从本轮播放顺序中跳过，不修改原歌单）。
  void removeFromUpNext(int index) {
    final pos = _orderPos + 1 + index;
    if (index < 0 || pos >= _order.length) return;
    _order.removeAt(pos);
    notifyListeners();
  }

  /// [newIndex] 为移除原条目后的目标位置（与 SliverReorderableList.onReorderItem 一致）。
  void reorderUpNext(int oldIndex, int newIndex) {
    final base = _orderPos + 1;
    final count = _order.length - base;
    if (oldIndex < 0 || oldIndex >= count) return;
    final item = _order.removeAt(base + oldIndex);
    _order.insert(base + newIndex.clamp(0, count - 1), item);
    notifyListeners();
  }

  /// 点击 "Next in queue" 中的曲目：跳过它之前的排队曲目并立即播放。
  Future<void> playFromUserQueue(int index) async {
    if (index < 0 || index >= _userQueue.length) return;
    _userQueue.removeRange(0, index);
    await _startTrack(_userQueue.removeAt(0).track);
  }

  /// 点击 "Next from" 中的曲目：直接跳到该位置。
  Future<void> playFromUpNext(int index) async {
    final pos = _orderPos + 1 + index;
    if (index < 0 || pos >= _order.length) return;
    _orderPos = pos;
    await _startTrack(_contextTracks[_order[_orderPos]]);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    positionNotifier.dispose();
    _audio.dispose();
    super.dispose();
  }
}
