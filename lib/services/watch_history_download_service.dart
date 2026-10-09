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

  /// Starts or resumes a high-speed download strictly using ONLY the `download_url`
  /// provided by the Niooo M API Key (`apiDownloadUrl`) and the Native C++17 Download Engine.
  /// Never uses the video player's extracted direct stream link.
  Future<void> startMovieDownload({
    required String movieId,
    required String title,
    required String posterUrl,
    required String backdropUrl,
    required String qualityBadge,
    required String language,
    required String apiDownloadUrl,
    required int estimatedSizeBytes,
  }) async {
    final existing = _downloadsById[movieId];
    if (existing != null && existing.isDownloading) {
      return;
    }

    final cleanApiDownloadUrl = apiDownloadUrl.trim();
    if (cleanApiDownloadUrl.isEmpty) {
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
      apiDownloadUrl: cleanApiDownloadUrl,
      localFilePath: existing?.localFilePath ?? "",
      status: "downloading",
      downloadedBytes: (effectiveTotalBytes * 0.01).round(),
      totalBytes: effectiveTotalBytes,
      progress: 0.01,
      speedLabel: "Starting C++ Engine...",
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    _downloadsById[movieId] = initialTask;
    _saveDownloadsToStorage();
    notifyListeners();

    PlatformBridge.showDownloadNotification(
      movieId: movieId,
      title: "Downloading: $title",
      body: "1% · Starting C++ High-Speed Download via API Link",
      progress: 1,
      isOngoing: true,
    );

    await PlatformBridge.startRealVideoDownload(
      movieId: movieId,
      title: title,
      apiDownloadUrl: cleanApiDownloadUrl,
      estimatedBytes: effectiveTotalBytes,
      onProgress: (downloadedBytes, totalBytes, progressRatio, speedText, localPath) {
        final double pct = progressRatio.clamp(0.01, 1.0);
        final updated = (_downloadsById[movieId] ?? initialTask).copyWith(
          apiDownloadUrl: cleanApiDownloadUrl,
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
          apiDownloadUrl: cleanApiDownloadUrl,
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
          speedLabel: "Tap Retry",
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
    _saveDownloadsToStorage();
    notifyListeners();
  }
}
