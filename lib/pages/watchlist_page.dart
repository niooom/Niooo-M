import "package:flutter/material.dart";
import "../models/movie_models.dart";
import "../widgets/glass_container.dart";

class WatchlistPage extends StatelessWidget {
  final List<MovieItem> movies;
  final Set<String> watchlistIds;
  final ValueChanged<MovieItem> onPlayMovie;
  final ValueChanged<String> onToggleWatchlist;
  final VoidCallback onExploreMovies;

  const WatchlistPage({
    super.key,
    required this.movies,
    required this.watchlistIds,
    required this.onPlayMovie,
    required this.onToggleWatchlist,
    required this.onExploreMovies,
  });

  @override
  Widget build(BuildContext context) {
    final savedMovies =
        movies.where((m) => watchlistIds.contains(m.id)).toList();

    return GlassContainer(
      margin: EdgeInsets.zero,
      borderRadius: 0,
      blur: 28,
      border: const Border(),
      boxShadow: const [],
      backgroundColor: const Color(0xFF050C0A).withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "My Watchlist",
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFF0FDF4),
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Saved movies ready for instant 4K streaming",
                        style: TextStyle(
                          color: Color(0xFF8696A0),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF00E676).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    "${savedMovies.length} Saved",
                    style: const TextStyle(
                      color: Color(0xFF00E676),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: savedMovies.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 16, 28, 80),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.bookmark_add_outlined,
                            color: Color(0xFF00E676),
                            size: 46,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Your Watchlist is Empty",
                            style: TextStyle(
                              color: Color(0xFFF0FDF4),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          GlassButton(
                            onTap: onExploreMovies,
                            borderRadius: 18,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 12,
                            ),
                            child: const Text(
                              "Explore 4K Movies",
                              style: TextStyle(
                                color: Color(0xFF03120D),
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 95),
                    itemCount: savedMovies.length,
                    itemBuilder: (context, index) {
                      final movie = savedMovies[index];
                      return GestureDetector(
                        onTap: () => onPlayMovie(movie),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(alpha: 0.07),
                                const Color(0xFF091613).withValues(alpha: 0.75),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0xFF00E676)
                                  .withValues(alpha: 0.24),
                            ),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.network(
                                  movie.posterUrl,
                                  width: 74,
                                  height: 102,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      movie.qualityBadge,
                                      style: const TextStyle(
                                        color: Color(0xFF00E676),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      movie.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFF0FDF4),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      "${movie.releaseYear} · ${movie.viewsLabel} · ★ ${movie.rating}",
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        GlassButton(
                                          onTap: () => onPlayMovie(movie),
                                          borderRadius: 14,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 7,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(
                                                Icons.play_arrow_rounded,
                                                color: Color(0xFF03120D),
                                                size: 16,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                "Play Now",
                                                style: TextStyle(
                                                  color: Color(0xFF03120D),
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        GlassIconButton(
                                          icon: Icons.delete_outline_rounded,
                                          tooltip: "Remove",
                                          size: 34,
                                          color: const Color(0xFFFF5252),
                                          onTap: () =>
                                              onToggleWatchlist(movie.id),
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
                  ),
          ),
        ],
      ),
    );
  }
}
