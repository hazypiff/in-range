import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A little lighthouse night-scene for the beacon status card.
///
/// ON: the lamp glows, a light beam sweeps, stars twinkle, waves drift.
/// OFF: the scene goes still and desaturated.
class LighthouseBeacon extends StatefulWidget {
  const LighthouseBeacon({super.key, required this.on, this.size = 64});

  final bool on;
  final double size;

  @override
  State<LighthouseBeacon> createState() => _LighthouseBeaconState();
}

class _LighthouseBeaconState extends State<LighthouseBeacon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void initState() {
    super.initState();
    if (widget.on) _controller.repeat();
  }

  @override
  void didUpdateWidget(LighthouseBeacon old) {
    super.didUpdateWidget(old);
    if (widget.on && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.on && _controller.isAnimating) {
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _LighthousePainter(t: _controller.value, on: widget.on),
      ),
    );
  }
}

class _LighthousePainter extends CustomPainter {
  const _LighthousePainter({required this.t, required this.on});

  final double t; // 0..1 animation phase
  final bool on;

  // Desaturate + darken everything when the beacon is off.
  Color _c(Color c) =>
      on ? c : Color.lerp(c, const Color(0xFF3A4149), 0.62)!;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset p(double x, double y) => Offset(s * x, s * y);
    final lamp = p(0.5, 0.345);

    // Everything lives inside a circular badge.
    final badge = Rect.fromCircle(center: p(0.5, 0.5), radius: s * 0.48);
    canvas.save();
    canvas.clipPath(Path()..addOval(badge));

    // Night sky.
    canvas.drawRect(
      badge,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_c(const Color(0xFF2E3B63)), _c(const Color(0xFF141B31))],
        ).createShader(badge),
    );

    // Stars (twinkle when on).
    const stars = [
      Offset(0.20, 0.20), Offset(0.30, 0.10), Offset(0.72, 0.12),
      Offset(0.82, 0.28), Offset(0.14, 0.42), Offset(0.86, 0.50),
      Offset(0.68, 0.22),
    ];
    for (var i = 0; i < stars.length; i++) {
      final tw = on
          ? 0.35 + 0.65 * math.pow(math.sin(math.pi * (t + i / stars.length)), 2)
          : 0.35;
      canvas.drawCircle(
        p(stars[i].dx, stars[i].dy),
        s * (i.isEven ? 0.012 : 0.008),
        Paint()..color = Colors.white.withValues(alpha: 0.85 * tw.toDouble()),
      );
    }

    // Light beam, behind the tower.
    if (on) {
      final sweep = math.sin(t * 2 * math.pi);
      final tilt = sweep * 0.26;
      final fade = 0.5 + 0.5 * (1 - sweep.abs());
      for (final dir in [-1.0, 1.0]) {
        canvas.save();
        canvas.translate(lamp.dx, lamp.dy);
        canvas.rotate(tilt * dir);
        canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..lineTo(dir * s * 0.52, -s * 0.10)
            ..lineTo(dir * s * 0.52, s * 0.10)
            ..close(),
          Paint()
            ..shader = LinearGradient(
              begin: dir < 0 ? Alignment.centerRight : Alignment.centerLeft,
              end: dir < 0 ? Alignment.centerLeft : Alignment.centerRight,
              colors: [
                const Color(0xFFFFE082).withValues(alpha: 0.85 * fade),
                const Color(0xFFFFE082).withValues(alpha: 0),
              ],
            ).createShader(
                Rect.fromCircle(center: Offset.zero, radius: s * 0.52)),
        );
        canvas.restore();
      }
      // Halo around the lamp.
      canvas.drawCircle(
        lamp,
        s * (0.10 + 0.015 * math.sin(t * 4 * math.pi)),
        Paint()
          ..color = const Color(0xFFFFD54F).withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }

    // Sea with two drifting wave lines.
    final seaTop = 0.76;
    final sea = Rect.fromLTRB(badge.left, s * seaTop, badge.right, badge.bottom);
    canvas.drawRect(
      sea,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_c(const Color(0xFF1E5A6E)), _c(const Color(0xFF0F2E3C))],
        ).createShader(sea),
    );
    for (final (level, phase, alpha) in [(0.78, 0.0, 0.5), (0.84, 0.5, 0.3)]) {
      final wave = Path()..moveTo(badge.left, s * level);
      for (var x = badge.left; x <= badge.right; x += s * 0.02) {
        wave.lineTo(
          x,
          s * level +
              s * 0.008 *
                  math.sin((x / s) * 4 * math.pi + (t + phase) * 2 * math.pi),
        );
      }
      canvas.drawPath(
        wave,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.012
          ..color = _c(const Color(0xFF7FD4E8)).withValues(alpha: alpha),
      );
    }

    // Rocky islet.
    canvas.drawOval(
      Rect.fromCenter(center: p(0.5, 0.815), width: s * 0.40, height: s * 0.14),
      Paint()..color = _c(const Color(0xFF2C3540)),
    );

    // Tower: gently curved taper, shaded left-to-right.
    final tower = Path()
      ..moveTo(s * 0.415, s * 0.415)
      ..quadraticBezierTo(s * 0.428, s * 0.60, s * 0.405, s * 0.80)
      ..lineTo(s * 0.595, s * 0.80)
      ..quadraticBezierTo(s * 0.572, s * 0.60, s * 0.585, s * 0.415)
      ..close();
    final towerRect = Rect.fromLTRB(s * 0.40, s * 0.40, s * 0.60, s * 0.80);
    canvas.drawPath(
      tower,
      Paint()
        ..shader = LinearGradient(
          colors: [_c(const Color(0xFFCFC9BC)), _c(const Color(0xFFFAF7F0))],
        ).createShader(towerRect),
    );
    // Two red bands, clipped to the tower silhouette.
    canvas.save();
    canvas.clipPath(tower);
    final band = Paint()..color = _c(const Color(0xFFE05252));
    canvas.drawRect(Rect.fromLTRB(0, s * 0.455, s, s * 0.525), band);
    canvas.drawRect(Rect.fromLTRB(0, s * 0.60, s, s * 0.67), band);
    canvas.restore();

    // Gallery deck + railing.
    final deck = Paint()..color = _c(const Color(0xFF37424E));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 0.395, s * 0.395, s * 0.605, s * 0.42),
        Radius.circular(s * 0.01),
      ),
      deck,
    );
    final rail = Paint()
      ..color = _c(const Color(0xFF37424E))
      ..strokeWidth = s * 0.012;
    canvas.drawLine(p(0.40, 0.365), p(0.60, 0.365), rail);
    for (final x in [0.415, 0.5, 0.585]) {
      canvas.drawLine(p(x, 0.365), p(x, 0.395), rail);
    }

    // Lamp room: glass with mullions.
    final glassRect = Rect.fromLTRB(s * 0.44, s * 0.29, s * 0.56, s * 0.395);
    canvas.drawRRect(
      RRect.fromRectAndRadius(glassRect, Radius.circular(s * 0.012)),
      Paint()
        ..shader = RadialGradient(
          colors: on
              ? [const Color(0xFFFFECB3), const Color(0xFFF9A825)]
              : [_c(const Color(0xFF9FB4C4)), _c(const Color(0xFF5C7284))],
        ).createShader(glassRect),
    );
    // The lamp itself.
    canvas.drawCircle(
      lamp,
      s * 0.032,
      Paint()..color = on ? Colors.white : _c(const Color(0xFF44586A)),
    );
    for (final x in [0.48, 0.52]) {
      canvas.drawLine(
        p(x, 0.29),
        p(x, 0.395),
        Paint()
          ..color = _c(const Color(0xFF37424E)).withValues(alpha: 0.55)
          ..strokeWidth = s * 0.008,
      );
    }

    // Dome roof + finial.
    final roof = Path()
      ..moveTo(s * 0.43, s * 0.29)
      ..quadraticBezierTo(s * 0.5, s * 0.175, s * 0.57, s * 0.29)
      ..close();
    canvas.drawPath(roof, Paint()..color = _c(const Color(0xFFC94040)));
    canvas.drawCircle(p(0.5, 0.185), s * 0.014, Paint()..color = _c(const Color(0xFFC94040)));

    canvas.restore();

    // Thin badge ring so the circle reads cleanly on any card color.
    canvas.drawCircle(
      badge.center,
      badge.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.015
        ..color = _c(const Color(0xFF3E4C6B)).withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_LighthousePainter old) => old.t != t || old.on != on;
}
