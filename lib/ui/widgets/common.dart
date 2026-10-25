import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';

BoxDecoration appCardDecoration(
  BuildContext context, {
  Color? color,
  bool highlighted = false,
  bool sunken = false,
  double radius = 16,
}) {
  final c = context.colors;
  return BoxDecoration(
    color: color ?? (sunken ? c.surfaceSunken : c.surface),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: highlighted ? c.accent.withValues(alpha: 0.45) : c.border,
    ),
    boxShadow: context.isDark
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ]
        : [
            BoxShadow(
              color: const Color(0xFF0B1220).withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
  );
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 16,
    this.color,
    this.highlighted = false,
    this.sunken = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final bool highlighted;
  final bool sunken;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: appCardDecoration(
        context,
        color: color,
        highlighted: highlighted,
        sunken: sunken,
        radius: radius,
      ),
      child: child,
    );
  }
}

/// 窄屏（手机）与宽屏（桌面）使用不同的页面留白。
EdgeInsets responsivePagePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 640) return const EdgeInsets.fromLTRB(16, 16, 16, 20);
  return const EdgeInsets.fromLTRB(30, 26, 30, 30);
}

bool isNarrow(BuildContext context) => MediaQuery.sizeOf(context).width < 640;

class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 1180});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 带悬停反馈的可点击卡片。
class HoverCard extends StatefulWidget {
  const HoverCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 16,
    this.onTap,
    this.accentWhenHovered = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool accentWhenHovered;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hovered ? c.surfaceAlt : c.surface,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: _hovered && widget.accentWhenHovered
                  ? c.accent.withValues(alpha: 0.35)
                  : c.border,
            ),
            boxShadow: context.isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: const Color(0xFF0B1220).withValues(alpha: 0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFA548), Color(0xFFF0740D)],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: c.accent.withValues(alpha: 0.32),
            blurRadius: size * 0.55,
            offset: Offset(0, size * 0.16),
          ),
        ],
      ),
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final cloud = Path()
      ..addOval(Rect.fromCircle(center: Offset(s * 0.37, s * 0.45), radius: s * 0.14))
      ..addOval(Rect.fromCircle(center: Offset(s * 0.57, s * 0.40), radius: s * 0.18))
      ..addOval(Rect.fromCircle(center: Offset(s * 0.71, s * 0.52), radius: s * 0.11))
      ..addRRect(RRect.fromLTRBR(
        s * 0.26,
        s * 0.45,
        s * 0.77,
        s * 0.64,
        Radius.circular(s * 0.09),
      ));

    final tunnel = Path()
      ..addRRect(RRect.fromLTRBAndCorners(
        s * 0.41,
        s * 0.50,
        s * 0.59,
        s * 0.64,
        topLeft: Radius.circular(s * 0.085),
        topRight: Radius.circular(s * 0.085),
      ));

    final combined = Path.combine(PathOperation.difference, cloud, tunnel);
    canvas.drawPath(combined, white);

    final base = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.018;
    canvas.drawLine(
      Offset(s * 0.2, s * 0.71),
      Offset(s * 0.8, s * 0.71),
      base,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StatusDot extends StatefulWidget {
  const StatusDot({
    super.key,
    required this.color,
    this.size = 8,
    this.pulse = false,
  });

  final Color color;
  final double size;
  final bool pulse;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.6),
            blurRadius: 7,
          ),
        ],
      ),
    );
    if (!widget.pulse) return dot;
    return SizedBox(
      width: widget.size * 2.6,
      height: widget.size * 2.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              return Container(
                width: widget.size * (1 + t * 1.6),
                height: widget.size * (1 + t * 1.6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.35 * (1 - t)),
                ),
              );
            },
          ),
          dot,
        ],
      ),
    );
  }
}

Color phaseColor(TunnelPhase phase, AppPalette c) {
  return switch (phase) {
    TunnelPhase.connected => c.success,
    TunnelPhase.starting => c.warning,
    TunnelPhase.reconnecting => c.warning,
    TunnelPhase.error => c.danger,
    TunnelPhase.stopped => c.faint,
  };
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
    this.pulse = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulse)
            StatusDot(color: color, size: dense ? 5.5 : 6, pulse: true)
          else if (icon != null)
            Icon(icon, size: dense ? 11 : 12, color: color)
          else
            Container(
              width: dense ? 5 : 6,
              height: dense ? 5 : 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          SizedBox(width: dense ? 5 : 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class TinyTag extends StatelessWidget {
  const TinyTag({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.dense = true,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color ?? c.muted;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tint.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 12, color: tint),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: tint,
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: c.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: c.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.eyebrow,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!.toUpperCase(),
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(title, style: context.texts.headlineMedium),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 20),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(spacing: 8, runSpacing: 8, children: actions),
          ),
        ],
      ],
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.tone = InfoTone.accent,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final InfoTone tone;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = switch (tone) {
      InfoTone.accent => c.accent,
      InfoTone.warning => c.warning,
      InfoTone.danger => c.danger,
      InfoTone.success => c.success,
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 12.5,
                    height: 1.55,
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress == 0 ? null : progress,
                      minHeight: 5,
                      backgroundColor: c.surfaceSunken,
                      color: color,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: action,
            ),
          ],
        ],
      ),
    );
  }
}

enum InfoTone { accent, warning, danger, success }

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: compact ? 26 : 46,
        horizontal: 24,
      ),
      decoration: BoxDecoration(
        color: c.surfaceSunken.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border),
            ),
            child: Icon(icon, size: 22, color: c.muted),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: c.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.55),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

class IconSquare extends StatelessWidget {
  const IconSquare({
    super.key,
    required this.icon,
    this.color,
    this.size = 38,
    this.iconSize = 18,
    this.radius = 11,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = color ?? c.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: tint.withValues(alpha: 0.16)),
      ),
      child: Icon(icon, size: iconSize, color: tint),
    );
  }
}

class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    this.icon,
    this.busy = false,
    this.onPressed,
    this.filled = true,
    this.danger = false,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final bool busy;
  final VoidCallback? onPressed;
  final bool filled;
  final bool danger;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: filled ? c.onAccent : c.muted,
            ),
          )
        else if (icon != null)
          Icon(icon, size: 15),
        if (busy || icon != null) const SizedBox(width: 7),
        Text(label),
      ],
    );
    final button = filled
        ? FilledButton(
            onPressed: busy ? null : onPressed,
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: c.danger,
                    foregroundColor: Colors.white,
                  )
                : null,
            child: child,
          )
        : OutlinedButton(
            onPressed: busy ? null : onPressed,
            child: child,
          );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class MonoText extends StatelessWidget {
  const MonoText(
    this.text, {
    super.key,
    this.size = 12,
    this.color,
    this.weight = FontWeight.w400,
    this.height = 1.55,
  });

  final String text;
  final double size;
  final Color? color;
  final FontWeight weight;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Cascadia Mono',
        fontFamilyFallback: const ['Consolas', 'Courier New'],
        fontSize: size,
        color: color ?? c.text,
        fontWeight: weight,
        height: height,
        letterSpacing: 0.05,
      ),
    );
  }
}

class PulsingRing extends StatefulWidget {
  const PulsingRing({
    super.key,
    required this.color,
    this.size = 120,
    this.child,
  });

  final Color color;
  final double size;
  final Widget? child;

  @override
  State<PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<PulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RingPainter(
              color: widget.color,
              progress: _controller.value,
            ),
            child: Center(
              child: Container(
                width: widget.size * 0.44,
                height: widget.size * 0.44,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.2),
                  ),
                ),
                child: Center(child: widget.child),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        center,
        radius * (0.62 + i * 0.17),
        ring..color = color.withValues(alpha: 0.14 - i * 0.03),
      );
    }
    final orbit = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.85);
    for (var i = 0; i < 3; i++) {
      final angle = progress * math.pi * 2 + i * (math.pi * 2 / 3);
      final r = radius * (0.62 + (i % 2) * 0.17);
      canvas.drawCircle(
        Offset(
          center.dx + math.cos(angle) * r,
          center.dy + math.sin(angle) * r,
        ),
        2.2,
        orbit..color = color.withValues(alpha: 0.65),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: c.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        child,
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint!,
            style: TextStyle(color: c.faint, fontSize: 11.5, height: 1.5),
          ),
        ],
      ],
    );
  }
}

class HoverTextButton extends StatefulWidget {
  const HoverTextButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.color,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;

  @override
  State<HoverTextButton> createState() => _HoverTextButtonState();
}

class _HoverTextButtonState extends State<HoverTextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = widget.color ?? (widget.onTap == null ? c.faint : c.muted);
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 120),
          style: TextStyle(
            color: _hovered && widget.onTap != null ? c.text : tint,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 13,
                  color: _hovered && widget.onTap != null ? c.text : tint,
                ),
                const SizedBox(width: 5),
              ],
              Text(widget.label),
            ],
          ),
        ),
      ),
    );
  }
}

class CopyText extends StatefulWidget {
  const CopyText(
    this.text, {
    super.key,
    this.display,
    this.size = 12,
    this.mono = false,
    this.color,
    this.icon = Icons.copy_rounded,
  });

  final String text;
  final String? display;
  final double size;
  final bool mono;
  final Color? color;
  final IconData icon;

  @override
  State<CopyText> createState() => _CopyTextState();
}

class _CopyTextState extends State<CopyText> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await _copyToClipboard(widget.text);
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final baseStyle = TextStyle(
      color: widget.color ?? c.muted,
      fontSize: widget.size,
      fontFamily: widget.mono ? 'Cascadia Mono' : null,
      fontFamilyFallback:
          widget.mono ? const ['Consolas', 'Courier New'] : null,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _copy,
        child: Tooltip(
          message: '复制',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.display ?? widget.text,
                  overflow: TextOverflow.ellipsis,
                  style: baseStyle,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                _copied ? Icons.check_rounded : widget.icon,
                size: widget.size + 1,
                color: _copied ? c.success : c.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _copyToClipboard(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}
