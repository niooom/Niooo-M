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

  /// Extracts the direct MP4 video stream link directly on the user's Android device
  /// using the Native C++17 Zero-Copy Engine so the Streamtape IP token 100% matches
  /// the user's phone IP and never gets blocked (403 Forbidden)!
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

    // 1. Primary: Extract directly from user's phone IP via `/e/{id}` + C++17 Engine
    final fromEmbed = await _extractFromDeviceEndpoint(
      cleanId,
      "https://streamtape.com/e/${Uri.encodeComponent(cleanId)}",
    );
    if (fromEmbed != null && fromEmbed.startsWith("http")) {
      _cacheDirectUrl(cleanId, fromEmbed);
      return fromEmbed;
    }

    // 2. Secondary: Try `/v/{id}` directly from user's phone IP + C++17 Engine
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
      req.headers.set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
      req.headers.set("Referer", "https://streamtape.com/");
      final res = await req.close();
      if (res.statusCode != 200) return null;

      final html = await res.transform(utf8.decoder).join();

      // 1. Native C++17 Zero-Copy Extractor (`libniooom_native_engine.so`)
      String? extractedGetVideoUrl =
          NativeCppEngine.extractStreamtapeUrlWithCpp(html);

      // 2. Fallback Dart Regex supporting all robotlink/botlink/ideoolink/norobotlink split patterns
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

                // Show clean 1%–100% circular loader whenever initializing or buffering due to slow network
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

/// Compact, text-free circular loading animation that counts smoothly from 1% to 100%
/// inside the video player while loading or buffering.
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
