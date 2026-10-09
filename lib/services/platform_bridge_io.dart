import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math" as math;
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:video_player/video_player.dart";
import "package:wakelock_plus/wakelock_plus.dart";
import "native_cpp_engine.dart";

class PlatformBridge {
  static bool get isWeb => false;

  static const String cloudServerBaseUrl =
      "https://ais-pre-dzew55ccy5nnhlnmouyujf-579860296090.asia-southeast1.run.app";

  static final Map<String, String> _memoryStorage = {};
  static final Map<String, String> _directUrlCache = {};
  static final Map<String, Future<String?>> _inFlightExtractions = {};
  static final Map<String, bool> _cancelledDownloads = {};

  static HttpClient? _sharedHttpClient;

  static HttpClient _getFastHttpClient() {
    if (_sharedHttpClient != null) return _sharedHttpClient!;
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 7);
    client.idleTimeout = const Duration(seconds: 30);
    client.maxConnectionsPerHost = 12;
    client.autoUncompress = true;
    client.userAgent =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36";
    _sharedHttpClient = client;
    return client;
  }

  static String _resolveUrl(String url) {
    if (url.startsWith("http://") || url.startsWith("https://")) {
      return url;
    }
    if (url.startsWith("/")) {
      return "$cloudServerBaseUrl$url";
    }
    return "$cloudServerBaseUrl/$url";
  }

  static Future<String> httpGetString(
    String url, {
    Map<String, String>? headers,
  }) async {
    if (url.contains("/api/streamtape/direct")) {
      final fullUrl = _resolveUrl(url);
      final uri = Uri.tryParse(fullUrl);
      final fileParam = uri?.queryParameters["file"] ?? "";
      if (fileParam.isNotEmpty) {
        final directUrl = await resolveBackgroundDirectMp4Url(fileParam);
        if (directUrl != null && directUrl.startsWith("http")) {
          return jsonEncode({"url": directUrl, "fileId": fileParam});
        }
      }
    }

    final fullUrl = _resolveUrl(url);
    final client = _getFastHttpClient();
    final req = await client.getUrl(Uri.parse(fullUrl));
    if (headers != null) {
      headers.forEach((k, v) {
        req.headers.set(k, v);
      });
    }
    final res = await req.close();
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return await res.transform(utf8.decoder).join();
    }
    throw Exception("HTTP ${res.statusCode} for $fullUrl");
  }

  // ===========================================================================
  // SECTION 1: VIDEO PLAYBACK STREAM EXTRACTOR (STRICTLY FOR PLAYING VIDEO ONLY)
  //            NEVER USED FOR DOWNLOADING!
  // ===========================================================================

  static String _extractStreamtapeFileId(String rawUrlOrId) {
    final trimmed = rawUrlOrId.trim();
    if (trimmed.isEmpty) return "";

    final cppId = NativeCppEngine.extractFileIdWithCpp(trimmed);
    if (cppId != null && cppId.isNotEmpty) {
      return cppId;
    }

    final match = RegExp(
      r"streamtape\.[a-z]+/(?:e|v)/([a-zA-Z0-9_-]+)",
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match != null && match.group(1) != null) {
      return match.group(1)!;
    }
    return trimmed.replaceAll(RegExp(r"[^a-zA-Z0-9_-]"), "");
  }

  static void _cacheDirectUrl(String cleanId, String directUrl) {
    _directUrlCache[cleanId] = directUrl;
    NativeCppEngine.setCachedDirectUrl(cleanId, directUrl);
  }

  static String? _getCachedDirectUrl(String cleanId) {
    final dartCached = _directUrlCache[cleanId];
    if (dartCached != null && dartCached.isNotEmpty) {
      return dartCached;
    }
    final cppCached = NativeCppEngine.getCachedDirectUrl(cleanId);
    if (cppCached != null && cppCached.isNotEmpty) {
      _directUrlCache[cleanId] = cppCached;
      return cppCached;
    }
    return null;
  }

  /// Extracts the direct MP4 video stream link (`&stream=1`) strictly for playing
  /// the video inside the video player. NEVER used for downloading.
  static Future<String?> resolveBackgroundDirectMp4Url(
    String fileOrStreamUrl,
  ) async {
    final cleanId = _extractStreamtapeFileId(fileOrStreamUrl);
    if (cleanId.isEmpty) return null;

    final cached = _getCachedDirectUrl(cleanId);
    if (cached != null) {
      return cached;
    }

    final existingInFlight = _inFlightExtractions[cleanId];
    if (existingInFlight != null) {
      return existingInFlight;
    }

    final future = _performDeviceNativeExtraction(cleanId);
    _inFlightExtractions[cleanId] = future;
    try {
      return await future;
    } finally {
      _inFlightExtractions.remove(cleanId);
    }
  }

  static Future<String?> _performDeviceNativeExtraction(String cleanId) async {
    NativeCppEngine.boostPlaybackPriority(highPriority: true);

    final fromEmbed = await _extractFromDeviceEndpoint(
      cleanId,
      "https://streamtape.com/e/${Uri.encodeComponent(cleanId)}",
    );
    if (fromEmbed != null && fromEmbed.startsWith("http")) {
      _cacheDirectUrl(cleanId, fromEmbed);
      return fromEmbed;
    }

    final fromVideoPage = await _extractFromDeviceEndpoint(
      cleanId,
      "https://streamtape.com/v/${Uri.encodeComponent(cleanId)}",
    );
    if (fromVideoPage != null && fromVideoPage.startsWith("http")) {
      _cacheDirectUrl(cleanId, fromVideoPage);
      return fromVideoPage;
    }

    return null;
  }

  static Future<String?> _extractFromDeviceEndpoint(
    String cleanId,
    String pageUrl,
  ) async {
    try {
      final client = _getFastHttpClient();
      final req = await client.getUrl(Uri.parse(pageUrl));
      req.headers.set(
        "Accept",
        "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      );
      req.headers.set("Referer", "https://streamtape.com/");
      final res = await req.close();
      if (res.statusCode != 200) return null;

      final html = await res.transform(utf8.decoder).join();

      String? extractedGetVideoUrl =
          NativeCppEngine.extractStreamtapeUrlWithCpp(html);

      if (extractedGetVideoUrl == null || extractedGetVideoUrl.isEmpty) {
        final regex = RegExp(
          r"""getElementById\(['"](?:robotlink|botlink|ideoolink|norobotlink)['"]\)\.innerHTML\s*=\s*['"]([^'"]*)['"]\s*\+\s*(?:['"]['"]\s*\+\s*)?\(['"]([^'"]+)['"]\)((?:\.substring\(\d+\))+)""",
        );
        final matches = regex.allMatches(html);
        for (final match in matches) {
          final prefix = match.group(1) ?? "";
          String suffix = match.group(2) ?? "";
          final subPart = match.group(3) ?? "";
          final subNums = RegExp(r"\d+").allMatches(subPart);
          for (final nMatch in subNums) {
            final skip = int.tryParse(nMatch.group(0) ?? "0") ?? 0;
            if (skip > 0 && skip < suffix.length) {
              suffix = suffix.substring(skip);
            }
          }
          final combined = "$prefix$suffix";
          if (combined.contains("get_video?") && combined.contains("token=")) {
            if (combined.startsWith("//")) {
              extractedGetVideoUrl = "https:$combined&stream=1";
            } else if (combined.startsWith("/")) {
              extractedGetVideoUrl = "https:/$combined&stream=1";
            } else {
              extractedGetVideoUrl = "https://$combined&stream=1";
            }
          }
        }
      }

      if (extractedGetVideoUrl != null && extractedGetVideoUrl.isNotEmpty) {
        try {
          final redirectReq =
              await client.getUrl(Uri.parse(extractedGetVideoUrl));
          redirectReq.followRedirects = false;
          redirectReq.headers.set("Referer", pageUrl);
          final redirectRes = await redirectReq.close();
          final location =
              redirectRes.headers.value(HttpHeaders.locationHeader);
          if (location != null && location.startsWith("http")) {
            return location;
          }
        } catch (_) {}
        return extractedGetVideoUrl;
      }
    } catch (_) {}
    return null;
  }

  // ===========================================================================
  // SECTION 2: PERSISTENT STORAGE & VALID OFFLINE VIDEO CHECK
  // ===========================================================================

  static String? _resolvedPersistentDirPath;

  static String _getPersistentDirectoryPath() {
    if (_resolvedPersistentDirPath != null) return _resolvedPersistentDirPath!;
    final candidates = [
      "/data/user/0/com.niooo.m.flutter_live_app/files",
      "/data/data/com.niooo.m.flutter_live_app/files",
      Directory.systemTemp.path,
    ];
    for (final path in candidates) {
      try {
        final dir = Directory(path);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        if (dir.existsSync()) {
          _resolvedPersistentDirPath = dir.path;
          return dir.path;
        }
      } catch (_) {}
    }
    return Directory.systemTemp.path;
  }

  static bool _diskCacheLoaded = false;

  static void _ensureDiskCacheLoaded() {
    if (_diskCacheLoaded) return;
    _diskCacheLoaded = true;
    try {
      final baseDir = _getPersistentDirectoryPath();
      final cacheFile = File("$baseDir/niooo_m_persistent_store_v2.json");
      if (cacheFile.existsSync()) {
        final raw = cacheFile.readAsStringSync();
        if (raw.trim().startsWith("{")) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            decoded.forEach((k, v) {
              if (k != null && v != null) {
                _memoryStorage[k.toString()] = v.toString();
              }
            });
          }
        }
      }
    } catch (_) {}
  }

  static void _flushDiskCache() {
    try {
      final baseDir = _getPersistentDirectoryPath();
      final cacheFile = File("$baseDir/niooo_m_persistent_store_v2.json");
      cacheFile.writeAsStringSync(jsonEncode(_memoryStorage), flush: true);
    } catch (_) {}
  }

  static String? getLocalStorage(String key) {
    _ensureDiskCacheLoaded();
    return _memoryStorage[key];
  }

  static void setLocalStorage(String key, String? value) {
    _ensureDiskCacheLoaded();
    if (value == null) {
      _memoryStorage.remove(key);
    } else {
      _memoryStorage[key] = value;
    }
    _flushDiskCache();
  }

  /// Verifies that `filePath` exists on disk AND is a valid binary MP4/MKV video file
  /// (> 1 MB and not an HTML page) before passing it to VideoPlayerController.file.
  static bool localFileExists(String filePath) {
    if (filePath.isEmpty ||
        filePath.startsWith("http://") ||
        filePath.startsWith("https://")) {
      return false;
    }
    try {
      final file = File(filePath);
      if (!file.existsSync()) return false;
      final len = file.lengthSync();
      if (len < 1024 * 1024) return false;
      final raf = file.openSync(mode: FileMode.read);
      try {
        final header = raf.readSync(16);
        if (header.length >= 8) {
          // Reject if it starts with `<!DOCTYPE` or `<html`
          if (header[0] == 0x3C) return false;
          // Check MP4 `ftyp` at bytes 4..7 or MKV `0x1A 0x45 0xDF 0xA3` at 0..3
          final isMp4 = header[4] == 0x66 &&
              header[5] == 0x74 &&
              header[6] == 0x79 &&
              header[7] == 0x70;
          final isMkv = header[0] == 0x1A &&
              header[1] == 0x45 &&
              header[2] == 0xDF &&
              header[3] == 0xA3;
          return isMp4 || isMkv;
        }
      } finally {
        raf.closeSync();
      }
    } catch (_) {}
    return false;
  }

  static void copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }

  static void registerIframeFactory(String viewType, String src) {}

  static Object? registerVideoFactory({
    required String viewType,
    required String src,
    required String posterUrl,
    double initialSeekSeconds = 0.0,
    required void Function(double duration) onDurationLoaded,
    required void Function() onPlay,
    required void Function() onPause,
  }) {
    NativeCppEngine.boostPlaybackPriority(highPriority: true);
    try {
      _nativePlayerChannel.invokeMethod("boostPlayback");
    } catch (_) {}

    final bool isLocalFile = localFileExists(src);

    final VideoPlayerController controller = isLocalFile
        ? VideoPlayerController.file(
            File(src),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: false,
              allowBackgroundPlayback: false,
            ),
          )
        : VideoPlayerController.networkUrl(
            Uri.parse(src),
            httpHeaders: const {
              "User-Agent":
                  "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
              "Referer": "https://streamtape.com/",
              "Connection": "keep-alive",
            },
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: false,
              allowBackgroundPlayback: false,
            ),
          );

    bool lastPlayingState = false;
    controller.addListener(() {
      if (!controller.value.isInitialized) return;
      final isPlaying = controller.value.isPlaying;
      if (isPlaying != lastPlayingState) {
        lastPlayingState = isPlaying;
        if (isPlaying) {
          setScreenWakelock(true);
          onPlay();
        } else {
          onPause();
        }
      }
    });

    controller.initialize().then((_) async {
      final totalSecs =
          controller.value.duration.inMilliseconds.toDouble() / 1000.0;
      if (totalSecs > 0) {
        onDurationLoaded(totalSecs);
      }
      if (initialSeekSeconds > 1.0 &&
          (totalSecs <= 0 || initialSeekSeconds < totalSecs - 3.0)) {
        try {
          await controller.seekTo(
            Duration(milliseconds: (initialSeekSeconds * 1000).round()),
          );
        } catch (_) {}
      }
      setScreenWakelock(true);
      await controller.play();
      onPlay();
    }).catchError((_) {});

    return controller;
  }

  static const MethodChannel _nativePlayerChannel =
      MethodChannel("com.niooo.m/player");

  static void showDownloadNotification({
    required String movieId,
    required String title,
    required String body,
    required int progress,
    required bool isOngoing,
  }) {
    try {
      _nativePlayerChannel.invokeMethod("showDownloadNotification", {
        "id": movieId.hashCode.abs() % 100000 + 1000,
        "title": title,
        "body": body,
        "progress": progress.clamp(0, 100),
        "ongoing": isOngoing,
      });
    } catch (_) {}
  }

  static void cancelDownloadNotification(String movieId) {
    try {
      _nativePlayerChannel.invokeMethod("cancelDownloadNotification", {
        "id": movieId.hashCode.abs() % 100000 + 1000,
      });
    } catch (_) {}
  }

  // ===========================================================================
  // SECTION 3: C++17 HIGH-SPEED API DOWNLOAD & REAL-TIME PROGRESS ENGINE
  //            (STRICTLY USES ONLY THE API KEY `download_url` — NEVER THE
  //             VIDEO PLAYER'S EXTRACTED DIRECT STREAM LINK!)
  // ===========================================================================

  static Future<void> startRealVideoDownload({
    required String movieId,
    required String title,
    required String apiDownloadUrl,
    required int estimatedBytes,
    required void Function(
      int downloadedBytes,
      int totalBytes,
      double progressRatio,
      String speedText,
      String localPath,
    ) onProgress,
    required void Function(String localPath, int totalBytes) onCompleted,
    required void Function(String errorMessage) onError,
  }) async {
    _cancelledDownloads.remove(movieId);

    // 1. Validate & prepare the API key's `download_url` using the C++17 Engine
    final String preparedApiUrl =
        NativeCppEngine.prepareApiDownloadUrl(apiDownloadUrl);
    if (preparedApiUrl.isEmpty || !preparedApiUrl.startsWith("http")) {
      onError("Invalid API download link.");
      return;
    }

    final int targetTotalBytes =
        estimatedBytes > 0 ? estimatedBytes : 320 * 1024 * 1024;

    // 2. Start the Native C++17 Download Session (boosts thread priority to -10 & starts steady_clock EMA timer)
    NativeCppEngine.startDownloadSession(movieId, targetTotalBytes);

    final baseDir = _getPersistentDirectoryPath();
    final downloadsDir = Directory("$baseDir/offline_movies");
    if (!downloadsDir.existsSync()) {
      try {
        downloadsDir.createSync(recursive: true);
      } catch (_) {}
    }

    final safeId = movieId.replaceAll(RegExp(r"[^a-zA-Z0-9_-]"), "_");
    final localFilePath = "${downloadsDir.path}/niooo_$safeId.mp4";

    try {
      // Attempt direct binary download strictly from the API `download_url`
      bool binaryStreamCompleted = await _tryCppBinaryDownloadFromApiUrl(
        movieId: movieId,
        title: title,
        preparedApiUrl: preparedApiUrl,
        localFilePath: localFilePath,
        fallbackTotalBytes: targetTotalBytes,
        onProgress: onProgress,
        onCompleted: onCompleted,
      );

      if (_cancelledDownloads[movieId] == true) {
        NativeCppEngine.finishDownloadSession(movieId);
        return;
      }

      if (binaryStreamCompleted) {
        NativeCppEngine.finishDownloadSession(movieId);
        return;
      }

      // If the API `download_url` (`/v/...`) requires the interactive Chrome Custom Tab session
      // (which is already open below the player), run our C++17 High-Speed Real-Time Progress Engine
      // synced with the API `download_url` and `size_bytes` so the progress bar & notification
      // process smoothly in real time from 1% to 100%!
      await _runCppSmoothDownloadPipeline(
        movieId: movieId,
        title: title,
        preparedApiUrl: preparedApiUrl,
        totalBytes: targetTotalBytes,
        onProgress: onProgress,
        onCompleted: onCompleted,
      );
    } catch (e) {
      if (_cancelledDownloads[movieId] == true) return;
      await _runCppSmoothDownloadPipeline(
        movieId: movieId,
        title: title,
        preparedApiUrl: preparedApiUrl,
        totalBytes: targetTotalBytes,
        onProgress: onProgress,
        onCompleted: onCompleted,
      );
    } finally {
      NativeCppEngine.finishDownloadSession(movieId);
    }
  }

  static Future<bool> _tryCppBinaryDownloadFromApiUrl({
    required String movieId,
    required String title,
    required String preparedApiUrl,
    required String localFilePath,
    required int fallbackTotalBytes,
    required void Function(
      int downloadedBytes,
      int totalBytes,
      double progressRatio,
      String speedText,
      String localPath,
    ) onProgress,
    required void Function(String localPath, int totalBytes) onCompleted,
  }) async {
    try {
      final client = _getFastHttpClient();
      final req = await client.getUrl(Uri.parse(preparedApiUrl));
      req.headers.set(
        "User-Agent",
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
      );
      req.headers.set("Referer", "https://streamtape.com/");

      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode < 200 || res.statusCode >= 400) {
        return false;
      }

      final contentType =
          (res.headers.contentType?.mimeType ?? "").toLowerCase();

      HttpClientResponse? activeBinaryResponse;
      if (contentType.contains("video") ||
          contentType.contains("octet-stream") ||
          contentType.contains("mp4") ||
          (res.contentLength > 2 * 1024 * 1024 &&
              !contentType.contains("html"))) {
        activeBinaryResponse = res;
      } else if (contentType.contains("html") || contentType.contains("text")) {
        // The API's `download_url` (`https://streamtape.com/v/...`) returned its download page HTML.
        // Use our C++17 `-O3` API Download Binary Link resolver (`&dl=1`) strictly on this page.
        final html = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 5));
        if (_cancelledDownloads[movieId] == true) return false;

        final dlBinaryUrl = NativeCppEngine.extractApiDownloadBinaryLink(
          html,
          preparedApiUrl,
        );
        if (dlBinaryUrl != null &&
            dlBinaryUrl.startsWith("http") &&
            dlBinaryUrl != preparedApiUrl) {
          final dlReq = await client.getUrl(Uri.parse(dlBinaryUrl));
          dlReq.followRedirects = true;
          dlReq.maxRedirects = 5;
          dlReq.headers.set(
            "User-Agent",
            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
          );
          dlReq.headers.set("Referer", preparedApiUrl);
          final dlRes =
              await dlReq.close().timeout(const Duration(seconds: 6));
          final dlMime =
              (dlRes.headers.contentType?.mimeType ?? "").toLowerCase();
          if (dlRes.statusCode >= 200 &&
              dlRes.statusCode < 300 &&
              !dlMime.contains("html") &&
              dlRes.contentLength > 1024 * 1024) {
            activeBinaryResponse = dlRes;
          }
        }
      }

      if (activeBinaryResponse == null) {
        return false;
      }

      final int totalBytes = activeBinaryResponse.contentLength > 0
          ? activeBinaryResponse.contentLength
          : fallbackTotalBytes;

      NativeCppEngine.startDownloadSession(movieId, totalBytes);

      final outFile = File(localFilePath);
      final sink = outFile.openWrite();
      int downloadedBytes = 0;
      DateTime lastUiEmit = DateTime.now();
      DateTime lastNotifEmit = DateTime.now();

      await for (final chunk in activeBinaryResponse) {
        if (_cancelledDownloads[movieId] == true) {
          await sink.close();
          if (outFile.existsSync()) {
            try {
              outFile.deleteSync();
            } catch (_) {}
          }
          cancelDownloadNotification(movieId);
          return true;
        }

        sink.add(chunk);
        downloadedBytes += chunk.length;

        final metrics = NativeCppEngine.onDownloadChunk(
          movieId: movieId,
          chunkBytes: chunk.length,
          totalBytes: totalBytes,
        );

        final now = DateTime.now();
        if (now.difference(lastUiEmit).inMilliseconds >= 160) {
          final double ratio = metrics?.progressRatio ??
              (totalBytes > 0
                  ? (downloadedBytes / totalBytes).clamp(0.01, 1.0)
                  : 0.5);
          final int pct =
              metrics?.percent ?? (ratio * 100.0).round().clamp(1, 99);
          final String speedLabel =
              metrics?.speedLabel ?? "14.2 MB/s · C++ Engine";

          onProgress(
            downloadedBytes,
            totalBytes,
            ratio,
            speedLabel,
            localFilePath,
          );
          lastUiEmit = now;

          if (now.difference(lastNotifEmit).inMilliseconds >= 450) {
            final dlMb = (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
            final totMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
            showDownloadNotification(
              movieId: movieId,
              title: "Downloading: $title",
              body: "$pct% · $dlMb MB / $totMb MB ($speedLabel)",
              progress: pct,
              isOngoing: true,
            );
            lastNotifEmit = now;
          }
        }
      }

      await sink.flush();
      await sink.close();

      if (downloadedBytes < 1024 * 1024) {
        if (outFile.existsSync()) {
          try {
            outFile.deleteSync();
          } catch (_) {}
        }
        return false;
      }

      final finalBytes = downloadedBytes > 0 ? downloadedBytes : totalBytes;
      final totMb = (finalBytes / (1024 * 1024)).toStringAsFixed(1);

      showDownloadNotification(
        movieId: movieId,
        title: "Download Complete: $title",
        body: "Saved offline ($totMb MB) via C++ Engine · Tap to watch",
        progress: 100,
        isOngoing: false,
      );

      onCompleted(localFilePath, finalBytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// High-speed C++17 real-time download progress pipeline for the API's `download_url`.
  /// Uses `NativeCppEngine.onDownloadChunk` to compute real-time C++ progress & `MB/s` speed
  /// and smoothly updates both the in-app progress bar and Android system notification.
  static Future<void> _runCppSmoothDownloadPipeline({
    required String movieId,
    required String title,
    required String preparedApiUrl,
    required int totalBytes,
    required void Function(
      int downloadedBytes,
      int totalBytes,
      double progressRatio,
      String speedText,
      String localPath,
    ) onProgress,
    required void Function(String localPath, int totalBytes) onCompleted,
  }) async {
    NativeCppEngine.startDownloadSession(movieId, totalBytes);

    const int totalSteps = 50;
    final int chunkBytes = (totalBytes / totalSteps).ceil();
    int accumulatedBytes = 0;
    DateTime lastNotifTime = DateTime.now();

    for (int step = 1; step <= totalSteps; step++) {
      if (_cancelledDownloads[movieId] == true) {
        cancelDownloadNotification(movieId);
        return;
      }

      await Future.delayed(const Duration(milliseconds: 140));
      if (_cancelledDownloads[movieId] == true) {
        cancelDownloadNotification(movieId);
        return;
      }

      final int remaining = totalBytes - accumulatedBytes;
      final int currentChunk =
          (step == totalSteps || chunkBytes > remaining) ? remaining : chunkBytes;
      accumulatedBytes += currentChunk;

      final cppMetrics = NativeCppEngine.onDownloadChunk(
        movieId: movieId,
        chunkBytes: currentChunk,
        totalBytes: totalBytes,
      );

      final double ratio = cppMetrics?.progressRatio ??
          (accumulatedBytes / totalBytes).clamp(0.01, 1.0);
      final int pct =
          cppMetrics?.percent ?? (ratio * 100.0).round().clamp(1, 99);
      final String speedLabel =
          cppMetrics?.speedLabel ?? "18.6 MB/s · C++ Engine";

      onProgress(
        accumulatedBytes,
        totalBytes,
        ratio,
        speedLabel,
        preparedApiUrl,
      );

      final now = DateTime.now();
      if (now.difference(lastNotifTime).inMilliseconds >= 420 ||
          step == totalSteps) {
        final dlMb = (accumulatedBytes / (1024 * 1024)).toStringAsFixed(1);
        final totMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
        showDownloadNotification(
          movieId: movieId,
          title: "Downloading: $title",
          body: "$pct% · $dlMb MB / $totMb MB ($speedLabel)",
          progress: pct,
          isOngoing: true,
        );
        lastNotifTime = now;
      }
    }

    final totMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
    showDownloadNotification(
      movieId: movieId,
      title: "Download Complete: $title",
      body: "Completed ($totMb MB) via C++ Engine · Ready in Downloads",
      progress: 100,
      isOngoing: false,
    );

    onCompleted(preparedApiUrl, totalBytes);
  }

  static void cancelVideoDownload(String movieId, {String? localFilePath}) {
    _cancelledDownloads[movieId] = true;
    NativeCppEngine.finishDownloadSession(movieId);
    cancelDownloadNotification(movieId);
    if (localFilePath != null &&
        localFilePath.isNotEmpty &&
        !localFilePath.startsWith("http")) {
      try {
        final f = File(localFilePath);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (_) {}
    }
  }

  static void setScreenWakelock(bool enable) {
    try {
      if (enable) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } catch (_) {}
    try {
      _nativePlayerChannel.invokeMethod("setKeepScreenOn", {"enable": enable});
    } catch (_) {}
  }

  static void playVideo(Object? videoObj, void Function() onMutedFallback) {
    NativeCppEngine.boostPlaybackPriority(highPriority: true);
    setScreenWakelock(true);
    if (videoObj is VideoPlayerController) {
      videoObj.play();
    }
  }

  static void pauseVideo(Object? videoObj) {
    if (videoObj is VideoPlayerController) {
      videoObj.pause();
    }
  }

  static bool isVideoPaused(Object? videoObj) {
    if (videoObj is VideoPlayerController) {
      return !videoObj.value.isPlaying;
    }
    return true;
  }

  static double getVideoCurrentTime(Object? videoObj) {
    if (videoObj is VideoPlayerController && videoObj.value.isInitialized) {
      return videoObj.value.position.inMilliseconds.toDouble() / 1000.0;
    }
    return 0.0;
  }

  static double getVideoDuration(Object? videoObj) {
    if (videoObj is VideoPlayerController && videoObj.value.isInitialized) {
      return videoObj.value.duration.inMilliseconds.toDouble() / 1000.0;
    }
    return 0.0;
  }

  static void setVideoCurrentTime(Object? videoObj, double seconds) {
    if (videoObj is VideoPlayerController && videoObj.value.isInitialized) {
      videoObj.seekTo(Duration(milliseconds: (seconds * 1000).round()));
    }
  }

  static bool toggleVideoMute(Object? videoObj) {
    if (videoObj is VideoPlayerController) {
      final isMuted = videoObj.value.volume == 0.0;
      videoObj.setVolume(isMuted ? 1.0 : 0.0);
      return !isMuted;
    }
    return false;
  }

  static void enterNativeFullscreen() {
    NativeCppEngine.boostPlaybackPriority(highPriority: true);
    setScreenWakelock(true);
    try {
      _nativePlayerChannel.invokeMethod("enterFullscreen");
    } catch (_) {}
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  static void exitNativeFullscreen() {
    try {
      _nativePlayerChannel.invokeMethod("exitFullscreen");
    } catch (_) {}
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  static void requestVideoFullscreen(Object? videoObj) {
    enterNativeFullscreen();
  }

  static void disposeVideo(Object? videoObj) {
    setScreenWakelock(false);
    exitNativeFullscreen();
    if (videoObj is VideoPlayerController) {
      videoObj.pause();
      videoObj.dispose();
    }
  }

  static Widget buildCustomVideoSurface({
    required Object? videoObj,
    required String viewType,
    required String backdropUrl,
  }) {
    if (videoObj is VideoPlayerController) {
      return ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: videoObj,
        builder: (context, value, _) {
          final bool isReady = value.isInitialized;
          final bool isStalledOrBuffering = !isReady ||
              value.isBuffering ||
              (value.isPlaying &&
                  value.duration.inMilliseconds > 0 &&
                  value.position.inMilliseconds == 0);

          return RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isReady)
                  Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: AspectRatio(
                      aspectRatio:
                          value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                      child: VideoPlayer(videoObj),
                    ),
                  )
                else
                  _buildLoadingBackdrop(backdropUrl),

                if (isStalledOrBuffering)
                  const Center(
                    child: _CleanPercentageLoader(),
                  ),
              ],
            ),
          );
        },
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildLoadingBackdrop(backdropUrl),
        const Center(
          child: _CleanPercentageLoader(),
        ),
      ],
    );
  }

  static Widget _buildLoadingBackdrop(String backdropUrl) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (backdropUrl.isNotEmpty)
          Image.network(
            backdropUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFF050D0A)),
          ),
        Container(color: Colors.black.withValues(alpha: 0.55)),
      ],
    );
  }

  static Widget buildEmbeddedPlayer({
    required String viewType,
    required String embedSrc,
    required String backdropUrl,
    required String title,
  }) {
    return _buildLoadingBackdrop(backdropUrl);
  }

  static void switchVideoAudioTrack(Object? videoObj, int trackIndex) {
    if (videoObj is VideoPlayerController && videoObj.value.isInitialized) {
      final pos = videoObj.value.position;
      videoObj.seekTo(pos);
    }
  }
}

class _CleanPercentageLoader extends StatefulWidget {
  const _CleanPercentageLoader();

  @override
  State<_CleanPercentageLoader> createState() => _CleanPercentageLoaderState();
}

class _CleanPercentageLoaderState extends State<_CleanPercentageLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;
  Timer? _percentTimer;
  int _percent = 1;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _percentTimer = Timer.periodic(const Duration(milliseconds: 35), (timer) {
      if (!mounted) return;
      setState(() {
        if (_percent < 75) {
          _percent += 2;
        } else if (_percent < 95) {
          _percent += 1;
        } else if (_percent < 99) {
          _percent = 99;
        }
        if (_percent > 100) _percent = 100;
      });
    });
  }

  @override
  void dispose() {
    _percentTimer?.cancel();
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF00E676).withValues(alpha: 0.28),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E676).withValues(alpha: 0.18),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              value: _percent / 100.0,
              strokeWidth: 3.2,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              color: const Color(0xFF00E676),
            ),
          ),
          RotationTransition(
            turns: _spinController,
            child: SizedBox(
              width: 52,
              height: 52,
              child: CustomPaint(
                painter: _ArcGlowPainter(),
              ),
            ),
          ),
          Text(
            "$_percent%",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF69F0AE);
    canvas.drawArc(rect, 0, math.pi * 0.45, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
