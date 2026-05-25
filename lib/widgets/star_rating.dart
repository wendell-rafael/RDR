import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final double value;
  final double size;
  final Color? color;
  final ValueChanged<double>? onChanged;

  const StarRating({
    super.key,
    required this.value,
    this.size = 24,
    this.color,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final starColor = color ?? Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starValue = i + 1.0;
        IconData icon;
        if (value >= starValue) {
          icon = Icons.star_rounded;
        } else if (value >= starValue - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_border_rounded;
        }

        if (onChanged != null) {
          return GestureDetector(
            onTapDown: (details) {
              // Determine half or full star from tap position
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final starWidth = box.size.width / 5;
              final localX =
                  details.globalPosition.dx - box.localToGlobal(Offset.zero).dx;
              final starIndex = (localX / starWidth).floor();
              final fraction = (localX % starWidth) / starWidth;
              final newValue = starIndex + (fraction > 0.5 ? 1.0 : 0.5);
              onChanged!(newValue.clamp(0.5, 5.0));
            },
            child: Icon(icon, size: size, color: starColor),
          );
        }
        return Icon(icon, size: size, color: starColor);
      }),
    );
  }
}

class StarRatingInput extends StatefulWidget {
  final double initialValue;
  final ValueChanged<double> onChanged;
  final double size;

  const StarRatingInput({
    super.key,
    required this.initialValue,
    required this.onChanged,
    this.size = 36,
  });

  @override
  State<StarRatingInput> createState() => _StarRatingInputState();
}

class _StarRatingInputState extends State<StarRatingInput> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    final starColor = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return _StarButton(
          index: i,
          value: _value,
          size: widget.size,
          color: starColor,
          onTap: (v) {
            setState(() => _value = v);
            widget.onChanged(v);
          },
        );
      }),
    );
  }
}

class _StarButton extends StatelessWidget {
  final int index;
  final double value;
  final double size;
  final Color color;
  final ValueChanged<double> onTap;

  const _StarButton({
    required this.index,
    required this.value,
    required this.size,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final starValue = index + 1.0;
    IconData icon;
    if (value >= starValue) {
      icon = Icons.star_rounded;
    } else if (value >= starValue - 0.5) {
      icon = Icons.star_half_rounded;
    } else {
      icon = Icons.star_border_rounded;
    }

    return GestureDetector(
      onTapDown: (details) {
        final RenderBox box = context.findRenderObject() as RenderBox;
        final localX = box.globalToLocal(details.globalPosition).dx;
        final newValue =
            localX < box.size.width / 2 ? index + 0.5 : index + 1.0;
        onTap(newValue.clamp(0.5, 5.0));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}
