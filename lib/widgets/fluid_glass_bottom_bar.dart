import "dart:ui";
import "package:flutter/material.dart";

class FluidGlassBottomBar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final int unreadChatsCount;

  const FluidGlassBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    this.unreadChatsCount = 0,
  });

  @override
  State<FluidGlassBottomBar> createState() => _FluidGlassBottomBarState();
}

class _FluidGlassBottomBarState extends State<FluidGlassBottomBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  double _currentPosition = 0.0;
  bool _isDragging = false;

  List<_NavItemData> get _items => [
        const _NavItemData(
          index: 0,
          label: "Home",
          outlineIcon: Icons.movie_creation_outlined,
          filledIcon: Icons.movie_filter_rounded,
          badgeCount: 0,
        ),
        const _NavItemData(
          index: 1,
          label: "Explore",
          outlineIcon: Icons.explore_outlined,
          filledIcon: Icons.explore_rounded,
          badgeCount: 0,
        ),
        _NavItemData(
          index: 2,
          label: "Watchlist",
          outlineIcon: Icons.bookmark_border_rounded,
          filledIcon: Icons.bookmark_rounded,
          badgeCount: widget.unreadChatsCount,
        ),
        const _NavItemData(
          index: 3,
          label: "Profile",
          outlineIcon: Icons.person_outline_rounded,
          filledIcon: Icons.person_rounded,
          badgeCount: 0,
        ),
      ];

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.selectedIndex.toDouble();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
  }

  @override
  void didUpdateWidget(FluidGlassBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && !_isDragging) {
      _animateTo(widget.selectedIndex.toDouble());
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _animController.stop();
    _slideAnimation = Tween<double>(
      begin: _currentPosition,
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
      ),
    )..addListener(() {
        setState(() {
          _currentPosition = _slideAnimation.value;
        });
      });

    _animController.forward(from: 0.0);
  }

  void _handleDragStart(DragStartDetails details, double tabWidth) {
    _animController.stop();
    setState(() {
      _isDragging = true;
      _currentPosition = (details.localPosition.dx / tabWidth - 0.5).clamp(0.0, 3.0);
    });
  }

  void _handleDragUpdate(DragUpdateDetails details, double tabWidth) {
    setState(() {
      _currentPosition = (details.localPosition.dx / tabWidth - 0.5).clamp(0.0, 3.0);
    });
  }

  void _handleDragEnd(DragEndDetails details, double tabWidth) {
    final targetIndex = _currentPosition.round().clamp(0, 3);
    setState(() {
      _isDragging = false;
    });
    _animateTo(targetIndex.toDouble());
    widget.onTabSelected(targetIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(38),
            boxShadow: [
              // Pitch-black levitation drop shadow
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.85),
                blurRadius: 34,
                spreadRadius: 2,
                offset: const Offset(0, 14),
              ),
              // Ambient neon emerald under-glow
              BoxShadow(
                color: const Color(0xFF00E676).withValues(alpha: 0.22),
                blurRadius: 28,
                spreadRadius: -2,
                offset: const Offset(0, 4),
              ),
              // Specular top edge highlight
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.14),
                blurRadius: 4,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(38),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(38),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.14),
                      const Color(0xFF0B1815).withValues(alpha: 0.80),
                      const Color(0xFF040908).withValues(alpha: 0.92),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.34),
                    width: 1.1,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double totalWidth = constraints.maxWidth;
                    final double tabWidth = totalWidth / 4;
                    final double pillLeft =
                        (_currentPosition * tabWidth).clamp(0.0, totalWidth - tabWidth);

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (details) =>
                          _handleDragStart(details, tabWidth),
                      onHorizontalDragUpdate: (details) =>
                          _handleDragUpdate(details, tabWidth),
                      onHorizontalDragEnd: (details) =>
                          _handleDragEnd(details, tabWidth),
                      child: SizedBox(
                        height: 56,
                        child: Stack(
                          children: [
                            // 3D Liquid Glass Sliding Active Pill Capsule
                            Positioned(
                              left: pillLeft,
                              top: 2,
                              bottom: 2,
                              width: tabWidth,
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF00E676)
                                          .withValues(alpha: _isDragging ? 0.96 : 0.88),
                                      const Color(0xFF10B981)
                                          .withValues(alpha: _isDragging ? 0.94 : 0.84),
                                      const Color(0xFF047857)
                                          .withValues(alpha: _isDragging ? 0.96 : 0.90),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: _isDragging ? 0.75 : 0.55),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.55),
                                      blurRadius: 12,
                                      offset: const Offset(0, 5),
                                    ),
                                    BoxShadow(
                                      color: const Color(0xFF00E676).withValues(
                                        alpha: _isDragging ? 0.65 : 0.45,
                                      ),
                                      blurRadius: _isDragging ? 20 : 14,
                                      offset: const Offset(0, 2),
                                    ),
                                    BoxShadow(
                                      color: Colors.white.withValues(alpha: 0.35),
                                      blurRadius: 3,
                                      offset: const Offset(0, -1),
                                    ),
                                  ],
                                ),
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    height: 15,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.white.withValues(alpha: 0.36),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: _items.map((item) {
                                final double distance =
                                    (_currentPosition - item.index).abs();
                                final bool isHovered = distance < 0.5;

                                return Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      _animateTo(item.index.toDouble());
                                      widget.onTabSelected(item.index);
                                    },
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              AnimatedScale(
                                                scale: isHovered ? 1.16 : 1.0,
                                                duration: const Duration(
                                                  milliseconds: 180,
                                                ),
                                                child: Icon(
                                                  isHovered
                                                      ? item.filledIcon
                                                      : item.outlineIcon,
                                                  color: isHovered
                                                      ? const Color(0xFF03120E)
                                                      : const Color(0xFF94A3B8),
                                                  size: 22,
                                                ),
                                              ),
                                              if (item.badgeCount > 0)
                                                Positioned(
                                                  top: -5,
                                                  right: -10,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 5.5,
                                                      vertical: 1.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(
                                                        colors: [
                                                          Color(0xFF00E676),
                                                          Color(0xFF10B981),
                                                        ],
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(12),
                                                      border: Border.all(
                                                        color: const Color(0xFF030706),
                                                        width: 1.5,
                                                      ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: const Color(0xFF00E676)
                                                              .withValues(alpha: 0.65),
                                                          blurRadius: 8,
                                                        ),
                                                      ],
                                                    ),
                                                    child: Text(
                                                      "${item.badgeCount}",
                                                      style: const TextStyle(
                                                        color: Color(0xFF030706),
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.w900,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 2.5),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              item.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isHovered
                                                    ? const Color(0xFF03120E)
                                                    : const Color(0xFF94A3B8),
                                                fontSize: 10.5,
                                                fontWeight: isHovered
                                                    ? FontWeight.w800
                                                    : FontWeight.w500,
                                                letterSpacing: 0.1,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final int index;
  final String label;
  final IconData outlineIcon;
  final IconData filledIcon;
  final int badgeCount;

  const _NavItemData({
    required this.index,
    required this.label,
    required this.outlineIcon,
    required this.filledIcon,
    this.badgeCount = 0,
  });
}
