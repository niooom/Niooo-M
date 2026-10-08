import "package:flutter/material.dart";
import "../models/movie_models.dart";
import "../widgets/glass_container.dart";

// =============================================================================
// PROFILE PAGE — MINIMAL "COMING SOON" PLACEHOLDER (NO FIREBASE / NO LOGIN / NO ADMIN PANEL)
// =============================================================================
class ProfileSettingsPage extends StatelessWidget {
  final List<MovieItem> movies;
  final String displayName;
  final String handle;
  final String membershipTier;
  final String streamQuality;
  final bool dolbyAtmosEnabled;
  final bool autoplayTrailers;
  final int watchlistCount;
  final int watchedCount;
  final ValueChanged<String>? onQualityChanged;
  final ValueChanged<bool>? onToggleDolbyAtmos;
  final ValueChanged<bool>? onToggleAutoplay;
  final VoidCallback? onReturnToWelcome;
  final VoidCallback? onOpenFullScreenAdminPanel;

  const ProfileSettingsPage({
    super.key,
    this.movies = const [],
    this.displayName = "",
    this.handle = "",
    this.membershipTier = "",
    this.streamQuality = "4K IMAX HDR",
    this.dolbyAtmosEnabled = true,
    this.autoplayTrailers = true,
    this.watchlistCount = 0,
    this.watchedCount = 0,
    this.onQualityChanged,
    this.onToggleDolbyAtmos,
    this.onToggleAutoplay,
    this.onReturnToWelcome,
    this.onOpenFullScreenAdminPanel,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      margin: EdgeInsets.zero,
      borderRadius: 0,
      blur: 28,
      border: const Border(),
      boxShadow: const [],
      backgroundColor: const Color(0xFF030706),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00E676).withValues(alpha: 0.12),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.38),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: Color(0xFF00E676),
                  size: 36,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Coming Soon",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFF0FDF4),
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
