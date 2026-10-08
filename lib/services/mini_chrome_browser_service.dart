import "package:flutter/material.dart";
import "package:flutter_custom_tabs/flutter_custom_tabs.dart" as custom_tabs;
import "package:url_launcher/url_launcher.dart" as url_launcher;
import "platform_bridge.dart";

/// Google Chrome Custom Tabs (Mini Chrome In-App Browser) Service for Niooo M.
/// ONLY opens external/advertisement links inside the Chrome Custom Tabs
/// mini-browser positioned right below the 16:9 video player so the video
/// player is NEVER covered.
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

    // On Android APK: Launch Google Chrome Custom Tabs strictly sized to the area
    // below the 16:9 video player (fixed height so it never covers the video player).
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
                      tooltip: "Close Ad Browser",
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
