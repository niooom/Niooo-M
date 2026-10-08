import "dart:ui";
import "package:flutter/material.dart";

/// Paints a 1px specular liquid-glass gradient border around a rounded rectangle.
/// Top-left edge catches bright specular light + neon emerald rim, fading into
/// subtle dark translucent glass on the bottom-right edge.
class _LiquidGlassBorderPainter extends CustomPainter {
  final double borderRadius;
  final double strokeWidth;
  final Gradient gradient;

  const _LiquidGlassBorderPainter({
    required this.borderRadius,
    required this.strokeWidth,
    required this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(borderRadius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassBorderPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gradient != gradient;
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? backgroundColor;
  final Color? borderColor;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final bool showEmeraldGlow;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 26.0,
    this.blur = 28.0,
    this.backgroundColor,
    this.borderColor,
    this.border,
    this.boxShadow,
    this.showEmeraldGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    final baseFill =
        backgroundColor ?? const Color(0xFF0A1412).withValues(alpha: 0.62);

    final effectiveGradientBorder = LinearGradient(
      begin: const Alignment(-0.9, -0.95),
      end: const Alignment(0.95, 0.95),
      colors: borderColor != null
          ? [
              borderColor!,
              borderColor!.withValues(alpha: 0.35),
              Colors.white.withValues(alpha: 0.08),
            ]
          : [
              Colors.white.withValues(alpha: 0.32),
              const Color(0xFF10B981).withValues(alpha: 0.42),
              Colors.white.withValues(alpha: 0.05),
              const Color(0xFF00E676).withValues(alpha: 0.22),
            ],
      stops: borderColor != null
          ? const [0.0, 0.5, 1.0]
          : const [0.0, 0.32, 0.72, 1.0],
    );

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: boxShadow ??
            [
              // Deep 3D pitch-black ambient drop shadow
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.78),
                blurRadius: 32,
                spreadRadius: 1,
                offset: const Offset(0, 14),
              ),
              // Subtle emerald ambient aura
              BoxShadow(
                color: const Color(0xFF00E676)
                    .withValues(alpha: showEmeraldGlow ? 0.16 : 0.06),
                blurRadius: 26,
                spreadRadius: -2,
                offset: const Offset(0, 4),
              ),
              // Specular top-left outer sheen
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(-1, -1),
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: CustomPaint(
            foregroundPainter: border == null
                ? _LiquidGlassBorderPainter(
                    borderRadius: borderRadius,
                    strokeWidth: 1.1,
                    gradient: effectiveGradientBorder,
                  )
                : null,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                border: border,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.09),
                    baseFill,
                    const Color(0xFF040908).withValues(alpha: 0.78),
                  ],
                  stops: const [0.0, 0.42, 1.0],
                ),
              ),
              padding: padding ?? EdgeInsets.zero,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class GlassIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final Color? color;
  final Color? backgroundColor;
  final bool isAccent;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 40.0,
    this.color,
    this.backgroundColor,
    this.isAccent = false,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.size * 0.36;
    final accentActive = widget.isAccent || _isPressed;

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          width: widget.size,
          height: widget.size,
          transform: Matrix4.translationValues(0, _isPressed ? 1.8 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: widget.backgroundColor != null
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isPressed
                        ? [
                            const Color(0xFF00E676).withValues(alpha: 0.28),
                            const Color(0xFF0A1916).withValues(alpha: 0.92),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.14),
                            const Color(0xFF101E1B).withValues(alpha: 0.72),
                            const Color(0xFF070F0D).withValues(alpha: 0.88),
                          ],
                  ),
            color: widget.backgroundColor,
            boxShadow: _isPressed
                ? [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : [
                    // 3D tactile bottom elevation
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.68),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                    // Soft inner/outer emerald glow
                    if (accentActive)
                      BoxShadow(
                        color: const Color(0xFF00E676).withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    // Top-left 3D specular rim
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.12),
                      blurRadius: 3,
                      offset: const Offset(-1, -1),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: CustomPaint(
                foregroundPainter: _LiquidGlassBorderPainter(
                  borderRadius: radius,
                  strokeWidth: 1.0,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: accentActive
                        ? [
                            const Color(0xFF69F0AE).withValues(alpha: 0.85),
                            const Color(0xFF00E676).withValues(alpha: 0.35),
                            Colors.white.withValues(alpha: 0.12),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.36),
                            const Color(0xFF10B981).withValues(alpha: 0.28),
                            Colors.white.withValues(alpha: 0.06),
                          ],
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Subtle top inner glass reflection
                    Positioned(
                      top: 0,
                      left: 4,
                      right: 4,
                      height: widget.size * 0.38,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(radius),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.16),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Icon(
                      widget.icon,
                      color: widget.color ?? const Color(0xFFF0FDF4),
                      size: widget.size * 0.47,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final EdgeInsetsGeometry? padding;
  final Gradient? gradient;
  final Color? color;
  final double borderRadius;

  const GlassButton({
    super.key,
    required this.child,
    required this.onTap,
    this.padding,
    this.gradient,
    this.color,
    this.borderRadius = 20.0,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isDefaultEmerald = widget.gradient == null && widget.color == null;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _isPressed ? 2.2 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: widget.color != null
              ? null
              : (widget.gradient ??
                  const LinearGradient(
                    colors: [
                      Color(0xFF00E676),
                      Color(0xFF10B981),
                      Color(0xFF047857),
                    ],
                    stops: [0.0, 0.48, 1.0],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )),
          color: widget.color,
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: const Color(0xFF00E676).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [
                  // Deep 3D tactile shadow
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.68),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                  // Neon emerald under-glow
                  if (isDefaultEmerald)
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.42),
                      blurRadius: 18,
                      spreadRadius: -1,
                      offset: const Offset(0, 3),
                    ),
                  // Top specular highlight
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.24),
                    blurRadius: 3,
                    offset: const Offset(0, -1),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: CustomPaint(
            foregroundPainter: _LiquidGlassBorderPainter(
              borderRadius: widget.borderRadius,
              strokeWidth: 1.15,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: _isPressed ? 0.35 : 0.62),
                  const Color(0xFF69F0AE).withValues(alpha: 0.45),
                  Colors.white.withValues(alpha: 0.10),
                ],
              ),
            ),
            child: Stack(
              children: [
                // Top inner liquid glass reflection band
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 16,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.26),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: widget.padding ??
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 9.5),
                  child: widget.child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
