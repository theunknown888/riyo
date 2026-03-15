class StreamSource {
  final String label;
  final String url;
  final String type;
  final String provider;
  final String quality;

  StreamSource({
    required this.label,
    required this.url,
    required this.type,
    required this.provider,
    this.quality = '720p',
  });

  factory StreamSource.fromJson(Map<String, dynamic> json) {
    return StreamSource(
      label: json['label'] ?? '',
      url: json['url'] ?? '',
      type: json['type'] ?? 'direct',
      provider: json['provider'] ?? 'url',
      quality: json['quality'] ?? '720p',
    );
  }
}

class Movie {
  final int id;
  final String? backendId; // MongoDB _id
  final String title;
  final String shortDesc;
  final String overview;
  final String posterPath;
  final String? backdropPath;
  final String? bannerUrl;
  final String? thumbnailUrl;
  final String releaseDate;
  final double voteAverage;
  final int? runtime;
  final List<String>? genres;
  final List<String>? cast;
  final String? director;
  final String? ageRating;
  final String? contentRating; // kept for compatibility
  final String? language;
  final String? country;
  final List<String>? tags;
  final String? quality;
  final String status; // published, draft, coming_soon, premium, trailer_only
  final String accessType; // free, premium, subscription
  final int views;
  final bool isTvShow;
  final int? seasonNumber;
  final List<Season>? seasons;
  final String? videoUrl;
  final List<StreamSource>? sources;
  final String? trailerUrl;
  final String? trailerType;
  final String contentType; // Deprecated but kept for compat
  final bool isPublished;
  final List<String> notifyUsers;
  final String? localPath;

  // Download related fields
  final bool isDownloaded;
  final bool isDownloading;
  final double downloadProgress;
  final String fileSize;
  final int downloadedEpisodesCount;

  Movie({
    required this.id,
    this.backendId,
    required this.title,
    this.shortDesc = '',
    required this.overview,
    required this.posterPath,
    this.backdropPath,
    this.bannerUrl,
    this.thumbnailUrl,
    required this.releaseDate,
    this.voteAverage = 0.0,
    this.runtime,
    this.genres,
    this.cast,
    this.director,
    this.ageRating,
    this.contentRating,
    this.language,
    this.country,
    this.tags,
    this.quality,
    this.status = 'published',
    this.accessType = 'free',
    this.views = 0,
    this.isTvShow = false,
    this.seasonNumber,
    this.seasons,
    this.videoUrl,
    this.sources,
    this.trailerUrl,
    this.trailerType,
    this.contentType = 'free',
    this.isPublished = true,
    this.notifyUsers = const [],
    this.localPath,
    this.isDownloaded = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.fileSize = '0 MB',
    this.downloadedEpisodesCount = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      '_id': backendId,
      'title': title,
      'shortDesc': shortDesc,
      'description': overview,
      'posterUrl': posterPath,
      'bannerUrl': bannerUrl,
      'backdropUrl': backdropPath,
      'year': releaseDate,
      'rating': voteAverage,
      'runtime': runtime,
      'genre': genres,
      'director': director,
      'cast': cast,
      'ageRating': ageRating,
      'contentRating': contentRating,
      'language': language,
      'country': country,
      'quality': quality,
      'status': status,
      'accessType': accessType,
      'isTvShow': isTvShow,
      'videoUrl': videoUrl,
      'trailerUrl': trailerUrl,
    };
  }

  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      id: json['id'] ?? (json['_id'] != null ? json['_id'].toString().hashCode : 0),
      backendId: json['_id']?.toString(),
      title: json['title'] ?? '',
      shortDesc: json['shortDesc'] ?? '',
      overview: json['description'] ?? json['overview'] ?? '',
      posterPath: json['posterUrl'] ?? json['poster_path'] ?? '',
      backdropPath: json['backdropUrl'] ?? json['backdrop_path'] ?? json['posterUrl'],
      bannerUrl: json['bannerUrl'],
      thumbnailUrl: json['thumbnailUrl'],
      releaseDate: json['year']?.toString() ?? json['release_date'] ?? json['createdAt']?.toString().split('T')[0] ?? '',
      voteAverage: (json['rating'] as num?)?.toDouble() ?? (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      runtime: json['duration'] is int ? json['duration'] : (json['duration'] != null ? _parseDuration(json['duration']) : (json['runtime'] is int ? json['runtime'] : null)),
      genres: json['genre'] != null ? List<String>.from(json['genre']) : null,
      cast: json['cast'] != null ? List<String>.from(json['cast']) : null,
      director: json['director'],
      ageRating: json['ageRating'] ?? json['contentRating'],
      contentRating: json['contentRating'] ?? json['ageRating'],
      language: json['language'],
      country: json['country'],
      tags: json['tags'] != null ? List<String>.from(json['tags']) : null,
      quality: json['quality'],
      status: json['status'] ?? 'published',
      accessType: json['accessType'] ?? 'free',
      views: (json['views'] as num?)?.toInt() ?? 0,
      isTvShow: json['isTvShow'] ?? json['is_tv_show'] ?? false,
      seasonNumber: json['season_number'],
      seasons: json['seasons'] != null ? (json['seasons'] as List).map((s) => Season.fromJson(s)).toList() : null,
      videoUrl: json['videoUrl'],
      sources: json['sources'] != null ? (json['sources'] as List).map((s) => StreamSource.fromJson(s)).toList() : null,
      trailerUrl: json['trailerUrl'] ?? json['trailer_url'],
      trailerType: json['trailerType'],
      contentType: json['contentType'] ?? json['content_type'] ?? 'free',
      isPublished: json['isPublished'] ?? json['is_published'] ?? true,
      notifyUsers: json['notifyUsers'] != null ? List<String>.from(json['notifyUsers'].map((u) => u.toString())) : [],
      localPath: json['local_path'],
      isDownloaded: json['is_downloaded'] ?? false,
      isDownloading: json['is_downloading'] ?? false,
      downloadProgress: (json['download_progress'] as num?)?.toDouble() ?? 0.0,
      fileSize: json['file_size'] ?? '0 MB',
      downloadedEpisodesCount: json['downloaded_episodes_count'] ?? 0,
    );
  }

  static int? _parseDuration(String duration) {
    try {
      if (duration.contains('h')) {
        final parts = duration.split('h');
        int hours = int.parse(parts[0].trim());
        int minutes = 0;
        if (parts[1].contains('m')) {
          minutes = int.parse(parts[1].replaceAll('m', '').trim());
        }
        return (hours * 60) + minutes;
      }
      return int.tryParse(duration.replaceAll('min', '').trim());
    } catch (_) {
      return null;
    }
  }

  Movie copyWith({
    bool? isDownloaded,
    bool? isDownloading,
    double? downloadProgress,
    int? downloadedEpisodesCount,
    String? localPath,
    String? videoUrl,
    String? trailerUrl,
    String? contentType,
    bool? isPublished,
    String? fileSize,
    int? seasonNumber,
  }) {
    return Movie(
      id: id,
      backendId: backendId,
      title: title,
      shortDesc: shortDesc,
      overview: overview,
      posterPath: posterPath,
      backdropPath: backdropPath,
      bannerUrl: bannerUrl,
      thumbnailUrl: thumbnailUrl,
      releaseDate: releaseDate,
      voteAverage: voteAverage,
      runtime: runtime,
      genres: genres,
      cast: cast,
      director: director,
      ageRating: ageRating,
      contentRating: contentRating,
      language: language,
      country: country,
      tags: tags,
      quality: quality,
      status: status,
      accessType: accessType,
      views: views,
      isTvShow: isTvShow,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      seasons: seasons,
      videoUrl: videoUrl ?? this.videoUrl,
      sources: sources,
      trailerUrl: trailerUrl ?? this.trailerUrl,
      trailerType: trailerType,
      contentType: contentType ?? this.contentType,
      isPublished: isPublished ?? this.isPublished,
      notifyUsers: notifyUsers,
      localPath: localPath ?? this.localPath,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      fileSize: fileSize ?? this.fileSize,
      downloadedEpisodesCount: downloadedEpisodesCount ?? this.downloadedEpisodesCount,
    );
  }
}

class Season {
  final int number;
  final String title;
  final List<Episode> episodes;

  Season({required this.number, required this.title, required this.episodes});

  factory Season.fromJson(Map<String, dynamic> json) {
    return Season(
      number: json['number'] ?? 0,
      title: json['title'] ?? '',
      episodes: json['episodes'] != null ? (json['episodes'] as List).map((e) => Episode.fromJson(e)).toList() : [],
    );
  }
}

class Episode {
  final int number;
  final String title;
  final String duration;
  final String? videoUrl;

  Episode({required this.number, required this.title, required this.duration, this.videoUrl});

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      number: json['number'] ?? 0,
      title: json['title'] ?? '',
      duration: json['duration'] ?? '',
      videoUrl: json['videoUrl'],
    );
  }
}
