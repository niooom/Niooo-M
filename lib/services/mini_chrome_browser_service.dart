import "dart:async";
import "package:flutter/material.dart";
import "package:flutter_custom_tabs/flutter_custom_tabs.dart" as custom_tabs;
import "package:url_launcher/url_launcher.dart" as url_launcher;
import "platform_bridge.dart";
import "watch_history_download_service.dart";

/// Google Chrome Custom Tabs (Mini Chrome In-App Browser) Service for Niooo M.
///
/// 1. For Ads / External links: opens inside Partial Chrome Custom Tabs below the 16:9 video player.
/// 2. For Movie Downloads (`openDownloadPortalBelowPlayer`):
///    - Does NOT start any download when the user merely clicks the "Download" button in the player!
///    - Opens the interactive Custom Chrome Tab below the 16:9 video player so the user can view
///      the download page and its ads normally.
///    - Intercepts/detects in real time ONLY when the user actually clicks the download button
///      inside the Custom Tab (`get_video` / `dl=1` / video binary stream or Android System
///      `DownloadManager` active download), and ONLY THEN triggers `WatchHistoryDownloadService`
///      and the Native C++17 Download Engine.
class MiniChromeBrowserService {
  MiniChromeBrowserService._();

  /// Calculates the exact height from the bottom of the screen up to the bottom
  /// edge of the top 16:9 video player so Chrome Custom Tabs never covers the player.
  static double calculateBelowPlayerHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final topPadding = media.padding.top;
    final videoPlayerHeight = screenWidth * (9.0 / 16.0);
    final availableBelowPlayer =
        screenHeight - topPadding - videoPlayerHeight - 4.0;
    return availableBelowPlayer.clamp(240.0, screenHeight * 0.72);
  }

  /// Opens the Movie's API `download_url` inside the Custom Chrome Tab below the video player
  /// WITHOUT starting any premature/demo download.
  /// Real-time download tracking begins ONLY when a real download is initiated inside the Custom Tab!
  static Future<void> openDownloadPortalBelowPlayer(
    BuildContext context, {
    required String movieId,
    required String title,
    required String posterUrl,
    required String backdropUrl,
    required String qualityBadge,
    required String language,
    required String apiDownloadUrl,
    required int estimatedSizeBytes,
  }) async {
    final cleanUrl = apiDownloadUrl.trim();
    if (cleanUrl.isEmpty) return;

    final Uri? uri = Uri.tryParse(
      cleanUrl.startsWith("http://") || cleanUrl.startsWith("https://")
          ? cleanUrl
          : "https://$cleanUrl",
    );
    if (uri == null) return;

    // Arm the real-time Custom Tab download detector (does NOT start downloading or show any progress yet).
    WatchHistoryDownloadService.instance.preparePendingCustomTabDownload(
      movieId: movieId,
      title: title,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      qualityBadge: qualityBadge,
      language: language,
      apiDownloadUrl: uri.toString(),
      estimatedSizeBytes: estimatedSizeBytes,
    );

    final sheetHeight = calculateBelowPlayerHeight(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _InteractiveCustomTabDownloadSheet(
          initialUrl: uri.toString(),
          movieId: movieId,
          movieTitle: title,
          sheetHeight: sheetHeight,
        );
      },
    );
  }

  /// Opens an Advertisement / External URL inside Google's Partial Chrome Custom Tab
  /// strictly below the video player area (never covering the top 16:9 player).
  static Future<void> openAdUrlBelowPlayer(
    BuildContext context,
    String rawUrl, {
    String? title,
  }) async {
    final cleanUrl = rawUrl.trim();
    if (cleanUrl.isEmpty) return;

    final Uri? uri = Uri.tryParse(
      cleanUrl.startsWith("http://") || cleanUrl.startsWith("https://")
          ? cleanUrl
          : "https://$cleanUrl",
    );
    if (uri == null) return;

    final sheetHeight = calculateBelowPlayerHeight(context);

    if (PlatformBridge.isWeb) {
      await _openWebMiniChromeBelowPlayer(
        context,
        uri.toString(),
        title: title ?? uri.host,
        sheetHeight: sheetHeight,
      );
      return;
    }

    try {
      await custom_tabs.launchUrl(
        uri,
        customTabsOptions: custom_tabs.CustomTabsOptions(
          colorSchemes: custom_tabs.CustomTabsColorSchemes.defaults(
            toolbarColor: const Color(0xFF061510),
            navigationBarColor: const Color(0xFF030706),
            navigationBarDividerColor: const Color(0xFF00E676),
          ),
          shareState: custom_tabs.CustomTabsShareState.on,
          urlBarHidingEnabled: true,
          showTitle: true,
          closeButton: custom_tabs.CustomTabsCloseButton(
            icon: custom_tabs.CustomTabsCloseButtonIcons.back,
          ),
          partial: custom_tabs.PartialCustomTabsConfiguration.adaptiveSheet(
            initialHeight: sheetHeight,
            initialWidth: MediaQuery.of(context).size.width,
            activityHeightResizeBehavior:
                custom_tabs.CustomTabsActivityHeightResizeBehavior.fixed,
            cornerRadius: 18,
          ),
          browser: const custom_tabs.CustomTabsBrowserConfiguration(
            prefersDefaultBrowser: false,
            fallbackCustomTabs: [
              "com.android.chrome",
              "com.chrome.beta",
              "com.chrome.dev",
              "org.mozilla.firefox",
              "com.microsoft.emmx",
            ],
          ),
        ),
        safariVCOptions: const custom_tabs.SafariViewControllerOptions(
          preferredBarTintColor: Color(0xFF061510),
          preferredControlTintColor: Color(0xFF00E676),
          barCollapsingEnabled: true,
          dismissButtonStyle:
              custom_tabs.SafariViewControllerDismissButtonStyle.close,
        ),
      );
    } catch (_) {
      try {
        await url_launcher.launchUrl(
          uri,
          mode: url_launcher.LaunchMode.inAppBrowserView,
          browserConfiguration: const url_launcher.BrowserConfiguration(
            showTitle: true,
          ),
        );
      } catch (_) {}
    }
  }

  static Future<void> _openWebMiniChromeBelowPlayer(
    BuildContext context,
    String url, {
    required String title,
    required double sheetHeight,
  }) async {
    final viewType =
        "niooo-mini-chrome-${DateTime.now().microsecondsSinceEpoch}";
    PlatformBridge.registerIframeFactory(viewType, url);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: sheetHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF061510),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border.all(
              color: const Color(0xFF00E676).withValues(alpha: 0.45),
              width: 1.2,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF04100C),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(18)),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: "Close Browser",
                    ),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        color: Color(0xFF00E676),
                        size: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF00E676).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.public_rounded,
                            color: Color(0xFF00E676),
                            size: 12,
                          ),
                          SizedBox(width: 4),
                          Text(
                            "Chrome Custom Tab",
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PlatformBridge.buildEmbeddedPlayer(
                  viewType: viewType,
                  embedSrc: url,
                  backdropUrl: "",
                  title: title,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InteractiveCustomTabDownloadSheet extends StatefulWidget {
  final String initialUrl;
  final String movieId;
  final String movieTitle;
  final double sheetHeight;

  const _InteractiveCustomTabDownloadSheet({
    required this.initialUrl,
    required this.movieId,
    required this.movieTitle,
    required this.sheetHeight,
  });

  @override
  State<_InteractiveCustomTabDownloadSheet> createState() =>
      _InteractiveCustomTabDownloadSheetState();
}

class _InteractiveCustomTabDownloadSheetState
    extends State<_InteractiveCustomTabDownloadSheet> {
  late String _currentUrl;
  bool _downloadTriggeredInTab = false;
  late final String _webViewType;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _webViewType =
        "niooo-dl-custom-tab-${DateTime.now().microsecondsSinceEpoch}";
    if (PlatformBridge.isWeb) {
      PlatformBridge.registerIframeFactory(_webViewType, widget.initialUrl);
    }
    WatchHistoryDownloadService.instance.addListener(_onDownloadServiceChanged);
  }

  @override
  void dispose() {
    WatchHistoryDownloadService.instance
        .removeListener(_onDownloadServiceChanged);
    super.dispose();
  }

  void _onDownloadServiceChanged() {
    if (!mounted) return;
    final task =
        WatchHistoryDownloadService.instance.getDownloadTask(widget.movieId);
    final isNowActive =
        task != null && (task.isDownloading || task.isCompleted);
    if (isNowActive != _downloadTriggeredInTab) {
      setState(() {
        _downloadTriggeredInTab = isNowActive;
      });
    } else if (isNowActive) {
      setState(() {});
    }
  }

  void _handleRealDownloadDetectedInTab(
    String detectedDownloadUrl,
    String userAgent,
    String cookies,
  ) {
    if (!mounted) return;
    setState(() {
      _downloadTriggeredInTab = true;
    });
    WatchHistoryDownloadService.instance.onCustomTabDownloadDetected(
      movieId: widget.movieId,
      detectedDownloadUrl: detectedDownloadUrl,
      userAgent: userAgent,
      cookies: cookies,
    );
  }

  Future<void> _launchExternalChromeCustomTab() async {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null) return;
    try {
      await custom_tabs.launchUrl(
        uri,
        customTabsOptions: custom_tabs.CustomTabsOptions(
          colorSchemes: custom_tabs.CustomTabsColorSchemes.defaults(
            toolbarColor: const Color(0xFF061510),
            navigationBarColor: const Color(0xFF030706),
            navigationBarDividerColor: const Color(0xFF00E676),
          ),
          shareState: custom_tabs.CustomTabsShareState.on,
          urlBarHidingEnabled: true,
          showTitle: true,
          partial: custom_tabs.PartialCustomTabsConfiguration.adaptiveSheet(
            initialHeight: widget.sheetHeight,
            initialWidth: MediaQuery.of(context).size.width,
            activityHeightResizeBehavior:
                custom_tabs.CustomTabsActivityHeightResizeBehavior.fixed,
            cornerRadius: 18,
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final activeTask =
        WatchHistoryDownloadService.instance.getDownloadTask(widget.movieId);
    final bool isDownloadingOrDone = activeTask != null &&
        (activeTask.isDownloading || activeTask.isCompleted);

    return Container(
      height: widget.sheetHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF061510),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(
          color: const Color(0xFF00E676).withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          // Custom Chrome Tab Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF04100C),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  tooltip: "Close Custom Tab",
                ),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Color(0xFF00E676),
                    size: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Download · ${widget.movieTitle}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _currentUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!PlatformBridge.isWeb)
                  GestureDetector(
                    onTap: _launchExternalChromeCustomTab,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF00E676).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_in_browser_rounded,
                            color: Color(0xFF00E676),
                            size: 13,
                          ),
                          SizedBox(width: 4),
                          Text(
                            "Chrome Tab",
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Status Banner inside Custom Tab:
          // Shows real-time download progress ONLY AFTER the user clicks the download button inside the tab!
          if (isDownloadingOrDone)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF07231A),
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        activeTask.isCompleted
                            ? Icons.check_circle_rounded
                            : Icons.downloading_rounded,
                        color: const Color(0xFF00E676),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          activeTask.isCompleted
                              ? "Download Complete (${activeTask.formattedSizeProgress})"
                              : "Real-Time Download Active · ${(activeTask.progress * 100).round()}% (${activeTask.speedLabel})",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF0FDF4),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        activeTask.formattedSizeProgress,
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: activeTask.isCompleted
                          ? 1.0
                          : activeTask.progress.clamp(0.01, 1.0),
                      minHeight: 4,
                      backgroundColor: Colors.white12,
                      color: const Color(0xFF00E676),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF05140F),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    color: Color(0xFF00E676),
                    size: 14,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Complete the page steps/ads below and tap Download inside the page to start real-time download.",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Interactive Custom Tab Browser Area
          Expanded(
            child: PlatformBridge.buildInteractiveDownloadCustomTab(
              initialUrl: widget.initialUrl,
              viewType: _webViewType,
              onUrlChanged: (url) {
                if (!mounted) return;
                setState(() {
                  _currentUrl = url;
                });
              },
              onDownloadTriggeredInTab: _handleRealDownloadDetectedInTab,
            ),
          ),
        ],
      ),
    );
  }
}
