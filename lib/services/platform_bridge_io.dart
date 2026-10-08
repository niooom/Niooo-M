import "dart:convert";
import "dart:io";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:video_player/video_player.dart";
import "package:wakelock_plus/wakelock_plus.dart";

class PlatformBridge {
  static bool get isWeb => false;

  static const String cloudServerBaseUrl =
      "https://ais-pre-dzew55ccy5nnhlnmouyujf-579860296090.asia-southeast1.run.app";

  static final Map<String, String> _memoryStorage = {};
  static final Map<String, String> _directUrlCache = {};

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
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    try {
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
    } finally {
      client.close();
    }
  }

  static String _extractStreamtapeFileId(String rawUrlOrId) {
    final trimmed = rawUrlOrId.trim();
    if (trimmed.isEmpty) return "";
    final match = RegExp(
      r"streamtape\.com/(?:e|v)/([a-zA-Z0-9_-]+)",
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match != null && match.group(1) != null) {
      return match.group(1)!;
    }
    return trimmed.replaceAll(RegExp(r"[^a-zA-Z0-9_-]"), "");
  }

  /// Extracts the direct MP4 video stream link in the background on Android
  /// from the video's `stream_url` or `download_url` so it plays in the native player!
  static Future<String?> resolveBackgroundDirectMp4Url(
    String fileOrStreamUrl,
  ) async {
    final cleanId = _extractStreamtapeFileId(fileOrStreamUrl);
    if (cleanId.isEmpty) return null;

    if (_directUrlCache.containsKey(cleanId)) {
      return _directUrlCache[cleanId];
    }

    // Method 1: Background extraction from Streamtape embed page (#robotlink token)
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      client.userAgent =
          "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36";
      try {
        final req = await client.getUrl(
          Uri.parse("https://streamtape.com/e/${Uri.encodeComponent(cleanId)}"),
        );
        final res = await req.close();
        if (res.statusCode == 200) {
          final html = await res.transform(utf8.decoder).join();
          final regex = RegExp(
            r"""getElementById\(['"]robotlink['"]\)\.innerHTML\s*=\s*['"]([^'"]+)['"]\s*\+\s*(?:''\s*\+\s*)?\(['"]([^'"]+)['"]\)((?:\.substring\(\d+\))+)""",
          );
          final matches = regex.allMatches(html);
          String? extractedGetVideoUrl;
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

          if (extractedGetVideoUrl != null) {
            try {
              final redirectReq =
                  await client.getUrl(Uri.parse(extractedGetVideoUrl));
              redirectReq.followRedirects = false;
              final redirectRes = await redirectReq.close();
              final location =
                  redirectRes.headers.value(HttpHeaders.locationHeader);
              if (location != null && location.startsWith("http")) {
                _directUrlCache[cleanId] = location;
                return location;
              }
            } catch (_) {}

            _directUrlCache[cleanId] = extractedGetVideoUrl;
            return extractedGetVideoUrl;
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {}

    // Method 2: Ask cloud server's background extractor (/api/streamtape/direct)
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      try {
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
                _directUrlCache[cleanId] = url;
                return url;
              }
            }
          }
        }
      } finally {
        client.close();
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
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(src),
      httpHeaders: const {
        "User-Agent":
            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
      },
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
          return Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: AspectRatio(
              aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
              child: VideoPlayer(videoObj),
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
