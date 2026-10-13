import 'package:flutter/material.dart';
import 'package:portly/theme/app_theme.dart';

/// Shimmer efektli skeleton loader.
/// Veri yüklenirken gerçek içeriğin yerine konur, profesyonel görünüm sağlar.
class Skeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadiusGeometry borderRadius;

  const Skeleton({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  /// Dikdörtgen şeklinde bir card placeholder.
  factory Skeleton.card({double height = 80}) =>
      Skeleton(height: height, borderRadius: BorderRadius.circular(12));

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius is BorderRadius
                ? widget.borderRadius as BorderRadius
                : BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + _controller.value * 2, 0),
              end: Alignment(_controller.value * 2, 0),
              colors: [c.surface, c.surfaceAlt, c.surface],
            ),
          ),
        );
      },
    );
  }
}

/// Liste için tekrarlanan placeholder card'lar.
class SkeletonList extends StatelessWidget {
  final int count;
  final double itemHeight;
  final double spacing;
  const SkeletonList({
    super.key,
    this.count = 4,
    this.itemHeight = 76,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : spacing),
          child: Skeleton.card(height: itemHeight),
        );
      }),
    );
  }
}
