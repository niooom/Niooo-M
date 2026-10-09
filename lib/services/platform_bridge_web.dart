// ignore: avoid_web_libraries_in_flutter
import "dart:async";
// ignore: avoid_web_libraries_in_flutter
import "dart:html" as html;
// ignore: avoid_web_libraries_in_flutter
import "dart:js_util" as js_util;
// ignore: undefined_prefixed_name
import "dart:ui_web" as ui_web;
import "package:flutter/material.dart";

class PlatformBridge {
  static bool get isWeb => true;

  static final Map<String, html.HttpRequest> _activeWebRequests = {};

  static Future<String> httpGetString(
    String url, {
    Map<String, String>? headers,
  }) async {
    if (headers != null && headers.isNotEmpty) {
      final req = await html.HttpRequest.request(
        url,
        method: "GET",
        requestHeaders: headers,
      );
      if (req.status != null && req.status! >= 200 && req.status! < 300) {
        return req.responseText ?? "";
      }
      throw Exception("HTTP ${req.status} for $url");
    }
    return await html.HttpRequest.getString(url);
  }

  static String? getLocalStorage(String key) {
    try {
      return html.window.localStorage[key];
    } catch (_) {
      return null;
    }
  }

  static void setLocalStorage(String key, String? value) {
    try {
      if (value == null) {
        html.window.localStorage.remove(key);
      } else {
        html.window.localStorage[key] = value;
      }
    } catch (_) {}
  }

  static bool localFileExists(String filePath) {
    return false;
  }

  static void copyToClipboard(String text) {
    try {
      html.window.navigator.clipboard?.writeText(text);
    } catch (_) {}
  }

  static void registerIframeFactory(String viewType, String src) {
    final iframe = html.IFrameElement()
      ..src = src
      ..style.border = "none"
      ..style.width = "100%"
      ..style.height = "100%"
      ..style.backgroundColor = "#000000"
      ..setAttribute("loading", "eager")
      ..allowFullscreen = true
      ..allow =
          "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; fullscreen";

    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId) => iframe,
    );
  }

  static Object? registerVideoFactory({
    required String viewType,
    required String src,
    required String posterUrl,
    double initialSeekSeconds = 0.0,
    required void Function(double duration) onDurationLoaded,
    required void Function() onPlay,
    required void Function() onPause,
  }) {
    final video = html.VideoElement()
      ..src = src
      ..poster = posterUrl
      ..preload = "auto"
      ..autoplay = false
      ..controls = false
      ..loop = false
      ..style.width = "100%"
      ..style.height = "100%"
      ..style.objectFit = "contain"
      ..style.backgroundColor = "#000000"
      ..setAttribute("playsinline", "true")
      ..setAttribute("webkit-playsinline", "true");

    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId) => video,
    );

    video.onLoadedMetadata.listen((_) {
      final dur = video.duration;
      if (!dur.isNaN && !dur.isInfinite && dur > 0) {
        onDurationLoaded(dur.toDouble());
      }
      if (initialSeekSeconds > 1.0) {
        try {
          video.currentTime = initialSeekSeconds;
        } catch (_) {}
      }
    });

    video.onPlay.listen((_) => onPlay());
    video.onPause.listen((_) => onPause());

    return video;
  }

  static void showDownloadNotification({
    required String movieId,
    required String title,
    required String body,
    required int progress,
    required bool isOngoing,
  }) {}

  static void cancelDownloadNotification(String movieId) {}

  static Future<bool> openPartialChromeCustomTab({
    required String url,
    required int heightPx,
  }) async {
    return false;
  }

  static Future<Map<String, dynamic>?> pollSystemActiveDownload(
    String apiDownloadUrl,
  ) async {
    return null;
  }

  /// Strictly runs only when a real download is triggered inside the Custom Tab.
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
    _activeWebRequests[movieId]?.abort();
    _activeWebRequests.remove(movieId);

    final cleanApiUrl = apiDownloadUrl.trim();
    if (cleanApiUrl.isEmpty) {
      onError("Missing API download link.");
      return;
    }

    try {
      final req = html.HttpRequest();
      _activeWebRequests[movieId] = req;
      req.open("GET", cleanApiUrl, async: true);
      req.responseType = "blob";

      final int fallbackTotal =
          estimatedBytes > 0 ? estimatedBytes : 320 * 1024 * 1024;
      final DateTime startTime = DateTime.now();

      req.onProgress.listen((html.ProgressEvent event) {
        final int loaded = event.loaded ?? 0;
        final int total =
            (event.total != null && event.total! > 0) ? event.total! : fallbackTotal;
        if (loaded > 0 && total > 0) {
          final double ratio = (loaded / total).clamp(0.0, 0.99);
          final double elapsedSec =
              (DateTime.now().difference(startTime).inMilliseconds / 1000.0)
                  .clamp(0.1, 86400.0);
          final double mbps = (loaded / (1024 * 1024)) / elapsedSec;
          onProgress(
            loaded,
            total,
            ratio,
            "${mbps.toStringAsFixed(1)} MB/s · C++ Engine",
            cleanApiUrl,
          );
        }
      });

      final completer = Completer<void>();
      req.onLoad.listen((_) {
        _activeWebRequests.remove(movieId);
        if (req.status != null && req.status! >= 200 && req.status! < 300) {
          onCompleted(cleanApiUrl, fallbackTotal);
        } else {
          onError("Please use the Custom Tab page to complete the download.");
        }
        if (!completer.isCompleted) completer.complete();
      });

      req.onError.listen((_) {
        _activeWebRequests.remove(movieId);
        onError("Please use the Custom Tab page to complete the download.");
        if (!completer.isCompleted) completer.complete();
      });

      req.send();
      await completer.future;
    } catch (_) {
      onError("Please use the Custom Tab page to complete the download.");
    }
  }

  static void cancelVideoDownload(String movieId, {String? localFilePath}) {
    _activeWebRequests[movieId]?.abort();
    _activeWebRequests.remove(movieId);
  }

  static void playVideo(Object? videoObj, void Function() onMutedFallback) {
    if (videoObj is html.VideoElement) {
      videoObj.play().catchError((_) async {
        videoObj.muted = true;
        onMutedFallback();
        try {
          await videoObj.play();
        } catch (_) {}
      });
    }
  }

  static void pauseVideo(Object? videoObj) {
    if (videoObj is html.VideoElement) {
      videoObj.pause();
    }
  }

  static bool isVideoPaused(Object? videoObj) {
    if (videoObj is html.VideoElement) {
      return videoObj.paused;
    }
    return true;
  }

  static double getVideoCurrentTime(Object? videoObj) {
    if (videoObj is html.VideoElement) {
      return videoObj.currentTime.toDouble();
    }
    return 0.0;
  }

  static double getVideoDuration(Object? videoObj) {
    if (videoObj is html.VideoElement) {
      return videoObj.duration.toDouble();
    }
    return 0.0;
  }

  static void setVideoCurrentTime(Object? videoObj, double seconds) {
    if (videoObj is html.VideoElement) {
      videoObj.currentTime = seconds;
    }
  }

  static bool toggleVideoMute(Object? videoObj) {
    if (videoObj is html.VideoElement) {
      videoObj.muted = !videoObj.muted;
      return videoObj.muted;
    }
    return false;
  }

  static Object? _wakeLockSentinel;

  static void setScreenWakelock(bool enable) {
    try {
      final nav = html.window.navigator;
      final wakeLock = js_util.getProperty<Object?>(nav, "wakeLock");
      if (wakeLock != null) {
        if (enable) {
          js_util
              .promiseToFuture<Object?>(
                js_util.callMethod<Object>(wakeLock, "request", ["screen"]),
              )
              .then((sentinel) => _wakeLockSentinel = sentinel)
              .catchError((_) => null);
        } else if (_wakeLockSentinel != null) {
          js_util.callMethod<Object?>(_wakeLockSentinel!, "release", []);
          _wakeLockSentinel = null;
        }
      }
    } catch (_) {}
  }

  static void enterNativeFullscreen() {
    setScreenWakelock(true);
    try {
      html.document.documentElement?.requestFullscreen();
    } catch (_) {}
  }

  static void exitNativeFullscreen() {
    try {
      if (html.document.fullscreenElement != null) {
        html.document.exitFullscreen();
      }
    } catch (_) {}
  }

  static void requestVideoFullscreen(Object? videoObj) {
    if (videoObj is html.VideoElement) {
      try {
        videoObj.requestFullscreen();
      } catch (_) {}
    } else {
      enterNativeFullscreen();
    }
  }

  static void disposeVideo(Object? videoObj) {
    setScreenWakelock(false);
    exitNativeFullscreen();
    if (videoObj is html.VideoElement) {
      try {
        videoObj.pause();
        videoObj.removeAttribute("src");
        videoObj.load();
      } catch (_) {}
    }
  }

  static Widget buildCustomVideoSurface({
    required Object? videoObj,
    required String viewType,
    required String backdropUrl,
  }) {
    return HtmlElementView(viewType: viewType);
  }

  static Widget buildEmbeddedPlayer({
    required String viewType,
    required String embedSrc,
    required String backdropUrl,
    required String title,
  }) {
    return HtmlElementView(viewType: viewType);
  }

  static void switchVideoAudioTrack(Object? videoObj, int trackIndex) {
    if (videoObj is html.VideoElement) {
      try {
        final audioTracks =
            js_util.getProperty<Object?>(videoObj, "audioTracks");
        if (audioTracks != null) {
          final length =
              js_util.getProperty<int?>(audioTracks, "length") ?? 0;
          for (int i = 0; i < length; i++) {
            final track = js_util.callMethod<Object?>(
              audioTracks,
              "item",
              [i],
            );
            if (track != null) {
              js_util.setProperty(track, "enabled", i == trackIndex);
            }
          }
        }
      } catch (_) {}
    }
  }
}
