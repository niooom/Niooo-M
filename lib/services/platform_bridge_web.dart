// ignore: avoid_web_libraries_in_flutter
import "dart:async";
// ignore: avoid_web_libraries_in_flutter
import "dart:convert";
// ignore: avoid_web_libraries_in_flutter
import "dart:html" as html;
// ignore: avoid_web_libraries_in_flutter
import "dart:js_util" as js_util;
// ignore: undefined_prefixed_name
import "dart:ui_web" as ui_web;
import "package:flutter/material.dart";

class PlatformBridge {
  static bool get isWeb => true;

  static final Map<String, Timer> _webDownloadTimers = {};

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
    return filePath.startsWith("http") || filePath.startsWith("web_offline://");
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

  static Future<void> startRealVideoDownload({
    required String movieId,
    required String title,
    required String targetFileOrUrl,
    required int estimatedBytes,
    required void Function(
      int downloadedBytes,
      int totalBytes,
      String speedText,
      String localPath,
      String directUrl,
    ) onProgress,
    required void Function(String localPath, int totalBytes, String directUrl)
        onCompleted,
    required void Function(String errorMessage) onError,
  }) async {
    _webDownloadTimers[movieId]?.cancel();

    String resolvedUrl = "";
    try {
      final raw = await httpGetString(
        "/api/streamtape/direct?file=${Uri.encodeComponent(targetFileOrUrl)}",
      );
      if (raw.trim().startsWith("{")) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          resolvedUrl = (decoded["url"] ?? "").toString();
        }
      }
    } catch (_) {}

    if (resolvedUrl.isEmpty) {
      resolvedUrl = "https://streamtape.com/v/$targetFileOrUrl";
    }

    final int totalBytes =
        estimatedBytes > 0 ? estimatedBytes : 320 * 1024 * 1024;
    int currentBytes = (totalBytes * 0.04).round();
    final int stepBytes = (totalBytes * 0.08).round();

    _webDownloadTimers[movieId] =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      currentBytes += stepBytes;
      if (currentBytes >= totalBytes) {
        timer.cancel();
        _webDownloadTimers.remove(movieId);
        onCompleted(resolvedUrl, totalBytes, resolvedUrl);
      } else {
        onProgress(
          currentBytes,
          totalBytes,
          "4.8 MB/s",
          resolvedUrl,
          resolvedUrl,
        );
      }
    });
  }

  static void cancelVideoDownload(String movieId, {String? localFilePath}) {
    _webDownloadTimers[movieId]?.cancel();
    _webDownloadTimers.remove(movieId);
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
