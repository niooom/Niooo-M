import "dart:convert";
import "platform_bridge.dart";

class NiooomPublicApiService {
  static const String apiKey =
      "cl_3bbd97d2b14d3f81cf98ac2bf168e69581724ca4e3b9e76a";
  static const String remoteApiBaseUrl =
      "https://niooom.lovable.app/api/public/v1";

  static Map<String, String> get _authHeaders => const {
        "x-api-key": apiKey,
        "Authorization": "Bearer $apiKey",
        "Accept": "application/json",
      };

  /// Cleans poster/thumbnail URLs and proxies tapecontent.net on Web if needed
  static String cleanPosterUrl(String? rawUrl) {
    final raw = (rawUrl ?? "").trim();
    if (raw.isEmpty || !raw.startsWith("http")) return "";
    if (PlatformBridge.isWeb && raw.contains("tapecontent.net")) {
      return "/api/streamtape/thumb?url=${Uri.encodeComponent(raw)}";
    }
    return raw;
  }

  /// Extracts Streamtape file ID from `stream_url` or `download_url`
  /// e.g. `https://streamtape.com/e/3DAy2KYgY6tLRx/` -> `3DAy2KYgY6tLRx`
  static String extractStreamtapeFileId(String? streamUrl, String? downloadUrl) {
    for (final candidate in [streamUrl ?? "", downloadUrl ?? ""]) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty) continue;
      final match = RegExp(
        r"streamtape\.com/(?:e|v)/([a-zA-Z0-9_-]+)",
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (match != null && match.group(1) != null) {
        return match.group(1)!;
      }
    }
    return "";
  }

  /// Formats byte size into human-readable string (e.g. `1.24 GB` or `358 MB`)
  static String formatBytes(dynamic rawBytes) {
    final int bytes = rawBytes is int
        ? rawBytes
        : int.tryParse((rawBytes ?? "0").toString()) ?? 0;
    if (bytes <= 0) return "HD Stream";
    final double gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1.0) {
      return "${gb.toStringAsFixed(2)} GB";
    }
    final double mb = bytes / (1024 * 1024);
    return "${mb.round()} MB";
  }

  /// Cleans release/file names into a readable display title while keeping SxxExx info
  static String cleanDisplayTitle(String rawTitle) {
    String t = rawTitle
        .replaceAll(RegExp(r"^MovieLinkBD\.[a-zA-Z]+\s*-\s*", caseSensitive: false), "")
        .replaceAll(RegExp(r"\.(mkv|mp4|avi)$", caseSensitive: false), "")
        .replaceAll(RegExp(r"\s+(mkv|mp4|avi)$", caseSensitive: false), "")
        .replaceAll(".", " ")
        .replaceAll("_", " ")
        .trim();

    // Remove technical encoding suffixes after quality/year if present
    final stripped = t
        .replaceAll(
          RegExp(
            r"\b(720p|1080p|480p|2160p|4K|WEB-DL|WEBRip|WEB\s+DL|HDRip|BluRay|DS4K|AAC|x264|h264|HEVC|x265|ESub|Msubs|org|5\s*1|2\s*0|Dual|Line).*$",
            caseSensitive: false,
          ),
          "",
        )
        .trim();

    if (stripped.length >= 3) {
      t = stripped;
    }
    return t.replaceAll(RegExp(r"\s{2,}"), " ").trim();
  }

  /// Detects quality badge from title or metadata
  static String extractQualityBadge(String rawTitle, String? language) {
    final lower = rawTitle.toLowerCase();
    String res = "HD";
    if (lower.contains("2160p") || lower.contains("4k") || lower.contains("ds4k")) {
      res = "4K HDR";
    } else if (lower.contains("1080p")) {
      res = "1080p FHD";
    } else if (lower.contains("720p")) {
      res = "720p HD";
    }

    final bool isDual = lower.contains("dual") ||
        lower.contains("multi") ||
        (lower.contains("hindi") &&
            (lower.contains("english") ||
                lower.contains("kannada") ||
                lower.contains("tamil") ||
                lower.contains("telugu") ||
                lower.contains("bangla")));

    if (isDual) {
      return "$res · Dual Audio";
    }
    if (language != null && language.trim().isNotEmpty) {
      return "$res · ${language.trim()}";
    }
    return res;
  }

  /// Detects language from API field or title fallback
  static String resolveLanguage(String? apiLanguage, String rawTitle) {
    if (apiLanguage != null && apiLanguage.trim().isNotEmpty) {
      return apiLanguage.trim();
    }
    final lower = rawTitle.toLowerCase();
    if (lower.contains("bangla") || lower.contains("bengali")) return "Bangla";
    if (lower.contains("hindi") && lower.contains("english")) {
      return "Hindi + English";
    }
    if (lower.contains("hindi") && lower.contains("kannada")) {
      return "Hindi + Kannada";
    }
    if (lower.contains("hindi")) return "Hindi";
    if (lower.contains("english")) return "English";
    if (lower.contains("korean")) return "Korean";
    if (lower.contains("tamil")) return "Tamil";
    if (lower.contains("telugu")) return "Telugu";
    return "Multi-Audio";
  }

  /// Performs an authenticated GET request against the Niooo M Public API
  /// Uses local server proxy `/api/public/v1/...` first on Web, and direct HTTPS with `x-api-key` on Android/fallback.
  static Future<Map<String, dynamic>?> fetchEndpoint(
    String subPath, {
    Map<String, String>? queryParameters,
  }) async {
    final cleanSub = subPath.startsWith("/") ? subPath : "/$subPath";
    final qs = (queryParameters != null && queryParameters.isNotEmpty)
        ? "?${Uri(queryParameters: queryParameters).query}"
        : "";

    final List<String> urlsToTry = PlatformBridge.isWeb
        ? [
            "/api/public/v1$cleanSub$qs",
            "$remoteApiBaseUrl$cleanSub$qs",
          ]
        : [
            "$remoteApiBaseUrl$cleanSub$qs",
            "/api/public/v1$cleanSub$qs",
          ];

    for (final url in urlsToTry) {
      try {
        final raw = await PlatformBridge.httpGetString(
          url,
          headers: _authHeaders,
        );
        if (raw.trim().startsWith("{")) {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Fetches `/movies?page=1&limit=200` (plus additional pages if `total_pages > 1`)
  static Future<List<Map<String, dynamic>>> fetchAllMovies({String? query}) async {
    final List<Map<String, dynamic>> results = [];
    int page = 1;
    int totalPages = 1;

    while (page <= totalPages && page <= 10) {
      final params = <String, String>{
        "page": page.toString(),
        "limit": "200",
      };
      if (query != null && query.trim().isNotEmpty) {
        params["q"] = query.trim();
      }
      final res = await fetchEndpoint("/movies", queryParameters: params);
      if (res == null) break;

      final data = res["data"];
      if (data is List) {
        for (final item in data) {
          if (item is Map) {
            results.add(Map<String, dynamic>.from(item));
          }
        }
      }
      totalPages = int.tryParse((res["total_pages"] ?? "1").toString()) ?? 1;
      page++;
    }
    return results;
  }

  /// Fetches `/series?page=1&limit=200`
  static Future<List<Map<String, dynamic>>> fetchAllSeries({String? query}) async {
    final params = <String, String>{
      "page": "1",
      "limit": "200",
    };
    if (query != null && query.trim().isNotEmpty) {
      params["q"] = query.trim();
    }
    final res = await fetchEndpoint("/series", queryParameters: params);
    final List<Map<String, dynamic>> list = [];
    if (res != null && res["data"] is List) {
      for (final item in (res["data"] as List)) {
        if (item is Map) {
          list.add(Map<String, dynamic>.from(item));
        }
      }
    }
    return list;
  }

  /// Fetches `/series/{id}` (or `/series/{id}?season=X`) with full seasons[] and ordered episodes[]
  static Future<Map<String, dynamic>?> fetchSeriesDetail(
    String seriesId, {
    int? season,
  }) async {
    final params = <String, String>{};
    if (season != null) {
      params["season"] = season.toString();
    }
    final res = await fetchEndpoint(
      "/series/$seriesId",
      queryParameters: params.isEmpty ? null : params,
    );
    if (res != null && res["data"] is Map) {
      return Map<String, dynamic>.from(res["data"] as Map);
    }
    return res;
  }

  /// Fetches `/videos?page=1&limit=200` (all movies + episodes)
  static Future<List<Map<String, dynamic>>> fetchAllVideos({String? query}) async {
    final List<Map<String, dynamic>> results = [];
    int page = 1;
    int totalPages = 1;

    while (page <= totalPages && page <= 10) {
      final params = <String, String>{
        "page": page.toString(),
        "limit": "200",
      };
      if (query != null && query.trim().isNotEmpty) {
        params["q"] = query.trim();
      }
      final res = await fetchEndpoint("/videos", queryParameters: params);
      if (res == null) break;

      final data = res["data"];
      if (data is List) {
        for (final item in data) {
          if (item is Map) {
            results.add(Map<String, dynamic>.from(item));
          }
        }
      }
      totalPages = int.tryParse((res["total_pages"] ?? "1").toString()) ?? 1;
      page++;
    }
    return results;
  }

  /// Fetches single video `/videos/{id}` or episode `/episodes/{id}`
  static Future<Map<String, dynamic>?> fetchSingleVideo(String id) async {
    final res = await fetchEndpoint("/videos/$id");
    if (res != null && res["data"] is Map) {
      return Map<String, dynamic>.from(res["data"] as Map);
    }
    return res;
  }
}
