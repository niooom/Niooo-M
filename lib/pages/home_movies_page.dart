import "dart:async";
import "dart:ui";
import "package:flutter/material.dart";
import "../models/movie_models.dart";
import "../widgets/glass_container.dart";

class HomeMoviesPage extends StatefulWidget {
  final List<MovieItem> movies;
  final List<SeriesCatalogItem> seriesList;
  final Set<String> watchlistIds;
  final ValueChanged<MovieItem> onPlayMovie;
  final ValueChanged<String> onToggleWatchlist;
  final VoidCallback onOpenWatchlistTab;
  final VoidCallback onOpenProfileTab;
  final VoidCallback? onRefreshStreamtape;
  final bool isSyncingStreamtape;

  const HomeMoviesPage({
    super.key,
    required this.movies,
    this.seriesList = const [],
    required this.watchlistIds,
    required this.onPlayMovie,
    required this.onToggleWatchlist,
    required this.onOpenWatchlistTab,
    required this.onOpenProfileTab,
    this.onRefreshStreamtape,
    this.isSyncingStreamtape = false,
  });

  @override
  State<HomeMoviesPage> createState() => _HomeMoviesPageState();
}

class _HomeMoviesPageState extends State<HomeMoviesPage> {
  String _selectedCategory = "All";
  int _featuredIndex = 0;
  final Map<String, int> _selectedSeasonBySeries = {};
  Timer? _heroAutoSlideTimer;

  List<String> _buildCategories() {
    final Set<String> dynamicLangs = {};
    for (final m in widget.movies) {
      if (m.language.trim().isNotEmpty) {
        dynamicLangs.add(m.language.trim());
      }
    }
    return [
      "All",
      "Movies",
      "Web Series",
      ...dynamicLangs,
      "Action",
      "Romance",
      "Drama",
    ];
  }

  @override
  void initState() {
    super.initState();
    _heroAutoSlideTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      final featured = widget.movies.where((m) => m.isFeatured).toList();
      if (featured.length > 1) {
        setState(() {
          _featuredIndex = (_featuredIndex + 1) % featured.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _heroAutoSlideTimer?.cancel();
    super.dispose();
  }

  bool _matchesSelectedCategory(MovieItem m) {
    if (_selectedCategory == "All") return true;
    if (_selectedCategory == "Movies") return !m.isEpisode;
    if (_selectedCategory == "Web Series") return m.isEpisode;
    if (m.language.toLowerCase().contains(_selectedCategory.toLowerCase())) {
      return true;
    }
    return m.genres.any(
      (g) => g.toLowerCase() == _selectedCategory.toLowerCase(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.movies.isEmpty) {
      return GlassContainer(
        margin: EdgeInsets.zero,
        borderRadius: 0,
        blur: 28,
        border: const Border(),
        boxShadow: const [],
        backgroundColor: const Color(0xFF050C0A).withValues(alpha: 0.35),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    color: Color(0xFF00E676),
                    strokeWidth: 3.2,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.isSyncingStreamtape
                      ? "Loading Live Catalog..."
                      : "Connecting to Niooo M Catalog...",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFF0FDF4),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Fetching real-time movies, posters, languages, and web series.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                if (widget.onRefreshStreamtape != null) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: widget.onRefreshStreamtape,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E676), Color(0xFF10B981)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        "Refresh Live Catalog",
                        style: TextStyle(
                          color: Color(0xFF03120D),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final categories = _buildCategories();
    final featuredList = widget.movies.where((m) => m.isFeatured).toList();
    final MovieItem heroMovie = featuredList.isNotEmpty
        ? featuredList[_featuredIndex % featuredList.length]
        : widget.movies.first;

    final filteredItems =
        widget.movies.where(_matchesSelectedCategory).toList();
    final standaloneMovies =
        filteredItems.where((m) => !m.isEpisode).toList();

    final continueWatching =
        widget.movies.where((m) => m.watchProgress > 0.01).toList();

    // Build series list from API SeriesCatalogItem or group episodes dynamically
    final List<SeriesCatalogItem> activeSeriesList =
        widget.seriesList.isNotEmpty
            ? widget.seriesList
            : _buildFallbackSeriesFromEpisodes(widget.movies);

    return GlassContainer(
      margin: EdgeInsets.zero,
      borderRadius: 0,
      blur: 28,
      border: const Border(),
      boxShadow: const [],
      backgroundColor: const Color(0xFF050C0A).withValues(alpha: 0.35),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Top App Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF00E676),
                          Color(0xFF10B981),
                          Color(0xFF047857),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF00E676).withValues(alpha: 0.4),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.movie_filter_rounded,
                      color: Color(0xFF03120D),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "niooo",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFF0FDF4),
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  if (widget.onRefreshStreamtape != null) ...[
                    GlassIconButton(
                      icon: widget.isSyncingStreamtape
                          ? Icons.sync_rounded
                          : Icons.cloud_sync_rounded,
                      tooltip: "Refresh Catalog",
                      size: 38,
                      isAccent: widget.isSyncingStreamtape,
                      color: const Color(0xFF00E676),
                      onTap: widget.onRefreshStreamtape!,
                    ),
                    const SizedBox(width: 8),
                  ],
                  GlassIconButton(
                    icon: Icons.bookmark_border_rounded,
                    tooltip: "My Watchlist",
                    size: 38,
                    onTap: widget.onOpenWatchlistTab,
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    icon: Icons.person_outline_rounded,
                    tooltip: "Profile",
                    size: 38,
                    isAccent: true,
                    color: const Color(0xFF00E676),
                    onTap: widget.onOpenProfileTab,
                  ),
                ],
              ),
            ),
          ),

          // Category & Language Filter Pills
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFF00E676),
                                  Color(0xFF10B981),
                                  Color(0xFF047857),
                                ],
                              )
                            : LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.08),
                                  const Color(0xFF0A1815)
                                      .withValues(alpha: 0.72),
                                ],
                              ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.5)
                              : const Color(0xFF00E676).withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF03120D)
                              : const Color(0xFFCBD5E1),
                          fontSize: 12.5,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Hero Featured Banner
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
              child: _buildHeroBanner(heroMovie, featuredList),
            ),
          ),

          // Continue Watching Section
          if (continueWatching.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _buildSectionHeader(
                    "Continue Watching",
                    "Pick up right where you left off",
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 158,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: continueWatching.length,
                      itemBuilder: (context, index) {
                        return _buildContinueWatchingCard(
                          continueWatching[index],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Movies Horizontal Row (`/api/public/v1/movies`)
          if (standaloneMovies.isNotEmpty &&
              _selectedCategory != "Web Series")
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  _buildSectionHeader(
                    "Featured Movies (${standaloneMovies.length})",
                    "Official posters, languages & HD streams",
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 268,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: standaloneMovies.length,
                      itemBuilder: (context, index) {
                        return _buildPosterCard(standaloneMovies[index]);
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Dynamic Series & Seasons Management (`/api/public/v1/series` + `/api/public/v1/series/{id}`)
          if (activeSeriesList.isNotEmpty && _selectedCategory != "Movies")
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: activeSeriesList.map((series) {
                  return _buildSeriesSection(series);
                }).toList(),
              ),
            ),

          // Full Catalog List
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 22, 0, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(
                    "All Catalog Videos (${filteredItems.length})",
                    "Real-time movies & episodes from Niooo M API",
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: filteredItems
                          .map((movie) => _buildWideCatalogRow(movie))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<SeriesCatalogItem> _buildFallbackSeriesFromEpisodes(
    List<MovieItem> all,
  ) {
    final Map<String, List<MovieItem>> bySeries = {};
    for (final m in all) {
      if (m.isEpisode && m.seriesName.isNotEmpty) {
        bySeries.putIfAbsent(m.seriesName, () => []).add(m);
      }
    }
    final List<SeriesCatalogItem> result = [];
    bySeries.forEach((name, eps) {
      eps.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      final first = eps.first;
      result.add(
        SeriesCatalogItem(
          id: first.seriesId.isNotEmpty ? first.seriesId : name,
          title: name,
          posterUrl: first.posterUrl,
          description: first.synopsis,
          releaseYear: first.releaseYear,
          genres: first.genres,
          language: first.language,
          episodeCount: eps.length,
          seasonCount: 1,
          seasons: [
            SeriesSeasonItem(
              season: 1,
              posterUrl: first.posterUrl,
              episodeCount: eps.length,
              episodes: eps,
            ),
          ],
        ),
      );
    });
    return result;
  }

  Widget _buildSeriesSection(SeriesCatalogItem series) {
    final seasons = series.seasons;
    final int activeSeasonNum = _selectedSeasonBySeries[series.id] ??
        (seasons.isNotEmpty ? seasons.first.season : 1);

    final SeriesSeasonItem? activeSeason = seasons.isNotEmpty
        ? seasons.firstWhere(
            (s) => s.season == activeSeasonNum,
            orElse: () => seasons.first,
          )
        : null;

    final List<MovieItem> episodes = activeSeason?.episodes ?? [];
    if (episodes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF00E676).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF00E676)
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            "SERIES · ${series.language.toUpperCase()}",
                            style: const TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            series.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF0FDF4),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "${series.seasonCount} ${series.seasonCount == 1 ? 'Season' : 'Seasons'} · ${series.episodeCount} Episodes · Tap any episode to stream",
                      style: const TextStyle(
                        color: Color(0xFF8696A0),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (seasons.length > 1)
                Row(
                  children: seasons.map((s) {
                    final isSel = s.season == activeSeasonNum;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedSeasonBySeries[series.id] = s.season;
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? const Color(0xFF00E676)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          "S${s.season}",
                          style: TextStyle(
                            color: isSel
                                ? const Color(0xFF03120D)
                                : const Color(0xFFF0FDF4),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 268,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              return _buildPosterCard(episodes[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeroBanner(MovieItem hero, List<MovieItem> featuredList) {
    final inWatchlist = widget.watchlistIds.contains(hero.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => widget.onPlayMovie(hero),
        child: Container(
          height: 325,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFF00E676).withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.75),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  hero.posterUrl.isNotEmpty ? hero.posterUrl : hero.backdropUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF091814),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.18),
                        const Color(0xFF040B09).withValues(alpha: 0.68),
                        const Color(0xFF030706).withValues(alpha: 0.96),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676)
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF00E676)
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                            child: Text(
                              hero.qualityBadge,
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              hero.language,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (featuredList.length > 1)
                            Row(
                              children:
                                  List.generate(featuredList.length, (idx) {
                                final active = idx ==
                                    (_featuredIndex % featuredList.length);
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _featuredIndex = idx),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.only(left: 5),
                                    width: active ? 18 : 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: active
                                          ? const Color(0xFF00E676)
                                          : Colors.white38,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                );
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        hero.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${hero.releaseYear} · ${hero.language} · ${hero.duration} · ${hero.genres.join(' • ')}",
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: GlassButton(
                              onTap: () => widget.onPlayMovie(hero),
                              borderRadius: 20,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    color: Color(0xFF03120D),
                                    size: 20,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    "Play Movie Now",
                                    style: TextStyle(
                                      color: Color(0xFF03120D),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GlassIconButton(
                            icon: inWatchlist
                                ? Icons.bookmark_added_rounded
                                : Icons.bookmark_add_outlined,
                            tooltip: "Watchlist",
                            size: 44,
                            isAccent: inWatchlist,
                            color: inWatchlist
                                ? const Color(0xFF00E676)
                                : Colors.white,
                            onTap: () => widget.onToggleWatchlist(hero.id),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFF0FDF4),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF8696A0),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF00E676),
            size: 22,
          ),
        ],
      ),
    );
  }

  Widget _buildContinueWatchingCard(MovieItem movie) {
    return GestureDetector(
      onTap: () => widget.onPlayMovie(movie),
      child: Container(
        width: 255,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF00E676).withValues(alpha: 0.25),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                movie.backdropUrl.isNotEmpty
                    ? movie.backdropUrl
                    : movie.posterUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF0A1815),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E676),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Color(0xFF03120D),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                movie.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                              Text(
                                "${(movie.watchProgress * 100).round()}% watched · ${movie.language}",
                                style: const TextStyle(
                                  color: Color(0xFF00E676),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: movie.watchProgress,
                        minHeight: 4,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF00E676),
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
    );
  }

  Widget _buildPosterCard(MovieItem movie) {
    final saved = widget.watchlistIds.contains(movie.id);
    return GestureDetector(
      onTap: () => widget.onPlayMovie(movie),
      child: Container(
        width: 162,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.08),
              const Color(0xFF091613).withValues(alpha: 0.78),
            ],
          ),
          border: Border.all(
            color: const Color(0xFF00E676).withValues(alpha: 0.22),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      movie.posterUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF0A1815),
                        child: const Center(
                          child: Icon(
                            Icons.movie_creation_outlined,
                            color: Color(0xFF00E676),
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          movie.episodeLabel.isNotEmpty
                              ? movie.episodeLabel
                              : movie.language,
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => widget.onToggleWatchlist(movie.id),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            saved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            color: saved
                                ? const Color(0xFF00E676)
                                : Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF0FDF4),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${movie.releaseYear} · ${movie.language} · ${movie.duration}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8696A0),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWideCatalogRow(MovieItem movie) {
    final saved = widget.watchlistIds.contains(movie.id);

    return GestureDetector(
      onTap: () => widget.onPlayMovie(movie),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.06),
              const Color(0xFF091613).withValues(alpha: 0.72),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF00E676).withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                movie.posterUrl,
                width: 68,
                height: 92,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 68,
                  height: 92,
                  color: const Color(0xFF0A1815),
                  child: const Icon(
                    Icons.movie_outlined,
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
                          color:
                              const Color(0xFF00E676).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          movie.language,
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "${movie.releaseYear} · ${movie.qualityBadge} · ${movie.duration}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF8696A0),
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    movie.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF0FDF4),
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    movie.synopsis,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                GestureDetector(
                  onTap: () => widget.onToggleWatchlist(movie.id),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      saved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: saved ? const Color(0xFF00E676) : Colors.white70,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 36,
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
