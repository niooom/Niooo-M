import "dart:async";
import "dart:convert";
import "dart:io";
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

  static String _extractStreamtapeFileId(String rawUrlOrId) {
    final trimmed = rawUrlOrId.trim();
    if (trimmed.isEmpty) return "";

    // 1. Try Ultra-Fast Native C++17 File ID Extractor first
    final cppId = NativeCppEngine.extractFileIdWithCpp(trimmed);
    if (cppId != null && cppId.isNotEmpty) {
      return cppId;
    }

    // 2. Fallback Dart Regex
    final match = RegExp(
      r"streamtape\.com/(?:e|v)/([a-zA-Z0-9_-]+)",
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

  /// Extracts the direct MP4 video stream link in the background on Android
  /// using the Native C++17 Zero-Copy Engine + parallel race fallback.
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

    final future = _performFastExtraction(cleanId);
    _inFlightExtractions[cleanId] = future;
    try {
      return await future;
    } finally {
      _inFlightExtractions.remove(cleanId);
    }
  }

  static Future<String?> _performFastExtraction(String cleanId) async {
    NativeCppEngine.boostPlaybackPriority(highPriority: true);

    final completer = Completer<String?>();
    int remaining = 2;

    void handleCandidate(String? candidate) {
      if (candidate != null &&
          candidate.startsWith("http") &&
          !candidate.contains("/e/")) {
        _cacheDirectUrl(cleanId, candidate);
        if (!completer.isCompleted) {
          completer.complete(candidate);
        }
        return;
      }
      remaining--;
      if (remaining <= 0 && !completer.isCompleted) {
        completer.complete(null);
      }
    }

    // Racer 1: Direct Streamtape HTML fetch + Native C++17 (-O3) zero-copy token extraction
    _extractViaNativeCppAndStreamtape(cleanId)
        .then(handleCandidate)
        .catchError((_) => handleCandidate(null));

    // Racer 2: Cloud Server Direct Endpoint (runs in parallel so whichever finishes first wins!)
    _extractViaCloudServer(cleanId)
        .then(handleCandidate)
        .catchError((_) => handleCandidate(null));

    return completer.future;
  }

  static Future<String?> _extractViaNativeCppAndStreamtape(
    String cleanId,
  ) async {
    try {
      final client = _getFastHttpClient();
      final req = await client.getUrl(
        Uri.parse("https://streamtape.com/e/${Uri.encodeComponent(cleanId)}"),
      );
      final res = await req.close();
      if (res.statusCode != 200) return null;

      final html = await res.transform(utf8.decoder).join();

      // 1. Primary: Native C++17 Zero-Copy Extractor (`libniooom_native_engine.so`)
      String? extractedGetVideoUrl =
          NativeCppEngine.extractStreamtapeUrlWithCpp(html);

      // 2. Fallback: Dart Regex if Native C++ library did not match a new variant
      if (extractedGetVideoUrl == null || extractedGetVideoUrl.isEmpty) {
        final regex = RegExp(
          r"""getElementById\(['"]robotlink['"]\)\.innerHTML\s*=\s*['"]([^'"]+)['"]\s*\+\s*(?:''\s*\+\s*)?\(['"]([^'"]+)['"]\)((?:\.substring\(\d+\))+)""",
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
          if (combined.startsWith("//")) {
            extractedGetVideoUrl = "https:$combined&stream=1";
          } else if (combined.startsWith("/")) {
            extractedGetVideoUrl = "https:/$combined&stream=1";
          } else {
            extractedGetVideoUrl = "https://$combined&stream=1";
          }
        }
      }

      if (extractedGetVideoUrl != null && extractedGetVideoUrl.isNotEmpty) {
        try {
          final redirectReq =
              await client.getUrl(Uri.parse(extractedGetVideoUrl));
          redirectReq.followRedirects = false;
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

  static Future<String?> _extractViaCloudServer(String cleanId) async {
    try {
      final client = _getFastHttpClient();
      final req = await client.getUrl(
        Uri.parse(
          "$cloudServerBaseUrl/api/streamtape/direct?file=${Uri.encodeComponent(cleanId)}",
        ),
      );
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        if (body.trim().startsWith("{")) {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            final url = (decoded["url"] ?? "").toString();
            if (url.startsWith("http") && !url.contains("/e/")) {
              return url;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _diskCacheLoaded = false;

  static void _ensureDiskCacheLoaded() {
    if (_diskCacheLoaded) return;
    _diskCacheLoaded = true;
    try {
      final cacheFile =
          File("${Directory.systemTemp.path}/niooo_m_public_api_cache_v1.json");
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
      final cacheFile =
          File("${Directory.systemTemp.path}/niooo_m_public_api_cache_v1.json");
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

  static void copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }

  static void registerIframeFactory(String viewType, String src) {}

  static Object? registerVideoFactory({
    required String viewType,
    required String src,
    required String posterUrl,
    required void Function(double duration) onDurationLoaded,
    required void Function() onPlay,
    required void Function() onPause,
  }) {
    NativeCppEngine.boostPlaybackPriority(highPriority: true);
    try {
      _nativePlayerChannel.invokeMethod("boostPlayback");
    } catch (_) {}

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(src),
      httpHeaders: const {
        "User-Agent":
            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
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

    controller.initialize().then((_) {
      final totalSecs =
          controller.value.duration.inMilliseconds.toDouble() / 1000.0;
      if (totalSecs > 0) {
        onDurationLoaded(totalSecs);
      }
      setScreenWakelock(true);
      controller.play();
      onPlay();
    }).catchError((_) {});

    return controller;
  }

  static const MethodChannel _nativePlayerChannel =
      MethodChannel("com.niooo.m/player");

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
          if (!value.isInitialized) {
            return _buildLoadingBackdrop(backdropUrl);
          }
          return RepaintBoundary(
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: AspectRatio(
                aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                child: VideoPlayer(videoObj),
              ),
            ),
          );
        },
      );
    }
    return _buildLoadingBackdrop(backdropUrl);
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
