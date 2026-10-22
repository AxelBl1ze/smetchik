import 'package:flutter/material.dart';

class PdfContrast {
  static Color color(String hex) =>
      Color(int.parse(hex.replaceFirst('#', ''), radix: 16) | 0xFF000000);

  static double ratio(Color a, Color b) {
    final first = a.computeLuminance();
    final second = b.computeLuminance();
    return (first > second ? first + .05 : second + .05) /
        (first > second ? second + .05 : first + .05);
  }

  static Color on(Color background) =>
      ratio(Colors.black, background) >= ratio(Colors.white, background)
      ? Colors.black
      : Colors.white;

  static Color readable(Color proposed, Color background) =>
      ratio(proposed, background) >= 4.5 ? proposed : on(background);

  static String hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}
