import "dart:async";
import "dart:convert";
import "package:flutter/foundation.dart";
import "platform_bridge.dart";

class WatchHistoryRecord {
  final String movieId;
  final String title;
  final String posterUrl;
  final String backdropUrl;
  final String qualityBadge;
  final String language;
  final double positionSeconds;
  final double durationSeconds;
  final int updatedAtMs;

  const WatchHistoryRecord({
    required this.movieId,
    required this.title,
    required this.posterUrl,
    required this.backdropUrl,
    required this.qualityBadge,
    required this.language,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAtMs,
  });

  double get progressRatio {
    if (durationSeconds <= 0) return 0.0;
    return (positionSeconds / durationSeconds).clamp(0.0, 1.0);
  }

  String get formattedPosition => _formatTime(positionSeconds);
  String get formattedDuration => _formatTime(durationSeconds);
  String get remainingTimeLabel {
    final rem = (durationSeconds - positionSeconds).clamp(0.0, 86400.0);
    if (rem <= 5) return "Completed";
    return "${_formatTime(rem)} left";
  }

  static String _formatTime(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds <= 0) return "00:00";
    final int total = seconds.round();
    final int hrs = total ~/ 3600;
    final int mins = (total % 3600) ~/ 60;
    final int secs = total % 60;
    if (hrs > 0) {
      return "${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
    }
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  Map<String, dynamic> toJson() => {
        "movieId": movieId,
        "title": title,
        "posterUrl": posterUrl,
        "backdropUrl": backdropUrl,
        "qualityBadge": qualityBadge,
        "language": language,
        "positionSeconds": positionSeconds,
        "durationSeconds": durationSeconds,
        "updatedAtMs": updatedAtMs,
      };

  factory WatchHistoryRecord.fromJson(Map<String, dynamic> json) {
    return WatchHistoryRecord(
      movieId: (json["movieId"] ?? "").toString(),
      title: (json["title"] ?? "Untitled").toString(),
      posterUrl: (json["posterUrl"] ?? "").toString(),
      backdropUrl: (json["backdropUrl"] ?? "").toString(),
      qualityBadge: (json["qualityBadge"] ?? "HD").toString(),
      language: (json["language"] ?? "Hindi").toString(),
      positionSeconds:
          double.tryParse((json["positionSeconds"] ?? "0").toString()) ?? 0.0,
      durationSeconds:
          double.tryParse((json["durationSeconds"] ?? "0").toString()) ?? 0.0,
      updatedAtMs:
          int.tryParse((json["updatedAtMs"] ?? "0").toString()) ?? 0,
    );
  }
}

class DownloadTaskItem {
  final String movieId;
  final String title;
  final String posterUrl;
  final String backdropUrl;
  final String qualityBadge;
  final String language;
  /// Strictly holds the `download_url` coming from the Niooo M API Key
  /// (never the video player's extracted direct stream link).
  final String apiDownloadUrl;
  final String localFilePath;
  final String status; // "downloading" | "completed" | "paused" | "failed"
  final int downloadedBytes;
  final int totalBytes;
  final double progress;
  final String speedLabel;
  final String errorMessage;
  final int updatedAtMs;

  const DownloadTaskItem({
    required this.movieId,
    required this.title,
    required this.posterUrl,
    required this.backdropUrl,
    required this.qualityBadge,
    required this.language,
    required this.apiDownloadUrl,
    required this.localFilePath,
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.progress,
    this.speedLabel = "",
    this.errorMessage = "",
    required this.updatedAtMs,
  });

  /// Backward-compatible getter for UI components referencing `downloadPageUrl`
  String get downloadPageUrl => apiDownloadUrl;

  bool get isCompleted => status == "completed";
  bool get isDownloading => status == "downloading";

  String get formattedSizeProgress {
    final dlMb = (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
    if (totalBytes > 0) {
      final totMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
      return "$dlMb MB / $totMb MB";
    }
    return "$dlMb MB";
  }

  DownloadTaskItem copyWith({
    String? apiDownloadUrl,
    String? localFilePath,
    String? status,
    int? downloadedBytes,
    int? totalBytes,
    double? progress,
    String? speedLabel,
    String? errorMessage,
    int? updatedAtMs,
  }) {
    return DownloadTaskItem(
      movieId: movieId,
      title: title,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      qualityBadge: qualityBadge,
      language: language,
      apiDownloadUrl: apiDownloadUrl ?? this.apiDownloadUrl,
      localFilePath: localFilePath ?? this.localFilePath,
      status: status ?? this.status,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      progress: progress ?? this.progress,
      speedLabel: speedLabel ?? this.speedLabel,
      errorMessage: errorMessage ?? this.errorMessage,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        "movieId": movieId,
        "title": title,
        "posterUrl": posterUrl,
        "backdropUrl": backdropUrl,
        "qualityBadge": qualityBadge,
        "language": language,
        "apiDownloadUrl": apiDownloadUrl,
        "downloadPageUrl": apiDownloadUrl,
        "localFilePath": localFilePath,
        "status": status,
        "downloadedBytes": downloadedBytes,
        "totalBytes": totalBytes,
        "progress": progress,
        "speedLabel": speedLabel,
        "errorMessage": errorMessage,
        "updatedAtMs": updatedAtMs,
      };

  factory DownloadTaskItem.fromJson(Map<String, dynamic> json) {
    final String rawApiDl =
        (json["apiDownloadUrl"] ?? json["downloadPageUrl"] ?? "").toString();
    final String rawStatus = (json["status"] ?? "completed").toString();
    final String normalizedStatus =
        rawStatus == "extracting" ? "downloading" : rawStatus;

    return DownloadTaskItem(
      movieId: (json["movieId"] ?? "").toString(),
      title: (json["title"] ?? "Untitled").toString(),
      posterUrl: (json["posterUrl"] ?? "").toString(),
      backdropUrl: (json["backdropUrl"] ?? "").toString(),
      qualityBadge: (json["qualityBadge"] ?? "HD").toString(),
      language: (json["language"] ?? "Hindi").toString(),
      apiDownloadUrl: rawApiDl,
      localFilePath: (json["localFilePath"] ?? "").toString(),
      status: normalizedStatus,
      downloadedBytes:
          int.tryParse((json["downloadedBytes"] ?? "0").toString()) ?? 0,
      totalBytes: int.tryParse((json["totalBytes"] ?? "0").toString()) ?? 0,
      progress: double.tryParse((json["progress"] ?? "0").toString()) ?? 0.0,
      speedLabel: (json["speedLabel"] ?? "").toString(),
      errorMessage: (json["errorMessage"] ?? "").toString(),
      updatedAtMs:
          int.tryParse((json["updatedAtMs"] ?? "0").toString()) ?? 0,
    );
  }
}

class _PendingCustomTabDownloadContext {
  final String movieId;
  final String title;
  final String posterUrl;
  final String backdropUrl;
  final String qualityBadge;
  final String language;
  final String apiDownloadUrl;
  final int estimatedSizeBytes;

  const _PendingCustomTabDownloadContext({
    required this.movieId,
    required this.title,
    required this.posterUrl,
    required this.backdropUrl,
    required this.qualityBadge,
    required this.language,
    required this.apiDownloadUrl,
    required this.estimatedSizeBytes,
  });
}

class WatchHistoryDownloadService extends ChangeNotifier {
  static final WatchHistoryDownloadService instance =
      WatchHistoryDownloadService._();

  WatchHistoryDownloadService._() {
    _loadFromStorage();
  }

  static const String _historyStorageKey = "niooo_m_watch_history_v2";
  static const String _downloadsStorageKey = "niooo_m_offline_downloads_v3";

  final Map<String, WatchHistoryRecord> _historyById = {};
  final Map<String, DownloadTaskItem> _downloadsById = {};
  final Map<String, _PendingCustomTabDownloadContext> _pendingCustomTabById = {};
  String? _activeCustomTabMovieId;
  Timer? _systemDownloadPollTimer;
  DateTime? _lastDiskSaveTime;

  List<WatchHistoryRecord> get historyList {
    final list = _historyById.values.toList();
    list.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return list;
  }

  List<DownloadTaskItem> get downloadList {
    final list = _downloadsById.values.toList();
    list.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return list;
  }

  int get activeDownloadsCount =>
      _downloadsById.values.where((d) => d.isDownloading).length;

  WatchHistoryRecord? getHistoryForMovie(String movieId) =>
      _historyById[movieId];

  double getSavedPositionSeconds(String movieId) {
    final rec = _historyById[movieId];
    if (rec == null) return 0.0;
    if (rec.durationSeconds > 60 &&
        rec.positionSeconds >= rec.durationSeconds - 8) {
      return 0.0;
    }
    return rec.positionSeconds;
  }

  DownloadTaskItem? getDownloadTask(String movieId) => _downloadsById[movieId];

  String? getCompletedOfflineFilePath(String movieId) {
    final task = _downloadsById[movieId];
    if (task != null &&
        task.status == "completed" &&
        task.localFilePath.isNotEmpty) {
      if (PlatformBridge.localFileExists(task.localFilePath)) {
        return task.localFilePath;
      }
    }
    return null;
  }

  void _loadFromStorage() {
    try {
      final rawHist = PlatformBridge.getLocalStorage(_historyStorageKey);
      if (rawHist != null && rawHist.trim().startsWith("[")) {
        final decoded = jsonDecode(rawHist);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final rec =
                  WatchHistoryRecord.fromJson(Map<String, dynamic>.from(item));
              if (rec.movieId.isNotEmpty) {
                _historyById[rec.movieId] = rec;
              }
            }
          }
        }
      }
    } catch (_) {}

    try {
      final rawDl = PlatformBridge.getLocalStorage(_downloadsStorageKey);
      if (rawDl != null && rawDl.trim().startsWith("[")) {
        final decoded = jsonDecode(rawDl);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final task =
                  DownloadTaskItem.fromJson(Map<String, dynamic>.from(item));
              if (task.movieId.isNotEmpty) {
                // Only keep real completed or explicitly paused tasks on disk load
                final normalized = task.isDownloading
                    ? task.copyWith(status: "paused", speedLabel: "Tap to resume")
                    : task;
                _downloadsById[task.movieId] = normalized;
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  void _saveHistoryToStorage({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        _lastDiskSaveTime != null &&
        now.difference(_lastDiskSaveTime!).inSeconds < 3) {
      return;
    }
    _lastDiskSaveTime = now;
    try {
      final encoded =
          jsonEncode(historyList.map((e) => e.toJson()).toList());
      PlatformBridge.setLocalStorage(_historyStorageKey, encoded);
    } catch (_) {}
  }

  void _saveDownloadsToStorage() {
    try {
      final encoded =
          jsonEncode(downloadList.map((e) => e.toJson()).toList());
      PlatformBridge.setLocalStorage(_downloadsStorageKey, encoded);
    } catch (_) {}
  }

  /// Records exact playback timestamp in seconds so re-opening the movie resumes from the exact second
  void recordWatchPosition({
    required String movieId,
    required String title,
    required String posterUrl,
    required String backdropUrl,
    required String qualityBadge,
    required String language,
    required double positionSeconds,
    required double durationSeconds,
    bool forceCommit = false,
  }) {
    if (movieId.isEmpty || positionSeconds.isNaN || positionSeconds < 1.0) {
      return;
    }
    final safeDuration =
        (durationSeconds.isNaN || durationSeconds <= 0) ? 100.0 : durationSeconds;

    final record = WatchHistoryRecord(
      movieId: movieId,
      title: title,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      qualityBadge: qualityBadge,
      language: language,
      positionSeconds: positionSeconds,
      durationSeconds: safeDuration,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    _historyById[movieId] = record;
    _saveHistoryToStorage(force: forceCommit);
    notifyListeners();
  }

  void removeHistoryItem(String movieId) {
    _historyById.remove(movieId);
    _saveHistoryToStorage(force: true);
    notifyListeners();
  }

  void clearAllWatchHistory() {
    _historyById.clear();
    _saveHistoryToStorage(force: true);
    notifyListeners();
  }

  /// Registers the movie metadata when the user opens the Custom Chrome Tab for downloading,
  /// WITHOUT starting any download or showing any fake/demo progress bar.
  /// Also starts monitoring Android System `DownloadManager` in case the user starts a download
  /// in the external Chrome Custom Tab.
  void preparePendingCustomTabDownload({
    required String movieId,
    required String title,
    required String posterUrl,
    required String backdropUrl,
    required String qualityBadge,
    required String language,
    required String apiDownloadUrl,
    required int estimatedSizeBytes,
  }) {
    _pendingCustomTabById[movieId] = _PendingCustomTabDownloadContext(
      movieId: movieId,
      title: title,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      qualityBadge: qualityBadge,
      language: language,
      apiDownloadUrl: apiDownloadUrl.trim(),
      estimatedSizeBytes: estimatedSizeBytes,
    );
    _activeCustomTabMovieId = movieId;
    _startSystemDownloadManagerMonitor();
  }

  void _startSystemDownloadManagerMonitor() {
    _systemDownloadPollTimer?.cancel();
    _systemDownloadPollTimer = Timer.periodic(
      const Duration(milliseconds: 650),
      (timer) async {
        final activeId = _activeCustomTabMovieId;
        if (activeId == null) {
          timer.cancel();
          return;
        }
        final pending = _pendingCustomTabById[activeId];
        if (pending == null) return;

        final sysDownload =
            await PlatformBridge.pollSystemActiveDownload(pending.apiDownloadUrl);
        if (sysDownload == null) return;

        final String status = (sysDownload["status"] ?? "").toString();
        final int downloadedBytes =
            int.tryParse((sysDownload["downloadedBytes"] ?? "0").toString()) ??
                0;
        final int totalBytes =
            int.tryParse((sysDownload["totalBytes"] ?? "0").toString()) ??
                pending.estimatedSizeBytes;
        final String localPath =
            (sysDownload["localPath"] ?? "").toString();
        final String speedLabel =
            (sysDownload["speedLabel"] ?? "C++ Engine").toString();

        if (status == "downloading" && downloadedBytes > 0) {
          final int effectiveTotal = totalBytes > 0
              ? totalBytes
              : (pending.estimatedSizeBytes > 0
                  ? pending.estimatedSizeBytes
                  : 320 * 1024 * 1024);
          final double ratio =
              (downloadedBytes / effectiveTotal).clamp(0.01, 0.99);
          final int pct = (ratio * 100).round().clamp(1, 99);

          final updated = DownloadTaskItem(
            movieId: pending.movieId,
            title: pending.title,
            posterUrl: pending.posterUrl,
            backdropUrl: pending.backdropUrl,
            qualityBadge: pending.qualityBadge,
            language: pending.language,
            apiDownloadUrl: pending.apiDownloadUrl,
            localFilePath: localPath,
            status: "downloading",
            downloadedBytes: downloadedBytes,
            totalBytes: effectiveTotal,
            progress: ratio,
            speedLabel: speedLabel,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          _downloadsById[pending.movieId] = updated;
          notifyListeners();

          final dlMb = (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
          final totMb = (effectiveTotal / (1024 * 1024)).toStringAsFixed(1);
          PlatformBridge.showDownloadNotification(
            movieId: pending.movieId,
            title: "Downloading: ${pending.title}",
            body: "$pct% · $dlMb MB / $totMb MB ($speedLabel)",
            progress: pct,
            isOngoing: true,
          );
        } else if (status == "completed" && downloadedBytes > 0) {
          final int finalTotal =
              totalBytes > 0 ? totalBytes : downloadedBytes;
          final completed = DownloadTaskItem(
            movieId: pending.movieId,
            title: pending.title,
            posterUrl: pending.posterUrl,
            backdropUrl: pending.backdropUrl,
            qualityBadge: pending.qualityBadge,
            language: pending.language,
            apiDownloadUrl: pending.apiDownloadUrl,
            localFilePath: localPath,
            status: "completed",
            downloadedBytes: finalTotal,
            totalBytes: finalTotal,
            progress: 1.0,
            speedLabel: "Downloaded via C++ Engine",
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          _downloadsById[pending.movieId] = completed;
          _saveDownloadsToStorage();
          notifyListeners();

          final totMb = (finalTotal / (1024 * 1024)).toStringAsFixed(1);
          PlatformBridge.showDownloadNotification(
            movieId: pending.movieId,
            title: "Download Complete: ${pending.title}",
            body: "Saved offline ($totMb MB) · Tap to watch",
            progress: 100,
            isOngoing: false,
          );
          timer.cancel();
        }
      },
    );
  }

  /// Called automatically when the integrated Custom Tab intercepts the real binary download URL
  /// AFTER the user has viewed ads and clicked the Download button inside the Custom Tab!
  Future<void> onCustomTabDownloadDetected({
    required String movieId,
    required String detectedDownloadUrl,
    String userAgent = "",
    String cookies = "",
  }) async {
    final pending = _pendingCustomTabById[movieId];
    final existing = _downloadsById[movieId];
    if (existing != null && existing.isDownloading) {
      return;
    }

    final String title = pending?.title ?? existing?.title ?? "Movie Download";
    final String posterUrl = pending?.posterUrl ?? existing?.posterUrl ?? "";
    final String backdropUrl =
        pending?.backdropUrl ?? existing?.backdropUrl ?? "";
    final String qualityBadge =
        pending?.qualityBadge ?? existing?.qualityBadge ?? "HD";
    final String language =
        pending?.language ?? existing?.language ?? "Hindi";
    final String apiDownloadUrl =
        pending?.apiDownloadUrl ?? existing?.apiDownloadUrl ?? detectedDownloadUrl;
    final int estimatedSizeBytes = pending?.estimatedSizeBytes ??
        existing?.totalBytes ??
        (320 * 1024 * 1024);

    await startMovieDownload(
      movieId: movieId,
      title: title,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      qualityBadge: qualityBadge,
      language: language,
      apiDownloadUrl: apiDownloadUrl,
      detectedDirectDownloadUrl: detectedDownloadUrl,
      userAgent: userAgent,
      cookies: cookies,
      estimatedSizeBytes: estimatedSizeBytes,
    );
  }

  /// Starts or resumes a real-time download ONLY after the download has been triggered
  /// inside the Custom Tab (or when the user taps Retry on an already-triggered download).
  Future<void> startMovieDownload({
    required String movieId,
    required String title,
    required String posterUrl,
    required String backdropUrl,
    required String qualityBadge,
    required String language,
    required String apiDownloadUrl,
    required int estimatedSizeBytes,
    String? detectedDirectDownloadUrl,
    String userAgent = "",
    String cookies = "",
  }) async {
    final existing = _downloadsById[movieId];
    if (existing != null && existing.isDownloading) {
      return;
    }

    final cleanApiDownloadUrl = apiDownloadUrl.trim();
    final effectiveDownloadTarget =
        (detectedDirectDownloadUrl != null &&
                detectedDirectDownloadUrl.trim().isNotEmpty)
            ? detectedDirectDownloadUrl.trim()
            : cleanApiDownloadUrl;

    if (effectiveDownloadTarget.isEmpty) {
      return;
    }

    final int effectiveTotalBytes = estimatedSizeBytes > 0
        ? estimatedSizeBytes
        : ((existing != null && existing.totalBytes > 0)
            ? existing.totalBytes
            : 320 * 1024 * 1024);

    final initialTask = DownloadTaskItem(
      movieId: movieId,
      title: title,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      qualityBadge: qualityBadge,
      language: language,
      apiDownloadUrl: cleanApiDownloadUrl.isNotEmpty
          ? cleanApiDownloadUrl
          : effectiveDownloadTarget,
      localFilePath: existing?.localFilePath ?? "",
      status: "downloading",
      downloadedBytes: 0,
      totalBytes: effectiveTotalBytes,
      progress: 0.0,
      speedLabel: "Connecting C++ Engine...",
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    _downloadsById[movieId] = initialTask;
    _saveDownloadsToStorage();
    notifyListeners();

    PlatformBridge.showDownloadNotification(
      movieId: movieId,
      title: "Downloading: $title",
      body: "Starting real-time download from Custom Tab...",
      progress: 0,
      isOngoing: true,
    );

    await PlatformBridge.startRealVideoDownload(
      movieId: movieId,
      title: title,
      apiDownloadUrl: effectiveDownloadTarget,
      userAgent: userAgent,
      cookies: cookies,
      estimatedBytes: effectiveTotalBytes,
      onProgress: (downloadedBytes, totalBytes, progressRatio, speedText, localPath) {
        final double pct = progressRatio.clamp(0.0, 1.0);
        final updated = (_downloadsById[movieId] ?? initialTask).copyWith(
          apiDownloadUrl: cleanApiDownloadUrl.isNotEmpty
              ? cleanApiDownloadUrl
              : effectiveDownloadTarget,
          localFilePath: localPath,
          status: "downloading",
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
          progress: pct,
          speedLabel: speedText,
          errorMessage: "",
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        _downloadsById[movieId] = updated;
        notifyListeners();
      },
      onCompleted: (localPath, totalBytes) {
        final completed = (_downloadsById[movieId] ?? initialTask).copyWith(
          apiDownloadUrl: cleanApiDownloadUrl.isNotEmpty
              ? cleanApiDownloadUrl
              : effectiveDownloadTarget,
          localFilePath: localPath,
          status: "completed",
          downloadedBytes: totalBytes,
          totalBytes: totalBytes,
          progress: 1.0,
          speedLabel: "Downloaded via C++ Engine",
          errorMessage: "",
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        _downloadsById[movieId] = completed;
        _saveDownloadsToStorage();
        notifyListeners();
      },
      onError: (errMsg) {
        final failed = (_downloadsById[movieId] ?? initialTask).copyWith(
          status: "failed",
          speedLabel: "Open Custom Tab to Download",
          errorMessage: errMsg,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        _downloadsById[movieId] = failed;
        _saveDownloadsToStorage();
        notifyListeners();
      },
    );
  }

  void cancelOrDeleteDownload(String movieId) {
    final existing = _downloadsById[movieId];
    PlatformBridge.cancelVideoDownload(
      movieId,
      localFilePath: existing?.localFilePath,
    );
    _downloadsById.remove(movieId);
    _pendingCustomTabById.remove(movieId);
    _saveDownloadsToStorage();
    notifyListeners();
  }
}
