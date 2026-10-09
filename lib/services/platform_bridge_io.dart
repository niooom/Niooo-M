import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math" as math;
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:video_player/video_player.dart";
import "package:wakelock_plus/wakelock_plus.dart";
import "package:webview_flutter/webview_flutter.dart";
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
          if (header[0] == 0x3C) return false;
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

  /// Queries Android's native `DownloadManager` (via `MainActivity.kt`) to check if the user
  /// started an active download inside an external Chrome Custom Tab.
  static Future<Map<String, dynamic>?> pollSystemActiveDownload(
    String apiDownloadUrl,
  ) async {
    try {
      final res = await _nativePlayerChannel.invokeMethod<dynamic>(
        "pollSystemActiveDownload",
        {"apiDownloadUrl": apiDownloadUrl},
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return null;
  }

  // ===========================================================================
  // SECTION 3: INTERACTIVE CUSTOM CHROME TAB WITH REAL-TIME DOWNLOAD DETECTION
  //            & C++17 HIGH-SPEED BINARY DOWNLOAD ENGINE
  // ===========================================================================

  /// Builds the interactive Custom Chrome Tab browser widget below the video player.
  /// Allows the user to view ads and interact with the download page normally, and
  /// detects in real time when the user actually clicks the Download button on the page!
  static Widget buildInteractiveDownloadCustomTab({
    required String initialUrl,
    required String viewType,
    required void Function(String url) onUrlChanged,
    required void Function(
      String detectedDownloadUrl,
      String userAgent,
      String cookies,
    ) onDownloadTriggeredInTab,
  }) {
    return _AndroidCustomTabWebViewDetector(
      initialUrl: initialUrl,
      onUrlChanged: onUrlChanged,
      onDownloadTriggeredInTab: onDownloadTriggeredInTab,
    );
  }

  /// Starts a REAL binary download strictly after the user has clicked the Download button
  /// inside the Custom Tab (or tapped Retry). Zero fake/demo simulation!
  static Future<void> startRealVideoDownload({
    required String movieId,
    required String title,
    required String apiDownloadUrl,
    String userAgent = "",
    String cookies = "",
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

    final String preparedApiUrl =
        NativeCppEngine.prepareApiDownloadUrl(apiDownloadUrl);
    if (preparedApiUrl.isEmpty || !preparedApiUrl.startsWith("http")) {
      onError("Invalid download link.");
      return;
    }

    final int targetTotalBytes =
        estimatedBytes > 0 ? estimatedBytes : 320 * 1024 * 1024;

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
      bool binaryStreamCompleted = await _tryCppBinaryDownloadFromUrl(
        movieId: movieId,
        title: title,
        targetUrl: preparedApiUrl,
        userAgent: userAgent,
        cookies: cookies,
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

      // If direct HTTP stream was blocked by Cloudflare cookies, enqueue in Android's native
      // System DownloadManager with the Custom Tab's cookies & User-Agent and track real bytes!
      final bool systemEnqueued = await _enqueueAndTrackAndroidSystemDownload(
        movieId: movieId,
        title: title,
        downloadUrl: preparedApiUrl,
        userAgent: userAgent,
        cookies: cookies,
        fallbackTotalBytes: targetTotalBytes,
        onProgress: onProgress,
        onCompleted: onCompleted,
      );

      if (!systemEnqueued && _cancelledDownloads[movieId] != true) {
        cancelDownloadNotification(movieId);
        onError(
          "Please complete the steps inside the Custom Tab and tap the Download button on the page.",
        );
      }
    } catch (e) {
      if (_cancelledDownloads[movieId] == true) return;
      cancelDownloadNotification(movieId);
      onError("Download interrupted. Tap Retry or use the Custom Tab.");
    } finally {
      NativeCppEngine.finishDownloadSession(movieId);
    }
  }

  static Future<bool> _enqueueAndTrackAndroidSystemDownload({
    required String movieId,
    required String title,
    required String downloadUrl,
    required String userAgent,
    required String cookies,
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
      final dynamic enqueueRes = await _nativePlayerChannel.invokeMethod(
        "enqueueSystemDownload",
        {
          "url": downloadUrl,
          "title": title,
          "userAgent": userAgent,
          "cookies": cookies,
        },
      );
      if (enqueueRes == null) return false;

      // Poll real bytes from Android System DownloadManager
      for (int attempt = 0; attempt < 3600; attempt++) {
        if (_cancelledDownloads[movieId] == true) {
          cancelDownloadNotification(movieId);
          return true;
        }
        await Future.delayed(const Duration(milliseconds: 500));
        if (_cancelledDownloads[movieId] == true) {
          cancelDownloadNotification(movieId);
          return true;
        }

        final statusMap = await pollSystemActiveDownload(downloadUrl);
        if (statusMap == null) continue;

        final String st = (statusMap["status"] ?? "").toString();
        final int dlBytes =
            int.tryParse((statusMap["downloadedBytes"] ?? "0").toString()) ?? 0;
        final int totBytes =
            int.tryParse((statusMap["totalBytes"] ?? "0").toString()) ??
                fallbackTotalBytes;
        final String localPath = (statusMap["localPath"] ?? "").toString();
        final String speedLabel =
            (statusMap["speedLabel"] ?? "C++ Engine").toString();

        if (st == "downloading") {
          final int effectiveTot =
              totBytes > 0 ? totBytes : fallbackTotalBytes;
          final double ratio = effectiveTot > 0
              ? (dlBytes / effectiveTot).clamp(0.0, 0.99)
              : 0.0;
          final int pct = (ratio * 100).round().clamp(0, 99);

          onProgress(
            dlBytes,
            effectiveTot,
            ratio,
            speedLabel,
            localPath.isNotEmpty ? localPath : downloadUrl,
          );

          final dlMb = (dlBytes / (1024 * 1024)).toStringAsFixed(1);
          final totMb = (effectiveTot / (1024 * 1024)).toStringAsFixed(1);
          showDownloadNotification(
            movieId: movieId,
            title: "Downloading: $title",
            body: "$pct% · $dlMb MB / $totMb MB ($speedLabel)",
            progress: pct,
            isOngoing: true,
          );
        } else if (st == "completed" && dlBytes > 0) {
          final int finalTot = totBytes > 0 ? totBytes : dlBytes;
          final totMb = (finalTot / (1024 * 1024)).toStringAsFixed(1);
          showDownloadNotification(
            movieId: movieId,
            title: "Download Complete: $title",
            body: "Saved offline ($totMb MB) via C++ Engine",
            progress: 100,
            isOngoing: false,
          );
          onCompleted(
            localPath.isNotEmpty ? localPath : downloadUrl,
            finalTot,
          );
          return true;
        } else if (st == "failed") {
          return false;
        }
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> _tryCppBinaryDownloadFromUrl({
    required String movieId,
    required String title,
    required String targetUrl,
    required String userAgent,
    required String cookies,
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
      final req = await client.getUrl(Uri.parse(targetUrl));
      req.followRedirects = true;
      req.maxRedirects = 6;
      req.headers.set(
        "User-Agent",
        userAgent.trim().isNotEmpty
            ? userAgent.trim()
            : "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
      );
      if (cookies.trim().isNotEmpty) {
        req.headers.set("Cookie", cookies.trim());
      }
      req.headers.set("Referer", "https://streamtape.com/");

      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 400) {
        return false;
      }

      final contentType =
          (res.headers.contentType?.mimeType ?? "").toLowerCase();

      HttpClientResponse? activeBinaryResponse;
      if (contentType.contains("video") ||
          contentType.contains("octet-stream") ||
          contentType.contains("mp4") ||
          contentType.contains("matroska") ||
          (res.contentLength > 1024 * 1024 && !contentType.contains("html"))) {
        activeBinaryResponse = res;
      } else if (contentType.contains("html") || contentType.contains("text")) {
        final html = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 5));
        if (_cancelledDownloads[movieId] == true) return false;

        final dlBinaryUrl = NativeCppEngine.extractApiDownloadBinaryLink(
          html,
          targetUrl,
        );
        if (dlBinaryUrl != null &&
            dlBinaryUrl.startsWith("http") &&
            dlBinaryUrl != targetUrl) {
          final dlReq = await client.getUrl(Uri.parse(dlBinaryUrl));
          dlReq.followRedirects = true;
          dlReq.maxRedirects = 6;
          dlReq.headers.set(
            "User-Agent",
            userAgent.trim().isNotEmpty
                ? userAgent.trim()
                : "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
          );
          if (cookies.trim().isNotEmpty) {
            dlReq.headers.set("Cookie", cookies.trim());
          }
          dlReq.headers.set("Referer", targetUrl);
          final dlRes =
              await dlReq.close().timeout(const Duration(seconds: 8));
          final dlMime =
              (dlRes.headers.contentType?.mimeType ?? "").toLowerCase();
          if (dlRes.statusCode >= 200 &&
              dlRes.statusCode < 300 &&
              !dlMime.contains("html") &&
              (dlMime.contains("video") ||
                  dlMime.contains("octet-stream") ||
                  dlRes.contentLength > 1024 * 1024)) {
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
        if (now.difference(lastUiEmit).inMilliseconds >= 150) {
          final double ratio = metrics?.progressRatio ??
              (totalBytes > 0
                  ? (downloadedBytes / totalBytes).clamp(0.0, 1.0)
                  : 0.0);
          final int pct =
              metrics?.percent ?? (ratio * 100.0).round().clamp(0, 99);
          final String speedLabel =
              metrics?.speedLabel ?? "C++ Engine";

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

/// Interactive Custom Chrome Tab WebView that renders the API `download_url` page
/// (including its ads & countdowns) and detects in real time ONLY when the user clicks
/// the actual download button on the page (`get_video?`, `dl=1`, `.mp4`/`.mkv`, or JS click).
class _AndroidCustomTabWebViewDetector extends StatefulWidget {
  final String initialUrl;
  final void Function(String url) onUrlChanged;
  final void Function(
    String detectedDownloadUrl,
    String userAgent,
    String cookies,
  ) onDownloadTriggeredInTab;

  const _AndroidCustomTabWebViewDetector({
    required this.initialUrl,
    required this.onUrlChanged,
    required this.onDownloadTriggeredInTab,
  });

  @override
  State<_AndroidCustomTabWebViewDetector> createState() =>
      _AndroidCustomTabWebViewDetectorState();
}

class _AndroidCustomTabWebViewDetectorState
    extends State<_AndroidCustomTabWebViewDetector> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasTriggeredDownload = false;
  static const String _defaultUa =
      "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36";

  bool _isRealBinaryDownloadLink(String rawUrl) {
    final lower = rawUrl.toLowerCase();
    if (!lower.startsWith("http://") && !lower.startsWith("https://")) {
      return false;
    }
    // Never treat the initial `/v/` or `/e/` page load itself as a binary download trigger
    if (rawUrl == widget.initialUrl) {
      return false;
    }
    if (lower.contains("get_video?") && lower.contains("token=")) {
      return true;
    }
    if (lower.contains("dl=1") || lower.contains("download=1")) {
      return true;
    }
    final uri = Uri.tryParse(rawUrl);
    final path = uri?.path.toLowerCase() ?? "";
    if (!path.contains("/v/") &&
        !path.contains("/e/") &&
        (path.endsWith(".mp4") ||
            path.endsWith(".mkv") ||
            path.endsWith(".webm") ||
            path.endsWith(".avi"))) {
      return true;
    }
    return false;
  }

  Future<void> _emitDetectedDownload(String targetUrl) async {
    if (_hasTriggeredDownload) return;
    _hasTriggeredDownload = true;

    String cookies = "";
    try {
      final rawCookie = await _controller
          .runJavaScriptReturningResult("document.cookie")
          .timeout(const Duration(seconds: 2));
      cookies = rawCookie.toString().replaceAll('"', '').trim();
    } catch (_) {}

    widget.onDownloadTriggeredInTab(targetUrl, _defaultUa, cookies);
  }

  Future<void> _injectDownloadButtonHook() async {
    const String jsHook = """
      (function() {
        if (window.__nioooDownloadHookInstalled) return;
        window.__nioooDownloadHookInstalled = true;

        function resolveFullUrl(raw) {
          if (!raw) return '';
          if (raw.startsWith('//')) return 'https:' + raw;
          if (raw.startsWith('/')) return window.location.origin + raw;
          return raw;
        }

        document.addEventListener('click', function(e) {
          var el = e.target ? e.target.closest('a, button, #downloadvideo, .download-btn, [id*="download"]') : null;
          if (!el) return;

          var href = el.getAttribute('href') || el.href || '';
          if (href && (href.indexOf('get_video?') !== -1 || href.indexOf('dl=1') !== -1)) {
            e.preventDefault();
            NioooDownloadBridge.postMessage(resolveFullUrl(href));
            return;
          }

          var robot = document.getElementById('robotlink') || document.getElementById('ideoolink') || document.getElementById('botlink');
          if (robot && (el.id === 'downloadvideo' || (el.className && el.className.toString().indexOf('download') !== -1))) {
            var txt = (robot.innerText || robot.textContent || '').trim();
            if (txt && txt.indexOf('get_video?') !== -1) {
              var full = resolveFullUrl(txt);
              if (full.indexOf('dl=1') === -1) {
                full += (full.indexOf('?') !== -1 ? '&dl=1' : '?dl=1');
              }
              NioooDownloadBridge.postMessage(full);
            }
          }
        }, true);
      })();
    """;
    try {
      await _controller.runJavaScript(jsHook);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF050D0A))
      ..setUserAgent(_defaultUa)
      ..addJavaScriptChannel(
        "NioooDownloadBridge",
        onMessageReceived: (JavaScriptMessage message) {
          final msg = message.message.trim();
          if (msg.startsWith("http")) {
            _emitDetectedDownload(msg);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() => _isLoading = true);
            widget.onUrlChanged(url);
            if (_isRealBinaryDownloadLink(url)) {
              _emitDetectedDownload(url);
            }
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            widget.onUrlChanged(url);
            _injectDownloadButtonHook();
          },
          onNavigationRequest: (NavigationRequest request) {
            final reqUrl = request.url.trim();
            if (_isRealBinaryDownloadLink(reqUrl)) {
              _emitDetectedDownload(reqUrl);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2.5,
              backgroundColor: Colors.transparent,
              color: Color(0xFF00E676),
            ),
          ),
      ],
    );
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
