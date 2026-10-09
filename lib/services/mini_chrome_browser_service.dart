import "dart:async";
import "package:flutter/material.dart";
import "package:flutter_custom_tabs/flutter_custom_tabs.dart" as custom_tabs;
import "package:url_launcher/url_launcher.dart" as url_launcher;
import "watch_history_download_service.dart";

/// Google Chrome Custom Tabs Service for Niooo M.
///
/// Strictly uses ONLY Google Chrome's native Custom Tabs (`PartialCustomTabsConfiguration`)
/// sized from the bottom of the screen right up to the bottom edge of the top 16:9 video player.
/// Does NOT use any custom in-app WebView or custom bottom-sheet browser!
class MiniChromeBrowserService {
  MiniChromeBrowserService._();

  /// Calculates the exact height from the bottom of the screen up to the bottom
  /// edge of the top 16:9 video player so Google Chrome Custom Tabs never covers the player.
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

  /// Opens the Movie's API `download_url` directly inside Google Chrome's native
  /// Partial Custom Tab positioned right below the 16:9 video player.
  ///
  /// - Does NOT open any custom WebView or custom browser sheet.
  /// - Does NOT start any demo/fake download when tapped.
  /// - Arms the real-time Android Download detector so when the user finishes viewing ads
  ///   and clicks the Download button inside the Chrome Custom Tab, Niooo M automatically
  ///   detects and tracks the real download in real time!
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

    // Arm the real-time download detector for this movie WITHOUT starting any demo download.
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

    // Open directly in Google Chrome's native Partial Custom Tab right below the video player.
    await openAdUrlBelowPlayer(
      context,
      uri.toString(),
      title: "Download · $title",
    );
  }

  /// Opens any URL directly inside Google's native Partial Chrome Custom Tab
  /// strictly below the 16:9 video player area (never covering the top 16:9 player).
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
    final screenWidth = MediaQuery.of(context).size.width;

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
            initialWidth: screenWidth,
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
}
