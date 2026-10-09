import "dart:async";
import "dart:ui" as ui;
import "package:flutter/material.dart";
import "../models/movie_models.dart";
import "../services/mini_chrome_browser_service.dart";
import "../services/platform_bridge.dart";
import "../services/watch_history_download_service.dart";
import "../widgets/glass_container.dart";

class MoviePlayerPage extends StatefulWidget {
  final MovieItem movie;
  final List<MovieItem> allMovies;
  final bool isLiked;
  final bool isBookmarked;
  final VoidCallback onBack;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleBookmark;
  final VoidCallback onShareMovie;
  final ValueChanged<String> onAddComment;
  final ValueChanged<MovieItem> onSelectOtherMovie;
  final ValueChanged<double> onUpdateProgress;
  final ValueChanged<bool>? onFullscreenChanged;
  final VoidCallback? onOpenDownloadsManager;

  const MoviePlayerPage({
    super.key,
    required this.movie,
    required this.allMovies,
    required this.isLiked,
    required this.isBookmarked,
    required this.onBack,
    required this.onToggleLike,
    required this.onToggleBookmark,
    required this.onShareMovie,
    required this.onAddComment,
    required this.onSelectOtherMovie,
    required this.onUpdateProgress,
    this.onFullscreenChanged,
    this.onOpenDownloadsManager,
  });

  @override
  State<MoviePlayerPage> createState() => _MoviePlayerPageState();
}

class _MoviePlayerPageState extends State<MoviePlayerPage> {
  Object? _videoElement;
  late String _embedViewType;
  String? _directVideoViewType;

  /// Automatically detects whether the app is running in the Website environment
  /// (`PlatformBridge.isWeb == true`) or Android Application environment (`PlatformBridge.isWeb == false`).
  /// - On Website: Defaults to Streamtape Frame (`_useEmbedFrame = true`) because direct links are IP/session-bound on web.
  /// - On Android App: Defaults to Direct Link Native Player (`_useEmbedFrame = false`).
  late bool _useEmbedFrame;
  bool _isFullscreen = false;
  bool _isResolvingDirect = false;
  bool _hasStreamError = false;
  bool _isPlaying = true;
  bool _isMuted = false;
  bool _showControls = true;
  bool _isPlayingOfflineCopy = false;
  double _currentSeconds = 0.0;
  double _totalSeconds = 100.0;
  double _initialResumeSeconds = 0.0;
  bool _showResumeToast = false;
  Timer? _hideControlsTimer;
  Timer? _progressPollTimer;

  // Dual Audio detection & active audio track selection state
  int _selectedAudioTrackIndex = 0;
  late List<String> _availableAudioTracks;

  bool _showCommentsDrawer = false;
  bool _showShareBanner = false;
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Keep screen awake while the video player page is open so the screen never dims or sleeps
    PlatformBridge.setScreenWakelock(true);
    WatchHistoryDownloadService.instance.addListener(_onDownloadOrHistoryChanged);
    _initStreamtapePlayer(widget.movie);
  }

  void _onDownloadOrHistoryChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant MoviePlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movie.id != widget.movie.id) {
      _disposeVideo(keepFullscreenAndWakelock: true);
      _initStreamtapePlayer(widget.movie);
    }
  }

  /// Checks whether the current movie has Dual Audio / Multi-Audio tracks
  List<String> _detectMovieAudioTracks(MovieItem movie) {
    final combined =
        "${movie.title} ${movie.qualityBadge} ${movie.synopsis} ${movie.tagline}"
            .toLowerCase();
    final bool hasDualAudio = combined.contains("dual") ||
        combined.contains("multi") ||
        (combined.contains("hindi") && combined.contains("english")) ||
        combined.contains("dubbed") ||
        combined.contains("org") ||
        combined.contains("line");

    if (hasDualAudio) {
      return [
        "Track 1: Hindi / Dubbed Audio (Default)",
        "Track 2: English / Original Audio",
      ];
    }
    if (combined.contains("hindi")) {
      return [
        "Track 1: Hindi Audio (Primary)",
        "Track 2: Original / Stereo Audio",
      ];
    }
    if (combined.contains("kannada")) {
      return [
        "Track 1: Kannada / Regional Audio",
        "Track 2: Original / Hindi Audio",
      ];
    }
    return [
      "Track 1: Original Cinema Audio (Primary)",
      "Track 2: Alternate / Boosted Stereo Audio",
    ];
  }

  bool _isMovieDualAudio(MovieItem movie) {
    final combined =
        "${movie.title} ${movie.qualityBadge} ${movie.synopsis} ${movie.tagline}"
            .toLowerCase();
    return combined.contains("dual") ||
        combined.contains("multi") ||
        (combined.contains("hindi") && combined.contains("english")) ||
        combined.contains("dubbed") ||
        combined.contains("hindi");
  }

  void _initStreamtapePlayer(MovieItem movie, {bool? forceEmbedMode}) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    _embedViewType = "niooo-st-embed-${movie.id}-$timestamp";
    _availableAudioTracks = _detectMovieAudioTracks(movie);
    _selectedAudioTrackIndex = 0;

    // Look up exact saved timestamp from WatchHistoryDownloadService
    final savedSec =
        WatchHistoryDownloadService.instance.getSavedPositionSeconds(movie.id);
    _initialResumeSeconds = savedSec;

    // Automatic Environment Detection:
    // Website -> Streamtape Frame mode (`true`)
    // Android App -> Direct Link mode (`false`)
    _useEmbedFrame = forceEmbedMode ?? PlatformBridge.isWeb;
    _hasStreamError = false;
    _directVideoViewType = null;
    _isPlayingOfflineCopy = false;
    _currentSeconds = savedSec;
    final savedHistory =
        WatchHistoryDownloadService.instance.getHistoryForMovie(movie.id);
    _totalSeconds = (savedHistory != null && savedHistory.durationSeconds > 0)
        ? savedHistory.durationSeconds
        : 100.0;

    final String embedSrc = movie.embedUrl.isNotEmpty
        ? movie.embedUrl
        : "https://streamtape.com/e/${movie.streamtapeId.isNotEmpty ? movie.streamtapeId : movie.id}/";

    if (PlatformBridge.isWeb) {
      PlatformBridge.registerIframeFactory(_embedViewType, embedSrc);
    }

    if (_useEmbedFrame) {
      // Running in Streamtape Frame mode (Default for Website)
      setState(() {
        _isResolvingDirect = false;
        _hasStreamError = false;
      });
      return;
    }

    // 1. Check if movie is already downloaded offline on Android device!
    final offlinePath = WatchHistoryDownloadService.instance
        .getCompletedOfflineFilePath(movie.id);
    if (!PlatformBridge.isWeb &&
        offlinePath != null &&
        offlinePath.isNotEmpty) {
      _isPlayingOfflineCopy = true;
      _setupDirectHtml5Video(
        movie,
        offlinePath,
        initialSeekSeconds: _initialResumeSeconds,
      );
      setState(() {
        _isResolvingDirect = false;
        _hasStreamError = false;
        if (_initialResumeSeconds > 3.0) {
          _showResumeToast = true;
        }
      });
      _switchToDirectPlayer();
      if (_initialResumeSeconds > 3.0) {
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _showResumeToast = false);
        });
      }
      return;
    }

    // 2. Running in Direct Link mode (Default for Android App, or if manually clicked)
    setState(() {
      _isResolvingDirect = true;
      _hasStreamError = false;
    });

    final String directTarget = movie.streamtapeId.isNotEmpty
        ? movie.streamtapeId
        : (movie.embedUrl.isNotEmpty
            ? movie.embedUrl
            : (movie.downloadUrl.isNotEmpty ? movie.downloadUrl : movie.id));

    MovieCatalogData.resolveDirectStreamUrl(directTarget).then((directUrl) {
      if (!mounted || widget.movie.id != movie.id) return;
      if (directUrl != null &&
          directUrl.startsWith("http") &&
          !directUrl.contains("/e/")) {
        _setupDirectHtml5Video(
          movie,
          directUrl,
          initialSeekSeconds: _initialResumeSeconds,
        );
        setState(() {
          _isResolvingDirect = false;
          _hasStreamError = false;
          if (_initialResumeSeconds > 3.0) {
            _showResumeToast = true;
          }
        });
        _switchToDirectPlayer();
        if (_initialResumeSeconds > 3.0) {
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) setState(() => _showResumeToast = false);
          });
        }

        // Silently pre-extract next episode / recommended movie in background with C++ engine
        final candidates = widget.allMovies
            .where((m) => m.id != movie.id)
            .take(2)
            .toList();
        for (final nextItem in candidates) {
          final nextTarget = nextItem.streamtapeId.isNotEmpty
              ? nextItem.streamtapeId
              : (nextItem.embedUrl.isNotEmpty ? nextItem.embedUrl : nextItem.id);
          MovieCatalogData.resolveDirectStreamUrl(nextTarget);
        }
      } else {
        // If on Web and direct link fails, automatically fall back to Streamtape Frame
        if (PlatformBridge.isWeb) {
          setState(() {
            _useEmbedFrame = true;
            _isResolvingDirect = false;
            _hasStreamError = false;
          });
        } else {
          setState(() {
            _isResolvingDirect = false;
            _hasStreamError = true;
          });
        }
      }
    }).catchError((_) {
      if (!mounted || widget.movie.id != movie.id) return;
      if (PlatformBridge.isWeb) {
        setState(() {
          _useEmbedFrame = true;
          _isResolvingDirect = false;
          _hasStreamError = false;
        });
      } else {
        setState(() {
          _isResolvingDirect = false;
          _hasStreamError = true;
        });
      }
    });
  }

  void _switchToStreamtapeFrameMode() {
    _disposeVideo(keepFullscreenAndWakelock: true);
    final movie = widget.movie;
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    _embedViewType = "niooo-st-embed-${movie.id}-$timestamp";
    final String embedSrc = movie.embedUrl.isNotEmpty
        ? movie.embedUrl
        : "https://streamtape.com/e/${movie.id}";
    if (PlatformBridge.isWeb) {
      PlatformBridge.registerIframeFactory(_embedViewType, embedSrc);
    }
    setState(() {
      _useEmbedFrame = true;
      _isResolvingDirect = false;
      _hasStreamError = false;
    });
  }

  void _switchToDirectStreamMode() {
    _disposeVideo(keepFullscreenAndWakelock: true);
    _initStreamtapePlayer(widget.movie, forceEmbedMode: false);
  }

  /// Triggered when the user taps the Download button:
  /// Does NOT start any premature or demo download when clicked!
  /// Instead, it opens the API `download_url` inside the integrated Custom Chrome Tab below the player
  /// so the user can view the page/ads and click the Download button inside the Custom Tab.
  /// Real-time download tracking begins ONLY when the user triggers the download inside the Custom Tab!
  void _handleDownloadMovieTap() {
    final movie = widget.movie;
    final String apiDownloadLink = movie.downloadUrl.trim();
    if (apiDownloadLink.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF071A14),
          behavior: SnackBarBehavior.floating,
          content: Text(
            "API download link is not available for this video.",
            style: TextStyle(
              color: Color(0xFFFF6B6B),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      );
      return;
    }

    // Open the API download_url inside our Custom Chrome Tab with real-time download detection.
    // No download or progress bar starts until the user clicks Download inside the Custom Tab!
    MiniChromeBrowserService.openDownloadPortalBelowPlayer(
      context,
      movieId: movie.id,
      title: movie.title,
      posterUrl: movie.posterUrl,
      backdropUrl: movie.backdropUrl,
      qualityBadge: movie.qualityBadge,
      language: movie.language,
      apiDownloadUrl: apiDownloadLink,
      estimatedSizeBytes: movie.sizeBytes,
    );
  }

  void _openDualAudioSettingsSheet() {
    final movie = widget.movie;
    final isDual = _isMovieDualAudio(movie);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              decoration: BoxDecoration(
                color: const Color(0xFF061310),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(26)),
                border: Border.all(
                  color: const Color(0xFF00E676).withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF00E676).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.tune_rounded,
                          color: Color(0xFF00E676),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Dual Audio & Stream Settings",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isDual
                                  ? "✔ Dual Audio Detected (${movie.qualityBadge})"
                                  : "Standard Multi-Channel Audio (${movie.qualityBadge})",
                              style: TextStyle(
                                color: isDual
                                    ? const Color(0xFF00E676)
                                    : const Color(0xFF94A3B8),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isDual
                              ? Icons.graphic_eq_rounded
                              : Icons.audiotrack_rounded,
                          color: const Color(0xFF00E676),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isDual
                                ? "Dual Audio Status: Available (Hindi / English Tracks)"
                                : "Audio Status: Single Primary Language Track",
                            style: const TextStyle(
                              color: Color(0xFFF0FDF4),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "SELECT AUDIO LANGUAGE TRACK",
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(_availableAudioTracks.length, (index) {
                    final trackLabel = _availableAudioTracks[index];
                    final isSelected = _selectedAudioTrackIndex == index;
                    return GestureDetector(
                      onTap: () {
                        setModalState(() => _selectedAudioTrackIndex = index);
                        setState(() => _selectedAudioTrackIndex = index);
                        PlatformBridge.switchVideoAudioTrack(
                          _videoElement,
                          index,
                        );
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF071A14),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                            content: Text(
                              "Audio switched to $trackLabel",
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? LinearGradient(
                                  colors: [
                                    const Color(0xFF00E676)
                                        .withValues(alpha: 0.22),
                                    const Color(0xFF10B981)
                                        .withValues(alpha: 0.10),
                                  ],
                                )
                              : null,
                          color: isSelected
                              ? null
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF00E676)
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              color: isSelected
                                  ? const Color(0xFF00E676)
                                  : Colors.white54,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                trackLabel,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFFCBD5E1),
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  "ACTIVE",
                                  style: TextStyle(
                                    color: Color(0xFF03120D),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _setupDirectHtml5Video(
    MovieItem movie,
    String directMp4Url, {
    double initialSeekSeconds = 0.0,
  }) {
    final viewType =
        "niooo-st-direct-${movie.id}-${DateTime.now().microsecondsSinceEpoch}";

    final video = PlatformBridge.registerVideoFactory(
      viewType: viewType,
      src: directMp4Url,
      posterUrl: movie.backdropUrl,
      initialSeekSeconds: initialSeekSeconds,
      onDurationLoaded: (dur) {
        if (!mounted) return;
        setState(() {
          _totalSeconds = dur;
        });
      },
      onPlay: () {
        if (!mounted) return;
        setState(() => _isPlaying = true);
      },
      onPause: () {
        if (!mounted) return;
        setState(() => _isPlaying = false);
        _commitCurrentWatchPosition(force: true);
      },
    );

    if (video != null) {
      setState(() {
        _videoElement = video;
        _directVideoViewType = viewType;
      });
    }
  }

  void _commitCurrentWatchPosition({bool force = false}) {
    if (_currentSeconds <= 1.0) return;
    final movie = widget.movie;
    final ratio = _totalSeconds > 0
        ? (_currentSeconds / _totalSeconds).clamp(0.0, 1.0)
        : 0.0;
    widget.onUpdateProgress(ratio);
    WatchHistoryDownloadService.instance.recordWatchPosition(
      movieId: movie.id,
      title: movie.title,
      posterUrl: movie.posterUrl,
      backdropUrl: movie.backdropUrl,
      qualityBadge: movie.qualityBadge,
      language: movie.language,
      positionSeconds: _currentSeconds,
      durationSeconds: _totalSeconds,
      forceCommit: force,
    );
  }

  void _switchToDirectPlayer() {
    if (_directVideoViewType == null || _videoElement == null) return;
    setState(() {
      _useEmbedFrame = false;
      _showControls = true;
    });
    PlatformBridge.playVideo(_videoElement, () {
      if (mounted) setState(() => _isMuted = true);
    });

    _progressPollTimer?.cancel();
    _progressPollTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || _videoElement == null) return;
      final cur = PlatformBridge.getVideoCurrentTime(_videoElement);
      final dur = PlatformBridge.getVideoDuration(_videoElement);
      if (!cur.isNaN && cur > 0) {
        setState(() {
          _currentSeconds = cur;
          if (!dur.isNaN && !dur.isInfinite && dur > 0) {
            _totalSeconds = dur;
          }
        });
        _commitCurrentWatchPosition(force: false);
      }
    });

    _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControlsVisibility() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _scheduleHideControls();
    }
  }

  void _togglePlayPause() {
    final v = _videoElement;
    if (v == null) return;
    if (PlatformBridge.isVideoPaused(v)) {
      PlatformBridge.playVideo(v, () {});
      setState(() => _isPlaying = true);
      _scheduleHideControls();
    } else {
      PlatformBridge.pauseVideo(v);
      setState(() => _isPlaying = false);
      _commitCurrentWatchPosition(force: true);
    }
  }

  void _seekRelative(double deltaSeconds) {
    final v = _videoElement;
    if (v == null) return;
    final target = (_currentSeconds + deltaSeconds).clamp(0.0, _totalSeconds);
    PlatformBridge.setVideoCurrentTime(v, target);
    setState(() => _currentSeconds = target);
    _commitCurrentWatchPosition(force: true);
    _scheduleHideControls();
  }

  void _toggleMute() {
    final v = _videoElement;
    if (v == null) return;
    final muted = PlatformBridge.toggleVideoMute(v);
    setState(() => _isMuted = muted);
  }

  void _toggleFullscreen() {
    PlatformBridge.setScreenWakelock(true);
    if (PlatformBridge.isWeb && !_useEmbedFrame && _videoElement != null) {
      PlatformBridge.requestVideoFullscreen(_videoElement);
      return;
    }

    final nextFullscreen = !_isFullscreen;
    setState(() {
      _isFullscreen = nextFullscreen;
      _showControls = true;
    });
    widget.onFullscreenChanged?.call(nextFullscreen);

    if (nextFullscreen) {
      PlatformBridge.enterNativeFullscreen();
    } else {
      PlatformBridge.exitNativeFullscreen();
    }
    _scheduleHideControls();
  }

  void _handleBackOrExitFullscreen() {
    if (_isFullscreen) {
      setState(() {
        _isFullscreen = false;
        _showControls = true;
      });
      widget.onFullscreenChanged?.call(false);
      PlatformBridge.exitNativeFullscreen();
      return;
    }
    _commitCurrentWatchPosition(force: true);
    widget.onBack();
  }

  void _disposeVideo({bool keepFullscreenAndWakelock = false}) {
    _hideControlsTimer?.cancel();
    _progressPollTimer?.cancel();
    if (_videoElement != null && _totalSeconds > 0 && _currentSeconds > 1.0) {
      _commitCurrentWatchPosition(force: true);
    }
    if (keepFullscreenAndWakelock) {
      if (_videoElement != null) {
        PlatformBridge.pauseVideo(_videoElement);
      }
      PlatformBridge.setScreenWakelock(true);
    } else {
      widget.onFullscreenChanged?.call(false);
      PlatformBridge.disposeVideo(_videoElement);
    }
    _videoElement = null;
    _directVideoViewType = null;
  }

  @override
  void dispose() {
    WatchHistoryDownloadService.instance
        .removeListener(_onDownloadOrHistoryChanged);
    _disposeVideo(keepFullscreenAndWakelock: false);
    _commentController.dispose();
    super.dispose();
  }

  String _formatTime(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds < 0) return "00:00";
    final int total = seconds.round();
    final int hrs = total ~/ 3600;
    final int mins = (total % 3600) ~/ 60;
    final int secs = total % 60;
    if (hrs > 0) {
      return "${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
    }
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
  }

  String _formatCompactCount(int n) {
    if (n >= 1000000) {
      return "${(n / 1000000).toStringAsFixed(1)}M";
    }
    if (n >= 1000) {
      return "${(n / 1000).toStringAsFixed(1)}K";
    }
    return "$n";
  }

  void _handleShareTap() {
    widget.onShareMovie();
    final shareLink = widget.movie.downloadUrl.isNotEmpty
        ? widget.movie.downloadUrl
        : (widget.movie.embedUrl.isNotEmpty
            ? widget.movie.embedUrl
            : "https://streamtape.com/e/${widget.movie.streamtapeId}");
    PlatformBridge.copyToClipboard(shareLink);
    setState(() => _showShareBanner = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showShareBanner = false);
    });
  }

  Widget _buildVideoPlayerStack(
    MovieItem movie,
    String embedSrc,
    double progressRatio,
  ) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_useEmbedFrame && PlatformBridge.isWeb)
            // Website Environment: Play via Official Streamtape Frame (`https://streamtape.com/e/<id>`)
            PlatformBridge.buildEmbeddedPlayer(
              viewType: _embedViewType,
              embedSrc: embedSrc,
              backdropUrl: movie.backdropUrl,
              title: movie.title,
            )
          else if (_directVideoViewType != null && _videoElement != null)
            // Android Environment (or Direct Stream active): Play via Direct Stream / Offline File
            Stack(
              fit: StackFit.expand,
              children: [
                PlatformBridge.buildCustomVideoSurface(
                  videoObj: _videoElement,
                  viewType: _directVideoViewType!,
                  backdropUrl: movie.backdropUrl,
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControlsVisibility,
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.45),
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.78),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                        child: Stack(
                          children: [
                            Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _playerCircleControl(
                                    icon: Icons.replay_10_rounded,
                                    size: 42,
                                    onTap: () => _seekRelative(-10),
                                  ),
                                  const SizedBox(width: 24),
                                  GestureDetector(
                                    onTap: _togglePlayPause,
                                    child: Container(
                                      width: 58,
                                      height: 58,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF00E676),
                                            Color(0xFF10B981),
                                          ],
                                        ),
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.75),
                                          width: 1.4,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF00E676)
                                                .withValues(alpha: 0.55),
                                            blurRadius: 20,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        _isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: const Color(0xFF03120D),
                                        size: 34,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  _playerCircleControl(
                                    icon: Icons.forward_10_rounded,
                                    size: 42,
                                    onTap: () => _seekRelative(10),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: _isFullscreen ? 14 : 6,
                              child: Row(
                                children: [
                                  Text(
                                    _formatTime(_currentSeconds),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 3.0,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 6.0,
                                        ),
                                        overlayShape:
                                            const RoundSliderOverlayShape(
                                          overlayRadius: 12.0,
                                        ),
                                      ),
                                      child: Slider(
                                        value: progressRatio,
                                        activeColor: const Color(0xFF00E676),
                                        inactiveColor: Colors.white30,
                                        onChanged: (v) {
                                          final target = v * _totalSeconds;
                                          PlatformBridge.setVideoCurrentTime(
                                              _videoElement, target);
                                          setState(
                                              () => _currentSeconds = target);
                                          _commitCurrentWatchPosition(
                                              force: true);
                                          _scheduleHideControls();
                                        },
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _formatTime(_totalSeconds),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _toggleMute,
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Icon(
                                        _isMuted
                                            ? Icons.volume_off_rounded
                                            : Icons.volume_up_rounded,
                                        color: Colors.white,
                                        size: 21,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            // Loading / Retry state for Direct Stream
            Stack(
              fit: StackFit.expand,
              children: [
                if (movie.backdropUrl.isNotEmpty)
                  Image.network(
                    movie.backdropUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: const Color(0xFF050D0A)),
                  ),
                Container(
                  color: Colors.black.withValues(alpha: 0.65),
                  child: Center(
                    child: _hasStreamError
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.refresh_rounded,
                                color: Color(0xFF00E676),
                                size: 36,
                              ),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () => _initStreamtapePlayer(movie),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00E676),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Text(
                                    "Retry Stream",
                                    style: TextStyle(
                                      color: Color(0xFF03120D),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const _PlayerPercentageLoader(),
                  ),
                ),
              ],
            ),

          // Resume from exact timestamp toast badge
          if (_showResumeToast && _initialResumeSeconds > 3.0)
            Positioned(
              top: 12,
              left: 56,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF04140F).withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.65),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.25),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      color: Color(0xFF00E676),
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Resumed from ${_formatTime(_initialResumeSeconds)}",
                      style: const TextStyle(
                        color: Color(0xFFF0FDF4),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Offline Playback Badge
          if (_isPlayingOfflineCopy && !_showResumeToast)
            Positioned(
              top: 12,
              left: 56,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF04140F).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.55),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.offline_pin_rounded,
                      color: Color(0xFF00E676),
                      size: 14,
                    ),
                    SizedBox(width: 5),
                    Text(
                      "Playing Offline Copy",
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Top-Left: Clean Minimize / Back button
          Positioned(
            top: 10,
            left: 12,
            child: GestureDetector(
              onTap: _handleBackOrExitFullscreen,
              child: ClipOval(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Top-Right: Clean Settings Icon + Quick Download Icon
          Positioned(
            top: 10,
            right: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _handleDownloadMovieTap,
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF00E676)
                                .withValues(alpha: 0.45),
                          ),
                        ),
                        child: const Icon(
                          Icons.download_rounded,
                          color: Color(0xFF00E676),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _openDualAudioSettingsSheet,
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF00E676)
                                .withValues(alpha: 0.45),
                          ),
                        ),
                        child: const Icon(
                          Icons.settings_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final mediaSize = MediaQuery.of(context).size;
    final mediaOrientation = MediaQuery.of(context).orientation;
    final bool isEffectiveFullscreen = _isFullscreen ||
        (!PlatformBridge.isWeb && mediaOrientation == Orientation.landscape);

    final activeDownloadTask =
        WatchHistoryDownloadService.instance.getDownloadTask(movie.id);

    // Group same-series episodes if this movie is part of a multi-episode series
    final sameSeriesEpisodes = movie.isEpisode
        ? (widget.allMovies
            .where((m) =>
                m.isEpisode &&
                ((movie.seriesId.isNotEmpty && m.seriesId == movie.seriesId) ||
                    (movie.seriesName.isNotEmpty &&
                        m.seriesName.toLowerCase() ==
                            movie.seriesName.toLowerCase())))
            .toList()
          ..sort((a, b) {
            final sCmp = a.seasonNumber.compareTo(b.seasonNumber);
            if (sCmp != 0) return sCmp;
            return a.episodeNumber.compareTo(b.episodeNumber);
          }))
        : <MovieItem>[];

    final otherMovies =
        widget.allMovies.where((m) => m.id != movie.id).toList();

    final double progressRatio = _totalSeconds > 0
        ? (_currentSeconds / _totalSeconds).clamp(0.0, 1.0)
        : 0.0;

    final String embedSrc = movie.embedUrl.isNotEmpty
        ? movie.embedUrl
        : "https://streamtape.com/e/${movie.id}";

    if (isEffectiveFullscreen) {
      final bool needsManualLandscapeRotation =
          !PlatformBridge.isWeb && mediaSize.height > mediaSize.width;
      final Widget playerStack =
          _buildVideoPlayerStack(movie, embedSrc, progressRatio);

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          setState(() {
            _isFullscreen = false;
            _showControls = true;
          });
          widget.onFullscreenChanged?.call(false);
          PlatformBridge.exitNativeFullscreen();
        },
        child: Container(
          color: Colors.black,
          width: double.infinity,
          height: double.infinity,
          child: needsManualLandscapeRotation
              ? RotatedBox(
                  quarterTurns: 1,
                  child: playerStack,
                )
              : playerStack,
        ),
      );
    }

    return Container(
      color: const Color(0xFF030706),
      child: Column(
        children: [
          // ==============================================================
          // 1. AUTO-DETECTED VIDEO PLAYER (STREAMTAPE FRAME ON WEB / DIRECT ON ANDROID)
          // ==============================================================
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildVideoPlayerStack(movie, embedSrc, progressRatio),
          ),

          // ==============================================================
          // 1B. STREAM MODE, DOWNLOAD & FULLSCREEN BUTTON BAR
          // ==============================================================
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF06110E),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF00E676).withValues(alpha: 0.16),
                ),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Streamtape Frame Button
                  GestureDetector(
                    onTap: _switchToStreamtapeFrameMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: _useEmbedFrame
                            ? const LinearGradient(
                                colors: [Color(0xFF00E676), Color(0xFF10B981)],
                              )
                            : null,
                        color: _useEmbedFrame
                            ? null
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _useEmbedFrame
                              ? Colors.white70
                              : const Color(0xFF00E676).withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.web_asset_rounded,
                            size: 14,
                            color: _useEmbedFrame
                                ? const Color(0xFF03120D)
                                : const Color(0xFF00E676),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            PlatformBridge.isWeb
                                ? "Streamtape Frame (Web Auto)"
                                : "Streamtape Frame",
                            style: TextStyle(
                              color: _useEmbedFrame
                                  ? const Color(0xFF03120D)
                                  : const Color(0xFFF0FDF4),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Direct Stream Player Button (Default & Native on Android App)
                  GestureDetector(
                    onTap: _switchToDirectStreamMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: !_useEmbedFrame
                            ? const LinearGradient(
                                colors: [Color(0xFF00E676), Color(0xFF10B981)],
                              )
                            : null,
                        color: !_useEmbedFrame
                            ? null
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !_useEmbedFrame
                              ? Colors.white70
                              : const Color(0xFF00E676).withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_circle_fill_rounded,
                            size: 14,
                            color: !_useEmbedFrame
                                ? const Color(0xFF03120D)
                                : const Color(0xFF00E676),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            !PlatformBridge.isWeb
                                ? "Direct Player (Android Auto)"
                                : "Direct Stream",
                            style: TextStyle(
                              color: !_useEmbedFrame
                                  ? const Color(0xFF03120D)
                                  : const Color(0xFFF0FDF4),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Download Button (Opens Custom Chrome Tab + Starts Real-time Download Manager)
                  GestureDetector(
                    onTap: _handleDownloadMovieTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: (activeDownloadTask != null &&
                                (activeDownloadTask.isDownloading ||
                                    activeDownloadTask.isCompleted))
                            ? const LinearGradient(
                                colors: [Color(0xFF00E676), Color(0xFF10B981)],
                              )
                            : null,
                        color: (activeDownloadTask != null &&
                                (activeDownloadTask.isDownloading ||
                                    activeDownloadTask.isCompleted))
                            ? null
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF00E676).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            activeDownloadTask?.isCompleted == true
                                ? Icons.offline_pin_rounded
                                : Icons.download_for_offline_rounded,
                            size: 15,
                            color: (activeDownloadTask != null &&
                                    (activeDownloadTask.isDownloading ||
                                        activeDownloadTask.isCompleted))
                                ? const Color(0xFF03120D)
                                : const Color(0xFF00E676),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            activeDownloadTask == null
                                ? "Download Offline"
                                : activeDownloadTask.isCompleted
                                    ? "Downloaded (Offline)"
                                    : activeDownloadTask.isDownloading
                                        ? "Downloading ${(activeDownloadTask.progress * 100).round()}%"
                                        : "Retry Download",
                            style: TextStyle(
                              color: (activeDownloadTask != null &&
                                      (activeDownloadTask.isDownloading ||
                                          activeDownloadTask.isCompleted))
                                  ? const Color(0xFF03120D)
                                  : const Color(0xFFF0FDF4),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Dual Audio Quick Button
                  GestureDetector(
                    onTap: _openDualAudioSettingsSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF00E676).withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.graphic_eq_rounded,
                            size: 14,
                            color: Color(0xFF00E676),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _isMovieDualAudio(movie)
                                ? "Dual Audio (${_selectedAudioTrackIndex == 0 ? 'Track 1' : 'Track 2'})"
                                : "Audio Settings",
                            style: const TextStyle(
                              color: Color(0xFFF0FDF4),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Full Screen Quick Button
                  GestureDetector(
                    onTap: _toggleFullscreen,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF00E676).withValues(alpha: 0.28),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.fullscreen_rounded,
                            size: 15,
                            color: Color(0xFF00E676),
                          ),
                          SizedBox(width: 4),
                          Text(
                            "Full Screen",
                            style: TextStyle(
                              color: Color(0xFFF0FDF4),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ==============================================================
          // 2. BELOW VIDEO PLAYER: TITLE, LIKE / DOWNLOAD / COMMENT / SHARE BAR, EPISODES & OTHER MOVIES
          // ==============================================================
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
              children: [
                // Movie Title + Views & Streamtape Metadata
                Text(
                  movie.title,
                  style: const TextStyle(
                    color: Color(0xFFF0FDF4),
                    fontSize: 20.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      "${movie.viewsLabel} · ${movie.releaseYear} · ${movie.duration} · ${movie.genres.join(' • ')}",
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF00E676).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              const Color(0xFF00E676).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        "★ ${movie.rating} · ${movie.qualityBadge}",
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ==========================================================
                // INTERACTIVE LIKE, DOWNLOAD, COMMENT, SHARE & WATCHLIST ACTION BAR
                // ==========================================================
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // 1. LIKE BUTTON
                      _buildActionPill(
                        icon: widget.isLiked
                            ? Icons.thumb_up_alt_rounded
                            : Icons.thumb_up_off_alt_rounded,
                        label:
                            "Like · ${_formatCompactCount(movie.likesCount)}",
                        isActive: widget.isLiked,
                        onTap: widget.onToggleLike,
                      ),
                      const SizedBox(width: 10),

                      // 2. DOWNLOAD BUTTON (Opens Custom Chrome Tab + Starts Niooo M Download Manager)
                      _buildActionPill(
                        icon: activeDownloadTask?.isCompleted == true
                            ? Icons.offline_pin_rounded
                            : Icons.download_rounded,
                        label: activeDownloadTask == null
                            ? "Download"
                            : activeDownloadTask.isCompleted
                                ? "Downloaded"
                                : activeDownloadTask.isDownloading
                                    ? "${(activeDownloadTask.progress * 100).round()}% · ${activeDownloadTask.speedLabel}"
                                    : "Download",
                        isActive: activeDownloadTask != null &&
                            (activeDownloadTask.isDownloading ||
                                activeDownloadTask.isCompleted),
                        onTap: _handleDownloadMovieTap,
                      ),
                      const SizedBox(width: 10),

                      // 3. COMMENT BUTTON
                      _buildActionPill(
                        icon: Icons.mode_comment_outlined,
                        label: "Comment (${movie.comments.length})",
                        isActive: _showCommentsDrawer,
                        onTap: () => setState(
                          () => _showCommentsDrawer = !_showCommentsDrawer,
                        ),
                      ),
                      const SizedBox(width: 10),

                      // 4. SHARE BUTTON
                      _buildActionPill(
                        icon: Icons.reply_rounded,
                        label:
                            "Share · ${_formatCompactCount(movie.sharesCount)}",
                        isActive: _showShareBanner,
                        onTap: _handleShareTap,
                      ),
                      const SizedBox(width: 10),

                      // 5. SAVE TO WATCHLIST BUTTON
                      _buildActionPill(
                        icon: widget.isBookmarked
                            ? Icons.bookmark_added_rounded
                            : Icons.bookmark_add_outlined,
                        label: widget.isBookmarked ? "Saved" : "Watchlist",
                        isActive: widget.isBookmarked,
                        onTap: widget.onToggleBookmark,
                      ),
                    ],
                  ),
                ),

                // Real-time Download Progress Card inside Player Page when downloading or completed
                if (activeDownloadTask != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF00E676).withValues(alpha: 0.14),
                          const Color(0xFF061511).withValues(alpha: 0.92),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              activeDownloadTask.isCompleted
                                  ? Icons.check_circle_rounded
                                  : Icons.downloading_rounded,
                              color: const Color(0xFF00E676),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                activeDownloadTask.isCompleted
                                    ? "Offline Download Complete (${activeDownloadTask.formattedSizeProgress})"
                                    : "Niooo M C++ Download Engine · ${(activeDownloadTask.progress * 100).round()}%",
                                style: const TextStyle(
                                  color: Color(0xFFF0FDF4),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (widget.onOpenDownloadsManager != null)
                              GestureDetector(
                                onTap: widget.onOpenDownloadsManager,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00E676),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    "View Downloads",
                                    style: TextStyle(
                                      color: Color(0xFF03120D),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0.01,
                              end: activeDownloadTask.isCompleted
                                  ? 1.0
                                  : activeDownloadTask.progress.clamp(0.02, 1.0),
                            ),
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            builder: (context, animatedValue, _) {
                              return LinearProgressIndicator(
                                value: animatedValue,
                                minHeight: 5.5,
                                backgroundColor: Colors.white12,
                                color: const Color(0xFF00E676),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              activeDownloadTask.formattedSizeProgress,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              activeDownloadTask.speedLabel,
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                if (_showShareBanner) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.45),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF00E676),
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Streamtape movie link copied to clipboard!",
                            style: TextStyle(
                              color: Color(0xFFF0FDF4),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ==========================================================
                // SERIES EPISODES SELECTOR
                // ==========================================================
                if (sameSeriesEpisodes.length > 1) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF00E676).withValues(alpha: 0.10),
                          const Color(0xFF071512).withValues(alpha: 0.85),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.28),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.video_library_rounded,
                              color: Color(0xFF00E676),
                              size: 17,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                "${movie.seriesName} — All Episodes (${sameSeriesEpisodes.length})",
                                style: const TextStyle(
                                  color: Color(0xFFF0FDF4),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: sameSeriesEpisodes.map((ep) {
                            final isCurrent = ep.id == movie.id;
                            return GestureDetector(
                              onTap: () {
                                if (!isCurrent) {
                                  widget.onSelectOtherMovie(ep);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  gradient: isCurrent
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFF00E676),
                                            Color(0xFF10B981),
                                          ],
                                        )
                                      : null,
                                  color: isCurrent
                                      ? null
                                      : Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isCurrent
                                        ? Colors.white70
                                        : const Color(0xFF00E676)
                                            .withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Text(
                                  ep.episodeLabel.isNotEmpty
                                      ? ep.episodeLabel
                                      : "EP ${ep.episodeNumber.toString().padLeft(2, '0')}",
                                  style: TextStyle(
                                    color: isCurrent
                                        ? const Color(0xFF03120D)
                                        : const Color(0xFFF0FDF4),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Expandable / Interactive Comments Box right below the Action Bar
                GestureDetector(
                  onTap: () => setState(
                    () => _showCommentsDrawer = !_showCommentsDrawer,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.06),
                          const Color(0xFF091613).withValues(alpha: 0.78),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              "Comments",
                              style: TextStyle(
                                color: Color(0xFFF0FDF4),
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "${movie.comments.length}",
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              _showCommentsDrawer
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: const Color(0xFF94A3B8),
                              size: 20,
                            ),
                          ],
                        ),
                        if (!_showCommentsDrawer) ...[
                          const SizedBox(height: 6),
                          Text(
                            movie.comments.isNotEmpty
                                ? '${movie.comments.first.authorName}: "${movie.comments.first.comment}"'
                                : "Tap to write the first comment on this movie...",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12.5,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF050E0C),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFF00E676)
                                          .withValues(alpha: 0.28),
                                    ),
                                  ),
                                  child: TextField(
                                    controller: _commentController,
                                    onSubmitted: (val) {
                                      final txt = val.trim();
                                      if (txt.isEmpty) return;
                                      widget.onAddComment(txt);
                                      _commentController.clear();
                                    },
                                    style: const TextStyle(
                                      color: Color(0xFFF0FDF4),
                                      fontSize: 13,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: "Add a public comment...",
                                      hintStyle: TextStyle(
                                        color: Color(0xFF8696A0),
                                        fontSize: 12.5,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GlassIconButton(
                                icon: Icons.send_rounded,
                                tooltip: "Post Comment",
                                size: 38,
                                isAccent: true,
                                color: const Color(0xFF00E676),
                                onTap: () {
                                  final txt = _commentController.text.trim();
                                  if (txt.isEmpty) return;
                                  widget.onAddComment(txt);
                                  _commentController.clear();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (movie.comments.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                "No comments yet. Start the conversation!",
                                style: TextStyle(
                                  color: Color(0xFF8696A0),
                                  fontSize: 12.5,
                                ),
                              ),
                            )
                          else
                            ...movie.comments.map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor:
                                          const Color(0xFF10221D),
                                      backgroundImage: c.avatarUrl.isNotEmpty
                                          ? NetworkImage(c.avatarUrl)
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                c.authorName,
                                                style: const TextStyle(
                                                  color: Color(0xFFF0FDF4),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                c.timeAgo,
                                                style: const TextStyle(
                                                  color: Color(0xFF8696A0),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            c.comment,
                                            style: const TextStyle(
                                              color: Color(0xFFCBD5E1),
                                              fontSize: 12.5,
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Movie Synopsis & Streamtape Info Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movie.synopsis,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 13,
                          height: 1.48,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Language: ${movie.language} · Size: ${movie.duration} · Year: ${movie.releaseYear}",
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // ==========================================================
                // 3. OTHER STREAM-READY MOVIES FROM CATALOG
                // ==========================================================
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_motion_rounded,
                      color: Color(0xFF00E676),
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "More from Niooo M Catalog (${otherMovies.length})",
                        style: const TextStyle(
                          color: Color(0xFFF0FDF4),
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                ...otherMovies.map(
                  (other) => _buildUpNextMovieCard(other),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerCircleControl({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.48),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.54),
          ),
        ),
      ),
    );
  }

  Widget _buildActionPill({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9.5),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [
                    Color(0xFF00E676),
                    Color(0xFF10B981),
                    Color(0xFF047857),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    const Color(0xFF091714).withValues(alpha: 0.82),
                  ],
                ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive
                ? Colors.white.withValues(alpha: 0.6)
                : const Color(0xFF00E676).withValues(alpha: 0.25),
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFF00E676).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: isActive
                  ? const Color(0xFF03120D)
                  : const Color(0xFF00E676),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF03120D)
                    : const Color(0xFFF0FDF4),
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpNextMovieCard(MovieItem item) {
    final historyRec =
        WatchHistoryDownloadService.instance.getHistoryForMovie(item.id);

    return GestureDetector(
      onTap: () => widget.onSelectOtherMovie(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.06),
              const Color(0xFF091613).withValues(alpha: 0.76),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF00E676).withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            // 16:9 Streamtape Thumbnail with Size Badge & Play Icon
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 142,
                height: 84,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      item.backdropUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Image.network(
                        item.posterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF0A1815),
                        ),
                      ),
                    ),
                    Container(
                      color: Colors.black.withValues(alpha: 0.25),
                    ),
                    Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF00E676).withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Color(0xFF03120D),
                          size: 20,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 5,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          historyRec != null
                              ? "Resume ${historyRec.formattedPosition}"
                              : item.duration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (historyRec != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: historyRec.progressRatio.clamp(0.05, 1.0),
                          minHeight: 3,
                          backgroundColor: Colors.black45,
                          color: const Color(0xFF00E676),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF0FDF4),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "${item.qualityBadge} · ${item.genres.join(' • ')}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF00E676),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFBBF24),
                        size: 14,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        "${item.rating}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.viewsLabel,
                        style: const TextStyle(
                          color: Color(0xFF8696A0),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact, text-free circular loading indicator that rotates and counts from 1% to 100%
class _PlayerPercentageLoader extends StatefulWidget {
  const _PlayerPercentageLoader();

  @override
  State<_PlayerPercentageLoader> createState() =>
      _PlayerPercentageLoaderState();
}

class _PlayerPercentageLoaderState extends State<_PlayerPercentageLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;
  Timer? _timer;
  int _percent = 1;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();

    _timer = Timer.periodic(const Duration(milliseconds: 35), (_) {
      if (!mounted) return;
      setState(() {
        if (_percent < 78) {
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
    _timer?.cancel();
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
            child: const SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(
                value: 0.22,
                strokeWidth: 3.2,
                color: Color(0xFF69F0AE),
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
