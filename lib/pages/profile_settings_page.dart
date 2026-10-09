import "package:flutter/material.dart";
import "../models/movie_models.dart";
import "../services/mini_chrome_browser_service.dart";
import "../services/watch_history_download_service.dart";
import "../widgets/glass_container.dart";

// =============================================================================
// PROFILE & DOWNLOADS PAGE — CONTINUE WATCHING (EXACT TIMESTAMP RESUME),
// WATCH HISTORY & REAL-TIME OFFLINE DOWNLOAD MANAGER
// =============================================================================
class ProfileSettingsPage extends StatefulWidget {
  final List<MovieItem> movies;
  final ValueChanged<MovieItem>? onPlayMovie;
  final int initialTabIndex; // 0: Continue & History, 1: Offline Downloads

  const ProfileSettingsPage({
    super.key,
    this.movies = const [],
    this.onPlayMovie,
    this.initialTabIndex = 0,
  });

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  late int _selectedSegment;

  @override
  void initState() {
    super.initState();
    _selectedSegment = widget.initialTabIndex;
    WatchHistoryDownloadService.instance.addListener(_onServiceUpdated);
  }

  @override
  void didUpdateWidget(covariant ProfileSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      setState(() => _selectedSegment = widget.initialTabIndex);
    }
  }

  void _onServiceUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WatchHistoryDownloadService.instance.removeListener(_onServiceUpdated);
    super.dispose();
  }

  MovieItem _resolveMovieForHistory(WatchHistoryRecord rec) {
    for (final m in widget.movies) {
      if (m.id == rec.movieId) return m;
    }
    return MovieItem(
      id: rec.movieId,
      streamtapeId: rec.movieId,
      title: rec.title,
      language: rec.language,
      tagline: "${rec.language} · ${rec.qualityBadge}",
      synopsis: "Resume watching ${rec.title} from ${rec.formattedPosition}.",
      posterUrl: rec.posterUrl,
      backdropUrl: rec.backdropUrl,
      embedUrl: "https://streamtape.com/e/${rec.movieId}/",
      downloadUrl: "https://streamtape.com/v/${rec.movieId}/",
      videoStreamUrl:
          "/api/streamtape/direct?file=${Uri.encodeComponent(rec.movieId)}",
      rating: 9.2,
      releaseYear: 2025,
      duration: rec.formattedDuration,
      maturityRating: rec.language,
      qualityBadge: rec.qualityBadge,
      genres: const ["Cinema"],
      director: "Niooo M Catalog",
      cast: const [],
      watchProgress: rec.progressRatio,
    );
  }

  MovieItem _resolveMovieForDownload(DownloadTaskItem task) {
    for (final m in widget.movies) {
      if (m.id == task.movieId) return m;
    }
    return MovieItem(
      id: task.movieId,
      streamtapeId: task.movieId,
      title: task.title,
      language: task.language,
      tagline: "${task.language} · ${task.qualityBadge}",
      synopsis: "Downloaded offline movie (${task.formattedSizeProgress}).",
      posterUrl: task.posterUrl,
      backdropUrl: task.backdropUrl,
      embedUrl: "https://streamtape.com/e/${task.movieId}/",
      downloadUrl: task.downloadPageUrl,
      videoStreamUrl: task.localFilePath.isNotEmpty
          ? task.localFilePath
          : task.directMp4Url,
      sizeBytes: task.totalBytes,
      rating: 9.3,
      releaseYear: 2025,
      duration: task.formattedSizeProgress,
      maturityRating: task.language,
      qualityBadge: task.qualityBadge,
      genres: const ["Offline Cinema"],
      director: "Niooo M Offline",
      cast: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = WatchHistoryDownloadService.instance;
    final historyList = service.historyList;
    final downloadList = service.downloadList;
    final activeDownloadsCount = service.activeDownloadsCount;

    return GlassContainer(
      margin: EdgeInsets.zero,
      borderRadius: 0,
      blur: 28,
      border: const Border(),
      boxShadow: const [],
      backgroundColor: const Color(0xFF030706),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header: Profile, Watch History & Download Manager Summary
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E676), Color(0xFF059669)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.35),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Color(0xFF03120D),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "My Cinema Profile",
                        style: TextStyle(
                          color: Color(0xFFF0FDF4),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "${historyList.length} Watched · ${downloadList.length} Offline Downloads",
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selectedSegment == 0 && historyList.isNotEmpty)
                  GestureDetector(
                    onTap: () => service.clearAllWatchHistory(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        "Clear History",
                        style: TextStyle(
                          color: Color(0xFFFF6B6B),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Segmented Switcher: [ Continue Watching & History ] | [ Offline Downloads Manager ]
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF071512),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF00E676).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedSegment = 0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: _selectedSegment == 0
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF00E676),
                                    Color(0xFF10B981),
                                  ],
                                )
                              : null,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 16,
                              color: _selectedSegment == 0
                                  ? const Color(0xFF03120D)
                                  : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "Continue & History (${historyList.length})",
                              style: TextStyle(
                                color: _selectedSegment == 0
                                    ? const Color(0xFF03120D)
                                    : const Color(0xFFF0FDF4),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedSegment = 1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: _selectedSegment == 1
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF00E676),
                                    Color(0xFF10B981),
                                  ],
                                )
                              : null,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.download_for_offline_rounded,
                              size: 16,
                              color: _selectedSegment == 1
                                  ? const Color(0xFF03120D)
                                  : const Color(0xFF00E676),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              activeDownloadsCount > 0
                                  ? "Downloads ($activeDownloadsCount Active)"
                                  : "Offline Downloads (${downloadList.length})",
                              style: TextStyle(
                                color: _selectedSegment == 1
                                    ? const Color(0xFF03120D)
                                    : const Color(0xFFF0FDF4),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Main Content Area
          Expanded(
            child: _selectedSegment == 0
                ? _buildContinueAndHistoryTab(historyList, service)
                : _buildDownloadsManagerTab(downloadList, service),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueAndHistoryTab(
    List<WatchHistoryRecord> historyList,
    WatchHistoryDownloadService service,
  ) {
    if (historyList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 90),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00E676).withValues(alpha: 0.12),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.play_lesson_rounded,
                  color: Color(0xFF00E676),
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "No Watch History Yet",
                style: TextStyle(
                  color: Color(0xFFF0FDF4),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "When you play any movie or web series, Niooo M automatically saves your exact second so it resumes right where you left off after extracting the direct link.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: historyList.length,
      itemBuilder: (context, index) {
        final rec = historyList[index];
        final movie = _resolveMovieForHistory(rec);
        final pct = (rec.progressRatio * 100).round().clamp(1, 100);

        return GestureDetector(
          onTap: () => widget.onPlayMovie?.call(movie),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.06),
                  const Color(0xFF081713).withValues(alpha: 0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF00E676).withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              children: [
                // 16:9 Thumbnail with Exact Timestamp Overlay & Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 136,
                    height: 84,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          rec.backdropUrl.isNotEmpty
                              ? rec.backdropUrl
                              : rec.posterUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFF0A1815),
                          ),
                        ),
                        Container(
                          color: Colors.black.withValues(alpha: 0.30),
                        ),
                        Center(
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00E676),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Color(0xFF03120D),
                              size: 22,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.82),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "${rec.formattedPosition} / ${rec.formattedDuration}",
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: rec.progressRatio.clamp(0.04, 1.0),
                            minHeight: 3.5,
                            backgroundColor: Colors.black54,
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
                        rec.title,
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
                        "${rec.language} · ${rec.qualityBadge}",
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676)
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF00E676)
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              "Resume at ${rec.formattedPosition} ($pct%)",
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => service.removeHistoryItem(rec.movieId),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                color: Color(0xFF94A3B8),
                                size: 18,
                              ),
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
      },
    );
  }

  Widget _buildDownloadsManagerTab(
    List<DownloadTaskItem> downloadList,
    WatchHistoryDownloadService service,
  ) {
    if (downloadList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 90),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00E676).withValues(alpha: 0.12),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.download_for_offline_outlined,
                  color: Color(0xFF00E676),
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "No Offline Downloads Yet",
                style: TextStyle(
                  color: Color(0xFFF0FDF4),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Tap the Download button inside any movie player to open the download link in our integrated Custom Chrome Tab and track real-time download progress right here & in your Android Notification bar.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: downloadList.length,
      itemBuilder: (context, index) {
        final task = downloadList[index];
        final movie = _resolveMovieForDownload(task);
        final pct = (task.progress * 100).round().clamp(0, 100);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.06),
                const Color(0xFF081713).withValues(alpha: 0.88),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: task.isCompleted
                  ? const Color(0xFF00E676).withValues(alpha: 0.45)
                  : const Color(0xFF00E676).withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      task.posterUrl.isNotEmpty
                          ? task.posterUrl
                          : task.backdropUrl,
                      width: 62,
                      height: 82,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 62,
                        height: 82,
                        color: const Color(0xFF0A1815),
                        child: const Icon(
                          Icons.movie_rounded,
                          color: Color(0xFF00E676),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: task.isCompleted
                                    ? const Color(0xFF00E676)
                                    : const Color(0xFF00E676)
                                        .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                task.isCompleted
                                    ? "OFFLINE READY"
                                    : task.isDownloading
                                        ? "DOWNLOADING $pct%"
                                        : task.status.toUpperCase(),
                                style: TextStyle(
                                  color: task.isCompleted
                                      ? const Color(0xFF03120D)
                                      : const Color(0xFF00E676),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                task.qualityBadge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF0FDF4),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${task.formattedSizeProgress} · ${task.speedLabel}",
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: task.isCompleted
                      ? 1.0
                      : task.progress.clamp(0.03, 1.0),
                  minHeight: 5.5,
                  backgroundColor: Colors.white12,
                  color: const Color(0xFF00E676),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // Play Offline / Stream Button
                  Expanded(
                    child: GestureDetector(
                      onTap: () => widget.onPlayMovie?.call(movie),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00E676), Color(0xFF10B981)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.play_arrow_rounded,
                              color: Color(0xFF03120D),
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              task.isCompleted
                                  ? "Play Offline Video"
                                  : "Open in Player",
                              style: const TextStyle(
                                color: Color(0xFF03120D),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Open in Custom Chrome Tab Button
                  if (task.downloadPageUrl.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        MiniChromeBrowserService.openAdUrlBelowPlayer(
                          context,
                          task.downloadPageUrl,
                          title: "Download · ${task.title}",
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                const Color(0xFF00E676).withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.public_rounded,
                              color: Color(0xFF00E676),
                              size: 15,
                            ),
                            SizedBox(width: 4),
                            Text(
                              "Chrome Tab",
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
                  const SizedBox(width: 8),
                  // Retry if failed/paused
                  if (!task.isCompleted && !task.isDownloading)
                    GestureDetector(
                      onTap: () {
                        service.startMovieDownload(
                          movieId: task.movieId,
                          title: task.title,
                          posterUrl: task.posterUrl,
                          backdropUrl: task.backdropUrl,
                          qualityBadge: task.qualityBadge,
                          language: task.language,
                          streamtapeId: task.movieId,
                          embedUrl: "https://streamtape.com/e/${task.movieId}/",
                          downloadUrl: task.downloadPageUrl,
                          estimatedSizeBytes: task.totalBytes,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF00E676).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.refresh_rounded,
                          color: Color(0xFF00E676),
                          size: 18,
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  // Cancel / Delete Download
                  GestureDetector(
                    onTap: () => service.cancelOrDeleteDownload(task.movieId),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFFF6B6B),
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
