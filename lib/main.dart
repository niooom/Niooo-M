import "dart:async";
import "dart:ui";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "models/movie_models.dart";
import "pages/welcome_page.dart";
import "pages/home_movies_page.dart";
import "pages/explore_page.dart";
import "pages/watchlist_page.dart";
import "pages/profile_settings_page.dart";
import "pages/movie_player_page.dart";
import "widgets/fluid_glass_bottom_bar.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    // Prevent uncaught rendering/network image errors from crashing the runtime
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    return true;
  };
  runApp(const NioooMovieApp());
}

class NioooMovieApp extends StatelessWidget {
  const NioooMovieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "niooo",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF030706),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00E676),
          secondary: const Color(0xFF10B981),
          surface: const Color(0xFF0A1412).withValues(alpha: 0.72),
        ),
        fontFamily: "Roboto",
        useMaterial3: true,
      ),
      home: const NioooCinemaMainScreen(),
    );
  }
}

/// Snapshot of a single screen/page state in the navigation history stack
/// so pressing Back steps through every visited movie, page, and tab smoothly.
class _NavHistorySnapshot {
  final int navIndex;
  final String? playingMovieId;
  final bool hasDismissedWelcome;

  const _NavHistorySnapshot({
    required this.navIndex,
    required this.playingMovieId,
    required this.hasDismissedWelcome,
  });

  bool matches(_NavHistorySnapshot other) {
    return navIndex == other.navIndex &&
        playingMovieId == other.playingMovieId &&
        hasDismissedWelcome == other.hasDismissedWelcome;
  }
}

class NioooCinemaMainScreen extends StatefulWidget {
  const NioooCinemaMainScreen({super.key});

  @override
  State<NioooCinemaMainScreen> createState() => _NioooCinemaMainScreenState();
}

class _NioooCinemaMainScreenState extends State<NioooCinemaMainScreen>
    with WidgetsBindingObserver {
  late List<MovieItem> _movies;
  List<SeriesCatalogItem> _seriesList = [];
  final Set<String> _likedMovieIds = {};
  final Set<String> _watchlistIds = {};

  bool _hasDismissedWelcome =
      true; // Direct movie platform access without login
  bool _isSyncingCatalog = false;
  bool _isPlayerFullscreen = false;
  int _activeNavIndex = 0; // 0: Home, 1: Explore, 2: Watchlist, 3: Profile
  String? _activePlayingMovieId;
  Timer? _catalogAutoSyncTimer;

  // Navigation history stack for sequential, smooth back-navigation
  final List<_NavHistorySnapshot> _backHistoryStack = [];
  DateTime? _lastRootBackPressTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _movies = MovieCatalogData.loadCachedVerifiedCatalog();
    _seriesList = MovieCatalogData.latestSeriesList;
    _syncFromPublicCatalogApi(forceRefresh: true);

    // Real-time background sync with Niooo M Public API every 18 seconds
    _catalogAutoSyncTimer = Timer.periodic(
      const Duration(seconds: 18),
      (_) => _syncFromPublicCatalogApi(forceRefresh: true),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _catalogAutoSyncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncFromPublicCatalogApi(forceRefresh: true);
    }
  }

  _NavHistorySnapshot get _currentSnapshot => _NavHistorySnapshot(
        navIndex: _activeNavIndex,
        playingMovieId: _activePlayingMovieId,
        hasDismissedWelcome: _hasDismissedWelcome,
      );

  void _pushCurrentStateToHistory() {
    final snap = _currentSnapshot;
    if (_backHistoryStack.isEmpty || !_backHistoryStack.last.matches(snap)) {
      _backHistoryStack.add(snap);
      if (_backHistoryStack.length > 40) {
        _backHistoryStack.removeAt(0);
      }
    }
  }

  /// Navigates to a new state while recording the current state onto the history stack
  void _navigateTo({
    int? navIndex,
    String? playingMovieId,
    bool clearPlayingMovie = false,
    bool? hasDismissedWelcome,
  }) {
    final targetNavIndex = navIndex ?? _activeNavIndex;
    final targetMovieId =
        clearPlayingMovie ? null : (playingMovieId ?? _activePlayingMovieId);
    final targetWelcome = hasDismissedWelcome ?? _hasDismissedWelcome;

    final nextSnap = _NavHistorySnapshot(
      navIndex: targetNavIndex,
      playingMovieId: targetMovieId,
      hasDismissedWelcome: targetWelcome,
    );

    if (_currentSnapshot.matches(nextSnap)) return;

    setState(() {
      _pushCurrentStateToHistory();
      _activeNavIndex = targetNavIndex;
      _activePlayingMovieId = targetMovieId;
      _hasDismissedWelcome = targetWelcome;
    });
  }

  /// Handles hardware/gesture Back button and in-app Back actions sequentially & smoothly
  bool _handleSequentialBack() {
    while (_backHistoryStack.isNotEmpty) {
      final previous = _backHistoryStack.removeLast();
      if (!previous.matches(_currentSnapshot)) {
        setState(() {
          _activeNavIndex = previous.navIndex;
          _activePlayingMovieId = previous.playingMovieId;
          _hasDismissedWelcome = previous.hasDismissedWelcome;
        });
        return true;
      }
    }

    if (_activePlayingMovieId != null) {
      setState(() => _activePlayingMovieId = null);
      return true;
    }
    if (!_hasDismissedWelcome) {
      setState(() => _hasDismissedWelcome = true);
      return true;
    }
    if (_activeNavIndex != 0) {
      setState(() => _activeNavIndex = 0);
      return true;
    }

    return false;
  }

  void _onSystemPopInvokedWithResult(bool didPop, Object? result) {
    if (didPop) return;

    // If a movie is currently playing in fullscreen or landscape on Android,
    // exit fullscreen and return to portrait mode first before leaving the player!
    if (_activePlayingMovieId != null &&
        (_isPlayerFullscreen ||
            MediaQuery.of(context).orientation == Orientation.landscape)) {
      setState(() => _isPlayerFullscreen = false);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      return;
    }

    final handled = _handleSequentialBack();
    if (handled) return;

    // At root Home screen: require double-press within 2 seconds to exit app
    final now = DateTime.now();
    if (_lastRootBackPressTime == null ||
        now.difference(_lastRootBackPressTime!) > const Duration(seconds: 2)) {
      _lastRootBackPressTime = now;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF071A14),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: const Color(0xFF00E676).withValues(alpha: 0.45),
            ),
          ),
          content: const Text(
            "Press back again to exit Niooo M",
            style: TextStyle(
              color: Color(0xFFF0FDF4),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    SystemNavigator.pop();
  }

  Future<void> _syncFromPublicCatalogApi({bool forceRefresh = false}) async {
    if (_isSyncingCatalog) return;
    setState(() => _isSyncingCatalog = true);

    final snapshot = await MovieCatalogData.fetchLiveCatalogSnapshot();
    if (!mounted) return;

    if (snapshot != null && snapshot.allItems.isNotEmpty) {
      // Preserve watchProgress & comments for any movies already in state
      final Map<String, MovieItem> existingById = {
        for (final m in _movies) m.id: m,
      };

      final List<MovieItem> merged = snapshot.allItems.map((item) {
        final prev = existingById[item.id];
        if (prev != null) {
          return item.copyWith(
            watchProgress: prev.watchProgress,
            likesCount: prev.likesCount,
            sharesCount: prev.sharesCount,
            comments: prev.comments.length > item.comments.length
                ? prev.comments
                : item.comments,
          );
        }
        return item;
      }).toList();

      setState(() {
        _movies = merged;
        _seriesList = snapshot.seriesList;
        _isSyncingCatalog = false;
        if (_activePlayingMovieId != null &&
            !_movies.any((m) => m.id == _activePlayingMovieId)) {
          _activePlayingMovieId = null;
        }
      });
    } else {
      setState(() => _isSyncingCatalog = false);
    }
  }

  MovieItem? get _activePlayingMovie {
    if (_activePlayingMovieId == null) return null;
    for (final m in _movies) {
      if (m.id == _activePlayingMovieId) return m;
    }
    return null;
  }

  void _toggleWatchlist(String movieId) {
    setState(() {
      if (_watchlistIds.contains(movieId)) {
        _watchlistIds.remove(movieId);
      } else {
        _watchlistIds.add(movieId);
      }
    });
  }

  void _toggleLikeMovie(String movieId) {
    setState(() {
      final isLiked = _likedMovieIds.contains(movieId);
      if (isLiked) {
        _likedMovieIds.remove(movieId);
      } else {
        _likedMovieIds.add(movieId);
      }
      _movies = _movies.map((m) {
        if (m.id != movieId) return m;
        return m.copyWith(
          likesCount: isLiked ? (m.likesCount - 1) : (m.likesCount + 1),
        );
      }).toList();
    });
  }

  void _shareMovie(String movieId) {
    setState(() {
      _movies = _movies.map((m) {
        if (m.id != movieId) return m;
        return m.copyWith(sharesCount: m.sharesCount + 1);
      }).toList();
    });
  }

  void _addMovieComment(String movieId, String commentText) {
    final newComment = MovieComment(
      id: "c_${DateTime.now().millisecondsSinceEpoch}",
      authorName: "Cinema Viewer",
      authorHandle: "@niooo_viewer",
      avatarUrl:
          "https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&w=200&q=80",
      comment: commentText,
      timeAgo: "Just now",
      likes: 1,
    );

    setState(() {
      _movies = _movies.map((m) {
        if (m.id != movieId) return m;
        return m.copyWith(comments: [newComment, ...m.comments]);
      }).toList();
    });
  }

  void _openMoviePlayer(MovieItem movie) {
    _navigateTo(playingMovieId: movie.id);
  }

  void _updateMovieProgress(String movieId, double progress) {
    setState(() {
      _movies = _movies.map((m) {
        if (m.id != movieId) return m;
        return m.copyWith(watchProgress: progress.clamp(0.0, 1.0));
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final playingMovie = _activePlayingMovie;
    final mediaOrientation = MediaQuery.of(context).orientation;
    final bool hideBarsForFullscreen = playingMovie != null &&
        (_isPlayerFullscreen || mediaOrientation == Orientation.landscape);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onSystemPopInvokedWithResult,
      child: Scaffold(
        backgroundColor: const Color(0xFF030706),
        body: Stack(
          children: [
            // Ambient Deep Emerald & Obsidian Cinema Glow
            Positioned(
              top: -120,
              left: -90,
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF00E676).withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -140,
              right: -90,
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF059669).withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Main Content Area
            SafeArea(
              top: !hideBarsForFullscreen,
              bottom: !hideBarsForFullscreen,
              left: !hideBarsForFullscreen,
              right: !hideBarsForFullscreen,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: !_hasDismissedWelcome
                    ? WelcomePage(
                        onGetStarted: () {
                          _navigateTo(hasDismissedWelcome: true);
                        },
                      )
                    : playingMovie != null
                        ? MoviePlayerPage(
                            key: ValueKey("player_${playingMovie.id}"),
                            movie: playingMovie,
                            allMovies: _movies,
                            isLiked: _likedMovieIds.contains(playingMovie.id),
                            isBookmarked:
                                _watchlistIds.contains(playingMovie.id),
                            onBack: () {
                              _handleSequentialBack();
                            },
                            onFullscreenChanged: (isFull) {
                              if (_isPlayerFullscreen != isFull) {
                                setState(() => _isPlayerFullscreen = isFull);
                              }
                            },
                            onToggleLike: () =>
                                _toggleLikeMovie(playingMovie.id),
                            onToggleBookmark: () =>
                                _toggleWatchlist(playingMovie.id),
                            onShareMovie: () => _shareMovie(playingMovie.id),
                            onAddComment: (txt) =>
                                _addMovieComment(playingMovie.id, txt),
                            onSelectOtherMovie: (nextMovie) {
                              _openMoviePlayer(nextMovie);
                            },
                            onUpdateProgress: (p) =>
                                _updateMovieProgress(playingMovie.id, p),
                          )
                        : _buildMainTabs(),
              ),
            ),

            // Floating Liquid Glass Bottom Navigation Bar (hidden when Welcome or MoviePlayer is open)
            if (_hasDismissedWelcome && playingMovie == null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: FluidGlassBottomBar(
                  selectedIndex: _activeNavIndex,
                  unreadChatsCount: _watchlistIds.length,
                  onTabSelected: (idx) {
                    _navigateTo(navIndex: idx, clearPlayingMovie: true);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainTabs() {
    switch (_activeNavIndex) {
      case 0:
        return HomeMoviesPage(
          key: const ValueKey("tab_home"),
          movies: _movies,
          seriesList: _seriesList,
          watchlistIds: _watchlistIds,
          onPlayMovie: _openMoviePlayer,
          onToggleWatchlist: _toggleWatchlist,
          onOpenWatchlistTab: () =>
              _navigateTo(navIndex: 2, clearPlayingMovie: true),
          onOpenProfileTab: () =>
              _navigateTo(navIndex: 3, clearPlayingMovie: true),
          onRefreshStreamtape: () =>
              _syncFromPublicCatalogApi(forceRefresh: true),
          isSyncingStreamtape: _isSyncingCatalog,
        );
      case 1:
        return ExplorePage(
          key: const ValueKey("tab_explore"),
          movies: _movies,
          watchlistIds: _watchlistIds,
          onPlayMovie: _openMoviePlayer,
          onToggleWatchlist: _toggleWatchlist,
        );
      case 2:
        return WatchlistPage(
          key: const ValueKey("tab_watchlist"),
          movies: _movies,
          watchlistIds: _watchlistIds,
          onPlayMovie: _openMoviePlayer,
          onToggleWatchlist: _toggleWatchlist,
          onExploreMovies: () =>
              _navigateTo(navIndex: 1, clearPlayingMovie: true),
        );
      case 3:
      default:
        return const ProfileSettingsPage(
          key: ValueKey("tab_profile"),
        );
    }
  }
}
