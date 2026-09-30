import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/mock_spotify_data.dart';
import '../models/artist.dart';
import '../models/category.dart';
import '../models/device.dart';
import '../models/lyrics.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/user_profile.dart';
import '../services/spotify_api_service.dart';
import '../services/storage_service.dart';

/// 远端内容：主页数据、搜索、歌词与 Spotify Connect 设备。
class SpotifyProvider extends ChangeNotifier {
  static const Duration _searchDebounce = Duration(milliseconds: 300);

  final SpotifyApiService _api;
  final StorageService _storage;

  SpotifyUser _user = MockSpotifyData.currentUser;
  List<SpotifyPlaylist> _featuredPlaylists = [];
  List<SpotifyCategory> _categories = [];
  List<SpotifyDevice> _devices = [];
  SpotifyDevice? _activeDevice;
  bool _isLoadingHome = false;

  // Search
  Timer? _searchTimer;
  int _searchGeneration = 0;
  String _searchQuery = '';
  bool _isSearching = false;
  List<SpotifyTrack> _searchTracks = [];
  List<SpotifyArtist> _searchArtists = [];
  List<SpotifyPlaylist> _searchPlaylists = [];
  List<String> _recentSearches = [];

  // Lyrics（按曲目 ID 缓存，避免重复打开歌词页时重复请求）
  final Map<String, SpotifyLyrics> _lyricsCache = {};
  final Map<String, Future<SpotifyLyrics>> _lyricsInFlight = {};

  SpotifyProvider(this._api, this._storage) {
    _recentSearches = _storage.recentSearches;
    loadInitialData();
  }

  SpotifyUser get user => _user;
  List<SpotifyPlaylist> get featuredPlaylists => _featuredPlaylists;
  List<SpotifyCategory> get categories => _categories;
  List<SpotifyDevice> get devices => _devices;
  SpotifyDevice? get activeDevice => _activeDevice;
  bool get isLoadingHome => _isLoadingHome;

  String get searchQuery => _searchQuery;
  bool get isSearching => _isSearching;
  List<SpotifyTrack> get searchTracks => _searchTracks;
  List<SpotifyArtist> get searchArtists => _searchArtists;
  List<SpotifyPlaylist> get searchPlaylists => _searchPlaylists;
  List<String> get recentSearches => _recentSearches;

  Future<void> loadInitialData() async {
    _isLoadingHome = true;
    notifyListeners();

    try {
      // 互不依赖的请求并行发出，缩短首屏等待
      final results = await Future.wait([
        _api.getCurrentUser(),
        _api.getFeaturedPlaylists(),
        _api.getCategories(),
        _api.getDevices(),
      ]);
      _user = results[0] as SpotifyUser;
      _featuredPlaylists = results[1] as List<SpotifyPlaylist>;
      _categories = results[2] as List<SpotifyCategory>;
      _devices = results[3] as List<SpotifyDevice>;
      if (_devices.isNotEmpty) {
        _activeDevice = _devices.firstWhere((d) => d.isActive, orElse: () => _devices.first);
      }
    } catch (_) {}

    _isLoadingHome = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  /// 输入时调用：300ms 防抖，并丢弃过期请求的返回结果（避免乱序覆盖）。
  void performSearch(String query) {
    _searchTimer?.cancel();
    _searchQuery = query;
    final generation = ++_searchGeneration;

    if (query.trim().isEmpty) {
      _searchTracks = [];
      _searchArtists = [];
      _searchPlaylists = [];
      _isSearching = false;
      notifyListeners();
      return;
    }

    if (!_isSearching) {
      _isSearching = true;
      notifyListeners();
    }

    _searchTimer = Timer(_searchDebounce, () => _runSearch(query, generation));
  }

  Future<void> _runSearch(String query, int generation) async {
    Map<String, List<dynamic>> results = const {};
    try {
      results = await _api.search(query);
    } catch (_) {}

    if (generation != _searchGeneration) return;

    _searchTracks = results['tracks']?.cast<SpotifyTrack>() ?? [];
    _searchArtists = results['artists']?.cast<SpotifyArtist>() ?? [];
    _searchPlaylists = results['playlists']?.cast<SpotifyPlaylist>() ?? [];
    _isSearching = false;
    notifyListeners();
  }

  /// 用户确认搜索（回车或点击结果）时记录历史。
  void commitRecentSearch(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return;
    _recentSearches = [clean, ..._recentSearches.where((q) => q != clean)].take(20).toList();
    _storage.addRecentSearch(clean);
    notifyListeners();
  }

  void removeRecentSearch(String query) {
    _recentSearches = _recentSearches.where((q) => q != query).toList();
    _storage.removeRecentSearch(query);
    notifyListeners();
  }

  void clearRecentSearches() {
    _recentSearches = [];
    _storage.clearRecentSearches();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Lyrics
  // ---------------------------------------------------------------------------
  SpotifyLyrics? cachedLyrics(String trackId) => _lyricsCache[trackId];

  /// 获取歌词：命中缓存直接返回，并发请求合并为同一个 Future。
  Future<SpotifyLyrics> fetchLyrics(String trackId) {
    final cached = _lyricsCache[trackId];
    if (cached != null) return Future.value(cached);

    // whenComplete 回调必须是块体：箭头函数会返回 remove() 取出的 Future 本身，
    // whenComplete 会等待该 Future，形成自我等待的死锁。
    return _lyricsInFlight[trackId] ??= _api.getLyrics(trackId).then((lyrics) {
      _lyricsCache[trackId] = lyrics;
      return lyrics;
    }).whenComplete(() {
      _lyricsInFlight.remove(trackId);
    });
  }

  // ---------------------------------------------------------------------------
  // Devices
  // ---------------------------------------------------------------------------
  void setActiveDevice(SpotifyDevice device) {
    _activeDevice = device;
    notifyListeners();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }
}
