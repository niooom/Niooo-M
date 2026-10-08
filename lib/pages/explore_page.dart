import "dart:ui";
import "package:flutter/material.dart";
import "../models/movie_models.dart";
import "../widgets/glass_container.dart";

class ExplorePage extends StatefulWidget {
  final List<MovieItem> movies;
  final Set<String> watchlistIds;
  final ValueChanged<MovieItem> onPlayMovie;
  final ValueChanged<String> onToggleWatchlist;

  const ExplorePage({
    super.key,
    required this.movies,
    required this.watchlistIds,
    required this.onPlayMovie,
    required this.onToggleWatchlist,
  });

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  String _searchQuery = "";
  String _selectedGenre = "All";
  String _sortBy = "Rating";

  List<String> _buildFilters() {
    final Set<String> filters = {"All", "Movies", "Web Series"};
    for (final m in widget.movies) {
      if (m.language.trim().isNotEmpty) {
        filters.add(m.language.trim());
      }
      for (final g in m.genres) {
        if (g.trim().isNotEmpty) {
          filters.add(g.trim());
        }
      }
    }
    return filters.toList();
  }

  @override
  Widget build(BuildContext context) {
    final filters = _buildFilters();
    final filtered = widget.movies.where((m) {
      final q = _searchQuery.trim().toLowerCase();
      final matchesQuery = q.isEmpty ||
          m.title.toLowerCase().contains(q) ||
          m.rawTitle.toLowerCase().contains(q) ||
          m.seriesName.toLowerCase().contains(q) ||
          m.language.toLowerCase().contains(q) ||
          m.genres.any((g) => g.toLowerCase().contains(q));
      if (!matchesQuery) return false;
      if (_selectedGenre == "All") return true;
      if (_selectedGenre == "Movies") return !m.isEpisode;
      if (_selectedGenre == "Web Series") return m.isEpisode;
      if (m.language.toLowerCase() == _selectedGenre.toLowerCase()) return true;
      if (m.genres.any((g) => g.toLowerCase() == _selectedGenre.toLowerCase())) {
        return true;
      }
      return false;
    }).toList();

    if (_sortBy == "Rating") {
      filtered.sort((a, b) => b.rating.compareTo(a.rating));
    } else if (_sortBy == "Newest") {
      filtered.sort((a, b) => b.releaseYear.compareTo(a.releaseYear));
    }

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
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    "Explore Cinema",
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFF0FDF4),
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                _buildSortChip("Rating"),
                const SizedBox(width: 6),
                _buildSortChip("Newest"),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.08),
                        const Color(0xFF091714).withValues(alpha: 0.78),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF00E676).withValues(alpha: 0.25),
                    ),
                  ),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(
                        color: Color(0xFFF0FDF4), fontSize: 13.5),
                    decoration: const InputDecoration(
                      hintText:
                          "Search movies, directors, actors, or genres...",
                      hintStyle:
                          TextStyle(color: Color(0xFF8696A0), fontSize: 13),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Color(0xFF00E676),
                        size: 20,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: filters.map((genre) {
                final selected = _selectedGenre == genre;
                return GestureDetector(
                  onTap: () => setState(() => _selectedGenre = genre),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 7.5,
                    ),
                    decoration: BoxDecoration(
                      gradient: selected
                          ? const LinearGradient(
                              colors: [
                                Color(0xFF00E676),
                                Color(0xFF10B981),
                                Color(0xFF047857),
                              ],
                            )
                          : LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.07),
                                const Color(0xFF091714).withValues(alpha: 0.75),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.5)
                            : const Color(0xFF00E676).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      genre,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF03120D)
                            : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 95),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.66,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final movie = filtered[index];
                final saved = widget.watchlistIds.contains(movie.id);
                return GestureDetector(
                  onTap: () => widget.onPlayMovie(movie),
                  child: Container(
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
                        color:
                            const Color(0xFF00E676).withValues(alpha: 0.22),
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
                                      color: Colors.black
                                          .withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      movie.episodeLabel.isNotEmpty
                                          ? movie.episodeLabel
                                          : movie.language,
                                      style: const TextStyle(
                                        color: Color(0xFF00E676),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: GestureDetector(
                                    onTap: () =>
                                        widget.onToggleWatchlist(movie.id),
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.75),
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
                                Positioned(
                                  bottom: 8,
                                  right: 8,
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
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
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
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String label) {
    final active = _sortBy == label;
    return GestureDetector(
      onTap: () => setState(() => _sortBy = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF00E676).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? const Color(0xFF00E676)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF00E676) : const Color(0xFF94A3B8),
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
