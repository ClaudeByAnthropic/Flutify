import 'album.dart';
import 'artist.dart';

class SpotifyTrack {
  final String id;
  final String name;
  final String uri;
  final List<SpotifyArtist> artists;
  final SpotifyAlbum? album;
  final int durationMs;
  final String? previewUrl;
  final String? streamUrl;
  final bool explicit;
  final int popularity;
  final bool isPlayable;

  const SpotifyTrack({
    required this.id,
    required this.name,
    this.uri = '',
    this.artists = const [],
    this.album,
    this.durationMs = 0,
    this.previewUrl,
    this.streamUrl,
    this.explicit = false,
    this.popularity = 50,
    this.isPlayable = true,
  });

  String get artistNames => artists.map((a) => a.name).join(', ');
  String get coverUrl => album?.coverUrl ?? '';
  String get audioUrl => streamUrl ?? previewUrl ?? '';

  SpotifyTrack copyWith({
    String? id,
    String? name,
    String? uri,
    List<SpotifyArtist>? artists,
    SpotifyAlbum? album,
    int? durationMs,
    String? previewUrl,
    String? streamUrl,
    bool? explicit,
    int? popularity,
    bool? isPlayable,
  }) {
    return SpotifyTrack(
      id: id ?? this.id,
      name: name ?? this.name,
      uri: uri ?? this.uri,
      artists: artists ?? this.artists,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      previewUrl: previewUrl ?? this.previewUrl,
      streamUrl: streamUrl ?? this.streamUrl,
      explicit: explicit ?? this.explicit,
      popularity: popularity ?? this.popularity,
      isPlayable: isPlayable ?? this.isPlayable,
    );
  }

  factory SpotifyTrack.fromJson(Map<String, dynamic> json) {
    return SpotifyTrack(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      uri: json['uri'] as String? ?? (json['id'] != null ? 'spotify:track:${json['id']}' : ''),
      artists: (json['artists'] as List<dynamic>?)
              ?.map((e) => SpotifyArtist.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      album: json['album'] != null
          ? SpotifyAlbum.fromJson(json['album'] as Map<String, dynamic>)
          : null,
      durationMs: json['duration_ms'] as int? ?? 0,
      previewUrl: json['preview_url'] as String?,
      streamUrl: json['stream_url'] as String?,
      explicit: json['explicit'] as bool? ?? false,
      popularity: json['popularity'] as int? ?? 50,
      isPlayable: json['is_playable'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'uri': uri,
    'artists': artists.map((e) => e.toJson()).toList(),
    'album': album?.toJson(),
    'duration_ms': durationMs,
    'preview_url': previewUrl,
    'stream_url': streamUrl,
    'explicit': explicit,
    'popularity': popularity,
    'is_playable': isPlayable,
  };
}
