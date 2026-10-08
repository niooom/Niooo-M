import "dart:convert";
import "../services/niooom_public_api_service.dart";
import "../services/platform_bridge.dart";

class CastMember {
  final String name;
  final String role;
  final String avatarUrl;

  const CastMember({
    required this.name,
    required this.role,
    required this.avatarUrl,
  });
}

class MovieComment {
  final String id;
  final String authorName;
  final String authorHandle;
  final String avatarUrl;
  final String comment;
  final String timeAgo;
  final int likes;

  const MovieComment({
    required this.id,
    required this.authorName,
    required this.authorHandle,
    required this.avatarUrl,
    required this.comment,
    required this.timeAgo,
    this.likes = 0,
  });
}

class SeriesSeasonItem {
  final int season;
  final String posterUrl;
  final int episodeCount;
  final List<MovieItem> episodes;

  const SeriesSeasonItem({
    required this.season,
    required this.posterUrl,
    required this.episodeCount,
    required this.episodes,
  });
}

class SeriesCatalogItem {
  final String id;
  final String title;
  final String posterUrl;
  final String description;
  final int releaseYear;
  final List<String> genres;
  final String language;
  final int episodeCount;
  final int seasonCount;
  final List<SeriesSeasonItem> seasons;

  const SeriesCatalogItem({
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.description,
    required this.releaseYear,
    required this.genres,
    required this.language,
    required this.episodeCount,
    required this.seasonCount,
    this.seasons = const [],
  });

  List<MovieItem> get allEpisodes {
    final List<MovieItem> list = [];
    for (final s in seasons) {
      list.addAll(s.episodes);
    }
    return list;
  }
}

class MovieItem {
  final String id;
  final String streamtapeId;
  final String type; // "movie" | "episode"
  final String title;
  final String rawTitle;
  final String seriesId;
  final String seriesName;
  final int seasonNumber;
  final int episodeNumber;
  final String episodeLabel;
  final String language;
  final String tagline;
  final String synopsis;
  final String posterUrl;
  final String backdropUrl;
  final String embedUrl;
  final String downloadUrl;
  final String videoStreamUrl;
  final int sizeBytes;
  final double rating;
  final int releaseYear;
  final String duration;
  final String maturityRating;
  final String qualityBadge;
  final List<String> genres;
  final String director;
  final List<CastMember> cast;
  final bool isFeatured;
  final bool isTrending;
  final bool isNewRelease;
  final double watchProgress;
  final int likesCount;
  final int sharesCount;
  final String viewsLabel;
  final List<MovieComment> comments;

  const MovieItem({
    required this.id,
    this.streamtapeId = "",
    this.type = "movie",
    required this.title,
    this.rawTitle = "",
    this.seriesId = "",
    this.seriesName = "",
    this.seasonNumber = 0,
    this.episodeNumber = 0,
    this.episodeLabel = "",
    this.language = "Hindi",
    required this.tagline,
    required this.synopsis,
    required this.posterUrl,
    required this.backdropUrl,
    this.embedUrl = "",
    this.downloadUrl = "",
    required this.videoStreamUrl,
    this.sizeBytes = 0,
    required this.rating,
    required this.releaseYear,
    required this.duration,
    required this.maturityRating,
    required this.qualityBadge,
    required this.genres,
    required this.director,
    required this.cast,
    this.isFeatured = false,
    this.isTrending = false,
    this.isNewRelease = false,
    this.watchProgress = 0.0,
    this.likesCount = 1240,
    this.sharesCount = 310,
    this.viewsLabel = "1.8M views",
    this.comments = const [],
  });

  bool get isEpisode => type == "episode" || episodeNumber > 0 || seriesId.isNotEmpty;

  static String sanitizeWebImageUrl(String? rawUrl) {
    return NiooomPublicApiService.cleanPosterUrl(rawUrl);
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "streamtapeId": streamtapeId,
      "type": type,
      "title": title,
      "rawTitle": rawTitle,
      "seriesId": seriesId,
      "seriesName": seriesName,
      "seasonNumber": seasonNumber,
      "episodeNumber": episodeNumber,
      "episodeLabel": episodeLabel,
      "language": language,
      "tagline": tagline,
      "synopsis": synopsis,
      "posterUrl": posterUrl,
      "backdropUrl": backdropUrl,
      "embedUrl": embedUrl,
      "downloadUrl": downloadUrl,
      "videoStreamUrl": videoStreamUrl,
      "sizeBytes": sizeBytes,
      "rating": rating,
      "releaseYear": releaseYear,
      "duration": duration,
      "maturityRating": maturityRating,
      "qualityBadge": qualityBadge,
      "genres": genres,
      "director": director,
      "isFeatured": isFeatured,
      "isTrending": isTrending,
      "isNewRelease": isNewRelease,
      "watchProgress": watchProgress,
      "likesCount": likesCount,
      "sharesCount": sharesCount,
      "viewsLabel": viewsLabel,
    };
  }

  /// Creates a `MovieItem` from the official Niooo M Public API JSON object
  /// (`/api/public/v1/movies`, `/api/public/v1/videos`, or `/api/public/v1/series/{id}`)
  factory MovieItem.fromPublicApiJson(
    Map<String, dynamic> json, {
    String? fallbackSeriesId,
    String? fallbackSeriesTitle,
    String? fallbackSeriesPoster,
    String? fallbackSeriesLanguage,
    List<String>? fallbackSeriesGenres,
    int? fallbackYear,
    int index = 0,
  }) {
    final String rawId = (json["id"] ?? "").toString();
    final String streamUrl = (json["stream_url"] ?? json["embedUrl"] ?? "").toString();
    final String downloadUrl = (json["download_url"] ?? json["downloadUrl"] ?? "").toString();
    final String stId = (json["streamtapeId"] ?? "").toString().isNotEmpty
        ? json["streamtapeId"].toString()
        : NiooomPublicApiService.extractStreamtapeFileId(streamUrl, downloadUrl);

    final String effectiveId = rawId.isNotEmpty ? rawId : stId;
    final String rawTitle = (json["rawTitle"] ?? json["title"] ?? "Untitled Video").toString();
    final String itemType = (json["type"] ?? "movie").toString();

    final String seriesId =
        (json["series_id"] ?? json["seriesId"] ?? fallbackSeriesId ?? "").toString();
    final int seasonNum =
        int.tryParse((json["season"] ?? json["seasonNumber"] ?? "0").toString()) ?? 0;
    final int epNum =
        int.tryParse((json["episode"] ?? json["episodeNumber"] ?? "0").toString()) ?? 0;

    String seriesName =
        (json["seriesName"] ?? fallbackSeriesTitle ?? "").toString().trim();
    if (seriesName.isEmpty && (itemType == "episode" || epNum > 0)) {
      final sMatch = RegExp(r"^(.*?)\s+S\d+E\d+", caseSensitive: false)
          .firstMatch(rawTitle);
      if (sMatch != null && sMatch.group(1) != null) {
        seriesName = sMatch.group(1)!.replaceAll(".", " ").trim();
      }
    }

    String cleanTitle = NiooomPublicApiService.cleanDisplayTitle(rawTitle);
    final String? epTitle = json["episode_title"]?.toString();
    String episodeLabel = (json["episodeLabel"] ?? "").toString();
    if (epNum > 0 && episodeLabel.isEmpty) {
      final sPad = (seasonNum > 0 ? seasonNum : 1).toString().padLeft(2, "0");
      final ePad = epNum.toString().padLeft(2, "0");
      episodeLabel = "S${sPad}E$ePad";
    }

    if (epNum > 0 && seriesName.isNotEmpty) {
      if (epTitle != null && epTitle.trim().isNotEmpty) {
        cleanTitle = "$seriesName · $episodeLabel — ${epTitle.trim()}";
      } else {
        cleanTitle = "$seriesName · $episodeLabel";
      }
    }

    final String apiPoster = (json["poster"] ?? json["posterUrl"] ?? "").toString();
    final String apiThumb = (json["thumbnail"] ?? json["backdropUrl"] ?? "").toString();
    final String chosenPoster = apiPoster.isNotEmpty
        ? apiPoster
        : (fallbackSeriesPoster != null && fallbackSeriesPoster.isNotEmpty
            ? fallbackSeriesPoster
            : apiThumb);
    final String chosenBackdrop = apiThumb.isNotEmpty ? apiThumb : chosenPoster;

    final String posterUrl = sanitizeWebImageUrl(chosenPoster);
    final String backdropUrl = sanitizeWebImageUrl(chosenBackdrop);

    final String language = NiooomPublicApiService.resolveLanguage(
      (json["language"] ?? fallbackSeriesLanguage)?.toString(),
      rawTitle,
    );

    final List<String> genresList = [];
    if (json["genres"] is List) {
      for (final g in (json["genres"] as List)) {
        final gs = g.toString().trim();
        if (gs.isNotEmpty) genresList.add(gs);
      }
    }
    if (genresList.isEmpty && fallbackSeriesGenres != null) {
      genresList.addAll(fallbackSeriesGenres);
    }
    if (genresList.isEmpty) {
      final lower = rawTitle.toLowerCase();
      if (lower.contains("love") || lower.contains("romance")) {
        genresList.add("Romance");
        genresList.add("Drama");
      } else if (lower.contains("operation") ||
          lower.contains("war") ||
          lower.contains("ruler") ||
          lower.contains("king")) {
        genresList.add("Action");
        genresList.add("Thriller");
      } else {
        genresList.add("Action");
        genresList.add("Cinema");
      }
    }

    final int releaseYear = int.tryParse(
          (json["year"] ?? json["releaseYear"] ?? fallbackYear ?? "").toString(),
        ) ??
        _extractYearFromTitle(rawTitle) ??
        2025;

    final int sizeBytes =
        int.tryParse((json["size_bytes"] ?? json["sizeBytes"] ?? "0").toString()) ?? 0;
    final String sizeFormatted = sizeBytes > 0
        ? NiooomPublicApiService.formatBytes(sizeBytes)
        : (json["duration"] ?? "HD Stream").toString();

    final String qualityBadge = (json["qualityBadge"] ?? "").toString().isNotEmpty
        ? json["qualityBadge"].toString()
        : NiooomPublicApiService.extractQualityBadge(rawTitle, language);

    final String rawDescription = (json["description"] ?? json["synopsis"] ?? "").toString().trim();
    final String synopsis = rawDescription.isNotEmpty && rawDescription != "null"
        ? rawDescription
        : (epNum > 0
            ? "Watch $cleanTitle ($language) in $qualityBadge ($sizeFormatted) directly from Niooo M Catalog."
            : "Watch $cleanTitle ($releaseYear · $language) in $qualityBadge ($sizeFormatted) directly from Niooo M Catalog.");

    final String embedUrl = streamUrl.isNotEmpty
        ? streamUrl
        : (stId.isNotEmpty ? "https://streamtape.com/e/$stId/" : "");

    final String directTarget = stId.isNotEmpty ? stId : embedUrl;

    return MovieItem(
      id: effectiveId,
      streamtapeId: stId,
      type: itemType,
      title: cleanTitle,
      rawTitle: rawTitle,
      seriesId: seriesId,
      seriesName: seriesName,
      seasonNumber: seasonNum > 0 ? seasonNum : (epNum > 0 ? 1 : 0),
      episodeNumber: epNum,
      episodeLabel: episodeLabel,
      language: language,
      tagline: "$language · $qualityBadge · $sizeFormatted",
      synopsis: synopsis,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      embedUrl: embedUrl,
      downloadUrl: downloadUrl,
      videoStreamUrl: "/api/streamtape/direct?file=${Uri.encodeComponent(directTarget)}",
      sizeBytes: sizeBytes,
      rating: double.tryParse((json["rating"] ?? "").toString()) ??
          (9.4 - (index % 7) * 0.1),
      releaseYear: releaseYear,
      duration: sizeFormatted,
      maturityRating: language,
      qualityBadge: qualityBadge,
      genres: genresList,
      director: "Niooo M Official Catalog",
      cast: [
        CastMember(
          name: language,
          role: "Audio Language",
          avatarUrl: posterUrl,
        ),
      ],
      isFeatured: json["isFeatured"] == true || index < 5,
      isTrending: json["isTrending"] == true || index < 10,
      isNewRelease: json["isNewRelease"] == true || releaseYear >= 2024,
      watchProgress:
          double.tryParse((json["watchProgress"] ?? "0.0").toString()) ?? 0.0,
      likesCount:
          int.tryParse((json["likesCount"] ?? "").toString()) ?? (1850 + (index * 137) % 3200),
      sharesCount:
          int.tryParse((json["sharesCount"] ?? "").toString()) ?? (320 + (index * 53) % 900),
      viewsLabel: (json["viewsLabel"] ?? "${(1.2 + (index % 8) * 0.3).toStringAsFixed(1)}M views")
          .toString(),
      comments: [
        MovieComment(
          id: "c_${effectiveId}_1",
          authorName: "Arif Rahman",
          authorHandle: "@arif_cinema",
          avatarUrl:
              "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=200&q=80",
          comment:
              "Streaming $cleanTitle ($language) in crystal clear $qualityBadge!",
          timeAgo: "1h ago",
          likes: 184,
        ),
      ],
    );
  }

  static int? _extractYearFromTitle(String title) {
    final match = RegExp(r"\b(19\d{2}|20\d{2})\b").firstMatch(title);
    if (match != null) {
      return int.tryParse(match.group(1) ?? "");
    }
    return null;
  }

  MovieItem copyWith({
    String? title,
    String? seriesId,
    String? seriesName,
    int? seasonNumber,
    String? episodeLabel,
    int? episodeNumber,
    String? language,
    String? tagline,
    String? synopsis,
    String? posterUrl,
    String? backdropUrl,
    String? embedUrl,
    String? downloadUrl,
    String? videoStreamUrl,
    double? rating,
    int? releaseYear,
    String? duration,
    String? qualityBadge,
    List<String>? genres,
    String? director,
    bool? isFeatured,
    bool? isTrending,
    bool? isNewRelease,
    double? watchProgress,
    int? likesCount,
    int? sharesCount,
    List<MovieComment>? comments,
  }) {
    return MovieItem(
      id: id,
      streamtapeId: streamtapeId,
      type: type,
      title: title ?? this.title,
      rawTitle: rawTitle,
      seriesId: seriesId ?? this.seriesId,
      seriesName: seriesName ?? this.seriesName,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeLabel: episodeLabel ?? this.episodeLabel,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      language: language ?? this.language,
      tagline: tagline ?? this.tagline,
      synopsis: synopsis ?? this.synopsis,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      embedUrl: embedUrl ?? this.embedUrl,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      videoStreamUrl: videoStreamUrl ?? this.videoStreamUrl,
      sizeBytes: sizeBytes,
      rating: rating ?? this.rating,
      releaseYear: releaseYear ?? this.releaseYear,
      duration: duration ?? this.duration,
      maturityRating: maturityRating,
      qualityBadge: qualityBadge ?? this.qualityBadge,
      genres: genres ?? this.genres,
      director: director ?? this.director,
      cast: cast,
      isFeatured: isFeatured ?? this.isFeatured,
      isTrending: isTrending ?? this.isTrending,
      isNewRelease: isNewRelease ?? this.isNewRelease,
      watchProgress: watchProgress ?? this.watchProgress,
      likesCount: likesCount ?? this.likesCount,
      sharesCount: sharesCount ?? this.sharesCount,
      viewsLabel: viewsLabel,
      comments: comments ?? this.comments,
    );
  }
}

class PublicCatalogSnapshot {
  final List<MovieItem> allItems; // Movies + all ordered Series Episodes
  final List<MovieItem> moviesOnly;
  final List<SeriesCatalogItem> seriesList;

  const PublicCatalogSnapshot({
    required this.allItems,
    required this.moviesOnly,
    required this.seriesList,
  });
}

class MovieCatalogData {
  static const String _verifiedCatalogCacheKey =
      "niooo_m_public_api_catalog_v2";

  static List<SeriesCatalogItem> latestSeriesList = [];

  /// Loads previously cached API catalog items so launch is instant
  static List<MovieItem> loadCachedVerifiedCatalog() {
    try {
      final raw = PlatformBridge.getLocalStorage(_verifiedCatalogCacheKey);
      if (raw != null && raw.trim().startsWith("[")) {
        final decoded = jsonDecode(raw);
        if (decoded is List && decoded.isNotEmpty) {
          int idx = 0;
          return decoded
              .whereType<Map>()
              .map(
                (m) => MovieItem.fromPublicApiJson(
                  Map<String, dynamic>.from(m),
                  index: idx++,
                ),
              )
              .toList();
        }
      }
    } catch (_) {}
    return <MovieItem>[];
  }

  static void saveVerifiedCatalogCache(List<MovieItem> movies) {
    try {
      final encoded = jsonEncode(movies.map((m) => m.toJson()).toList());
      PlatformBridge.setLocalStorage(_verifiedCatalogCacheKey, encoded);
    } catch (_) {}
  }

  /// Fetches the entire Niooo M Public API catalog:
  /// 1. `/api/public/v1/movies` (all standalone movies with poster, language, year, genres, stream_url)
  /// 2. `/api/public/v1/series` + `/api/public/v1/series/{id}` (all series, seasons[], and ordered episodes[])
  static Future<PublicCatalogSnapshot?> fetchLiveCatalogSnapshot() async {
    try {
      final results = await Future.wait([
        NiooomPublicApiService.fetchAllMovies(),
        NiooomPublicApiService.fetchAllSeries(),
      ]);

      final rawMovies = results[0];
      final rawSeriesList = results[1];

      final List<MovieItem> moviesOnly = [];
      int itemIndex = 0;
      for (final m in rawMovies) {
        moviesOnly.add(
          MovieItem.fromPublicApiJson(m, index: itemIndex++),
        );
      }

      // Fetch full details (`/series/{id}`) for each series in parallel so all seasons & episodes are ordered
      final List<SeriesCatalogItem> parsedSeries = [];
      final List<MovieItem> allSeriesEpisodes = [];

      if (rawSeriesList.isNotEmpty) {
        final detailFutures = rawSeriesList.map((s) {
          final sid = (s["id"] ?? "").toString();
          return NiooomPublicApiService.fetchSeriesDetail(sid);
        }).toList();

        final details = await Future.wait(detailFutures);

        for (int i = 0; i < rawSeriesList.length; i++) {
          final summary = rawSeriesList[i];
          final detail = details[i] ?? summary;

          final String seriesId = (detail["id"] ?? summary["id"] ?? "").toString();
          final String seriesTitle =
              (detail["title"] ?? summary["title"] ?? "Untitled Series").toString();
          final String seriesPoster = MovieItem.sanitizeWebImageUrl(
            (detail["poster"] ?? summary["poster"] ?? "").toString(),
          );
          final String seriesDesc =
              (detail["description"] ?? summary["description"] ?? "").toString();
          final int seriesYear = int.tryParse(
                (detail["year"] ?? summary["year"] ?? "2025").toString(),
              ) ??
              2025;

          final List<String> seriesGenres = [];
          if (detail["genres"] is List) {
            for (final g in (detail["genres"] as List)) {
              final gs = g.toString().trim();
              if (gs.isNotEmpty) seriesGenres.add(gs);
            }
          }

          String seriesLang =
              (detail["language"] ?? summary["language"] ?? "").toString().trim();

          final List<SeriesSeasonItem> seasonsList = [];
          if (detail["seasons"] is List) {
            for (final sObj in (detail["seasons"] as List)) {
              if (sObj is Map) {
                final int seasonNum =
                    int.tryParse((sObj["season"] ?? "1").toString()) ?? 1;
                final String seasonPoster = MovieItem.sanitizeWebImageUrl(
                  (sObj["poster"] ?? seriesPoster).toString(),
                );
                final List<MovieItem> epItems = [];

                if (sObj["episodes"] is List) {
                  for (final epObj in (sObj["episodes"] as List)) {
                    if (epObj is Map) {
                      final epMap = Map<String, dynamic>.from(epObj);
                      final epItem = MovieItem.fromPublicApiJson(
                        epMap,
                        fallbackSeriesId: seriesId,
                        fallbackSeriesTitle: seriesTitle,
                        fallbackSeriesPoster:
                            seasonPoster.isNotEmpty ? seasonPoster : seriesPoster,
                        fallbackSeriesLanguage:
                            seriesLang.isNotEmpty ? seriesLang : null,
                        fallbackSeriesGenres:
                            seriesGenres.isNotEmpty ? seriesGenres : null,
                        fallbackYear: seriesYear,
                        index: itemIndex++,
                      );
                      if (seriesLang.isEmpty && epItem.language.isNotEmpty) {
                        seriesLang = epItem.language;
                      }
                      epItems.add(epItem);
                      allSeriesEpisodes.add(epItem);
                    }
                  }
                }

                epItems.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
                seasonsList.add(
                  SeriesSeasonItem(
                    season: seasonNum,
                    posterUrl: seasonPoster.isNotEmpty ? seasonPoster : seriesPoster,
                    episodeCount: epItems.length,
                    episodes: epItems,
                  ),
                );
              }
            }
          }

          seasonsList.sort((a, b) => a.season.compareTo(b.season));
          final int totalEpCount = seasonsList.fold<int>(
            0,
            (sum, s) => sum + s.episodes.length,
          );

          parsedSeries.add(
            SeriesCatalogItem(
              id: seriesId,
              title: seriesTitle,
              posterUrl: seriesPoster,
              description: seriesDesc.isNotEmpty && seriesDesc != "null"
                  ? seriesDesc
                  : "Watch all $totalEpCount episodes of $seriesTitle in HD.",
              releaseYear: seriesYear,
              genres: seriesGenres.isNotEmpty ? seriesGenres : const ["Drama", "Series"],
              language: seriesLang.isNotEmpty ? seriesLang : "Hindi",
              episodeCount: totalEpCount > 0
                  ? totalEpCount
                  : (int.tryParse((summary["episode_count"] ?? "0").toString()) ?? 0),
              seasonCount: seasonsList.isNotEmpty
                  ? seasonsList.length
                  : (int.tryParse((summary["season_count"] ?? "1").toString()) ?? 1),
              seasons: seasonsList,
            ),
          );
        }
      }

      // Fallback: if `/movies` + `/series` returned nothing, try `/videos`
      if (moviesOnly.isEmpty && allSeriesEpisodes.isEmpty) {
        final rawVideos = await NiooomPublicApiService.fetchAllVideos();
        for (final v in rawVideos) {
          final item = MovieItem.fromPublicApiJson(v, index: itemIndex++);
          if (item.isEpisode) {
            allSeriesEpisodes.add(item);
          } else {
            moviesOnly.add(item);
          }
        }
      }

      final List<MovieItem> combined = [...moviesOnly, ...allSeriesEpisodes];
      if (combined.isNotEmpty) {
        latestSeriesList = parsedSeries;
        saveVerifiedCatalogCache(combined);
        return PublicCatalogSnapshot(
          allItems: combined,
          moviesOnly: moviesOnly,
          seriesList: parsedSeries,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Compatibility helper that returns the full list of movies + episodes from the Public API
  static Future<List<MovieItem>?> fetchLiveStreamtapeCatalog() async {
    final snap = await fetchLiveCatalogSnapshot();
    return snap?.allItems;
  }

  /// Resolves the direct MP4 video stream URL from a MovieItem or Streamtape file ID/embed URL
  /// for Android native playback.
  static Future<String?> resolveDirectStreamUrl(String fileOrStreamUrl) async {
    try {
      final raw = await PlatformBridge.httpGetString(
        "/api/streamtape/direct?file=${Uri.encodeComponent(fileOrStreamUrl)}",
      );
      if (raw.trim().startsWith("{")) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final url = (decoded["url"] ?? "").toString();
          if (url.startsWith("http")) {
            return url;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
