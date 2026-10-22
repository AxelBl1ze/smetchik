import 'package:flutter_test/flutter_test.dart';
import 'package:smetchik/src/data/pdf_contrast.dart';
import 'package:smetchik/src/data/pdf_templates.dart';

void main() {
  test(
    'all template accents, surfaces and text maintain readable contrast',
    () {
      for (final template in SmetaTemplates.values) {
        for (final accent in template.accentChoices) {
          final background = PdfContrast.color(accent);
          expect(
            PdfContrast.ratio(PdfContrast.on(background), background),
            greaterThanOrEqualTo(4.5),
            reason: '${template.id}: $accent',
          );
        }
        for (final surface in [
          template.colors.background,
          template.colors.surface,
        ]) {
          final background = PdfContrast.color(surface);
          for (final ink in [
            template.colors.primaryText,
            template.colors.secondaryText,
            template.colors.accent,
          ]) {
            expect(
              PdfContrast.ratio(
                PdfContrast.readable(PdfContrast.color(ink), background),
                background,
              ),
              greaterThanOrEqualTo(4.5),
              reason: '${template.id}: $ink on $surface',
            );
          }
        }
      }
    },
  );
}
