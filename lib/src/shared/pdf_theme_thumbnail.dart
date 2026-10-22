import 'package:flutter/material.dart';

import '../data/pdf_contrast.dart';
import '../data/pdf_templates.dart';

class PdfThemeThumbnail extends StatelessWidget {
  const PdfThemeThumbnail({super.key, required this.template});
  final SmetaTemplateConfig template;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size(70, 88),
      painter: _DocumentPainter(template),
    ),
  );
}

class _DocumentPainter extends CustomPainter {
  _DocumentPainter(this.template);
  final SmetaTemplateConfig template;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 70;
    canvas.save();
    canvas.scale(scale);
    final bg = PdfContrast.color(template.colors.background);
    final ink = PdfContrast.readable(
      PdfContrast.color(template.colors.primaryText),
      bg,
    );
    final accent = PdfContrast.color(template.colors.accent);
    void rect(double x, double y, double w, double h, Color color) =>
        canvas.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = color);
    rect(0, 0, 70, 88, bg);
    final centered = template.layout.headerAlign == 'center';
    if (template.features.showCoverPage) {
      rect(0, 0, 70, 40, accent);
      rect(10, 13, 45, 3, PdfContrast.on(accent));
      rect(10, 20, 30, 2, PdfContrast.on(accent));
    } else {
      rect(8, 9, 54, 3, accent);
      rect(centered ? 19 : 8, 18, 32, 3, ink);
      rect(centered ? 23 : 8, 24, 24, 1.5, ink.withValues(alpha: .6));
    }
    for (var row = 0; row < 4; row++) {
      final y = 45.0 + row * 6;
      rect(8, y, 35 - row * 3, 1.5, ink.withValues(alpha: .6));
      rect(52, y, 10, 1.5, ink.withValues(alpha: .6));
      if (template.layout.tableStyle == 'grid') {
        rect(8, y + 3, 54, .4, ink.withValues(alpha: .25));
      }
    }
    rect(40, 74, 22, 6, accent);
    rect(43, 76, 16, 1.5, PdfContrast.on(accent));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DocumentPainter oldDelegate) =>
      oldDelegate.template.id != template.id;
}
