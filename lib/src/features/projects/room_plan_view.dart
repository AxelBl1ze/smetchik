import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../data/room_calculator.dart';

class RoomPlanView extends StatelessWidget {
  const RoomPlanView({
    super.key,
    required this.room,
    this.editing = false,
    this.pending,
    this.onTap,
    this.onDimension,
    this.compact = false,
  });
  final ProjectRoom room;
  final bool editing, compact;
  final PlanPoint? pending;
  final ValueChanged<Offset>? onTap;
  final ValueChanged<String>? onDimension;

  static Rect drawingRect(Size size, bool compact) => Rect.fromLTWH(
    compact ? 12 : 38,
    compact ? 12 : 52,
    math.max(1, size.width - (compact ? 24 : 104)),
    math.max(1, size.height - (compact ? 24 : 100)),
  );

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: compact ? 1 : 1.18,
    child: LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        final rect = drawingRect(size, compact);
        return Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                label: 'План помещения ${room.name}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: onTap == null
                      ? null
                      : (d) => onTap!(
                          Offset(
                            ((d.localPosition.dx - rect.left) / rect.width * 12)
                                .clamp(0, 12),
                            ((d.localPosition.dy - rect.top) / rect.height * 12)
                                .clamp(0, 12),
                          ),
                        ),
                  child: CustomPaint(
                    painter: _PlanPainter(room, editing, pending, compact),
                  ),
                ),
              ),
            ),
            if (!compact) ...[
              Positioned(
                top: 0,
                left: 40,
                right: 64,
                child: Center(
                  child: _Dimension(
                    label: 'Ширина',
                    value: room.width,
                    onTap: onDimension == null
                        ? null
                        : () => onDimension!('width'),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 60,
                bottom: 44,
                child: Center(
                  child: _Dimension(
                    label: 'Длина',
                    value: room.depth,
                    onTap: onDimension == null
                        ? null
                        : () => onDimension!('depth'),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 32,
                right: 64,
                child: Center(
                  child: _Dimension(
                    label: 'Высота',
                    value: room.height,
                    onTap: onDimension == null
                        ? null
                        : () => onDimension!('height'),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

String roomNumber(num n) =>
    n.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '').replaceAll('.', ',');

class _Dimension extends StatelessWidget {
  const _Dimension({required this.label, required this.value, this.onTap});
  final String label;
  final double value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$label помещения',
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${roomNumber(value)} м',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (onTap != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 12,
                      color: AppColors.orangeDark,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _PlanPainter extends CustomPainter {
  _PlanPainter(this.room, this.editing, this.pending, this.compact);
  final ProjectRoom room;
  final bool editing, compact;
  final PlanPoint? pending;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = RoomPlanView.drawingRect(size, compact);
    Offset pt(PlanPoint p) => Offset(
      rect.left + p.x / 12 * rect.width,
      rect.top + p.y / 12 * rect.height,
    );
    if (editing) {
      final grid = Paint()..color = AppColors.border;
      for (var x = 0; x <= 12; x++) {
        for (var y = 0; y <= 12; y++) {
          canvas.drawCircle(
            pt(PlanPoint(x.toDouble(), y.toDouble())),
            1.4,
            grid,
          );
        }
      }
    }
    try {
      final points = RoomGeometry(room).outline;
      final path = Path()..addPolygon(points.map(pt).toList(), true);
      canvas.drawPath(path, Paint()..color = AppColors.orangeLight);
    } on FormatException {
      /* An unfinished contour is deliberately not filled. */
    }
    final wallPaint = Paint()
      ..color = AppColors.graphite
      ..strokeWidth = compact ? 3 : 5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < room.walls.length; i++) {
      final wall = room.walls[i], a = pt(wall.a), b = pt(wall.b);
      canvas.drawLine(a, b, wallPaint);
      if (!compact) {
        String length = '';
        try {
          length = '${roomNumber(RoomGeometry(room).wallLength(wall))} м';
        } catch (_) {
          /* Labels appear once the geometry has bounds. */
        }
        final painter = TextPainter(
          text: TextSpan(
            text: '${i + 1} · $length',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontFamily: 'Inter',
              backgroundColor: AppColors.card,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        final delta = b - a;
        final len = delta.distance;
        final normal = len == 0
            ? Offset.zero
            : Offset(-delta.dy / len, delta.dx / len) * 12;
        painter.paint(
          canvas,
          mid + normal - Offset(painter.width / 2, painter.height / 2),
        );
      }
    }
    for (final opening in room.openings) {
      final walls = room.walls.where((w) => w.key == opening.wallKey);
      if (walls.isEmpty) continue;
      final wall = walls.first;
      final length = RoomGeometry(room).wallLength(wall);
      if (!length.isFinite || length <= 0) continue;
      final a = pt(wall.a), d = pt(wall.b) - a;
      final start = a + d * (opening.offset / length),
          end = a + d * ((opening.offset + opening.width) / length);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = AppColors.card
          ..strokeWidth = compact ? 5 : 8,
      );
      final color = opening.kind == OpeningKind.door
          ? AppColors.orangeDark
          : AppColors.info;
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = color
          ..strokeWidth = compact ? 2 : 3,
      );
      if (!compact) {
        final norm = Offset(-d.dy, d.dx) / d.distance * 5;
        canvas.drawLine(
          start + norm,
          end + norm,
          Paint()
            ..color = color
            ..strokeWidth = 1,
        );
      }
    }
    if (editing) {
      for (final wall in room.walls) {
        for (final p in [wall.a, wall.b]) {
          canvas.drawCircle(pt(p), 4, Paint()..color = AppColors.card);
          canvas.drawCircle(
            pt(p),
            4,
            Paint()
              ..color = AppColors.graphite
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
    }
    if (pending != null) {
      canvas.drawCircle(pt(pending!), 7, Paint()..color = AppColors.orange);
    }
  }

  @override
  bool shouldRepaint(covariant _PlanPainter old) =>
      old.room != room ||
      old.editing != editing ||
      old.pending != pending ||
      old.compact != compact;
}
