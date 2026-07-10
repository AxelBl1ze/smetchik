import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models.dart';

class PdfService {
  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<(pw.Font, pw.Font)> _fonts() async {
    _regular ??= await PdfGoogleFonts.robotoRegular();
    _bold ??= await PdfGoogleFonts.robotoBold();
    return (_regular!, _bold!);
  }

  static Future<Uint8List> buildCatalogPdf({
    required List<CatalogItemModel> items,
    required ProfileModel? profile,
  }) async {
    final (regular, bold) = await _fonts();
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final doc = pw.Document(theme: theme);
    final hasPro = profile?.hasActivePro == true;
    final showBrandHeader = !hasPro || profile?.pdfShowBrandHeader == true;
    final showServiceMark = !hasPro || profile?.pdfShowServiceMark == true;
    final template = hasPro
        ? PdfTemplate.normalize(profile?.pdfTemplate)
        : PdfTemplate.classic;
    final accent = PdfColor.fromHex(
      hasPro
          ? PdfAccentColor.normalize(profile?.pdfAccentColor)
          : PdfAccentColor.orange,
    );
    final masterName = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName.trim()
        : 'Сметчик';

    final grouped = <String, List<CatalogItemModel>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: _pageMargin(template),
          pageFormat: PdfPageFormat.a4,
        ),
        footer: showServiceMark ? _serviceFooter : null,
        build: (context) => [
          _documentHeader(
            template: template,
            accent: accent,
            brandTitle: showBrandHeader ? 'Сметчик' : masterName,
            subtitle: showBrandHeader ? masterName : profile?.specialization,
            phone: profile?.phone,
            docTitle: 'Прайс-лист',
            meta: [
              'Дата: ${formatDate(DateTime.now())}',
              'Позиций: ${items.length}',
            ],
          ),
          pw.SizedBox(height: template == PdfTemplate.compact ? 14 : 24),
          for (final entry in grouped.entries) ...[
            pw.Text(
              entry.key,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(
                  color: PdfColor.fromHex('#E0DED8'),
                ),
                bottom: pw.BorderSide(color: PdfColor.fromHex('#E0DED8')),
                top: pw.BorderSide(color: PdfColor.fromHex('#E0DED8')),
              ),
              headerDecoration: pw.BoxDecoration(
                color: _tableHeaderColor(template, accent),
              ),
              headerStyle: _tableHeaderStyle(template),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(4),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1.5),
              },
              headers: ['Услуга', 'Ед.', 'Цена'],
              data: [
                for (final item in entry.value)
                  [item.title, item.unit, formatMoney(item.unitPrice)],
              ],
            ),
            pw.SizedBox(height: 16),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> buildEstimatePdf({
    required EstimateDetail detail,
    required ProfileModel? profile,
  }) async {
    final (regular, bold) = await _fonts();
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final doc = pw.Document(theme: theme);
    final estimate = detail.estimate;
    final hasPro = profile?.hasActivePro == true;
    final template = hasPro
        ? PdfTemplate.normalize(profile?.pdfTemplate)
        : PdfTemplate.classic;
    final accent = PdfColor.fromHex(
      hasPro
          ? PdfAccentColor.normalize(profile?.pdfAccentColor)
          : PdfAccentColor.orange,
    );
    final showBrandHeader = !hasPro || profile?.pdfShowBrandHeader == true;
    final showSignatures = !hasPro || profile?.pdfShowSignatures == true;
    final showServiceMark = !hasPro || profile?.pdfShowServiceMark == true;
    final paymentTerms = hasPro ? profile?.pdfPaymentTerms?.trim() : null;
    final footerNote = hasPro ? profile?.pdfFooterNote?.trim() : null;
    final masterName = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName.trim()
        : 'Сметчик';

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: _pageMargin(template),
          pageFormat: PdfPageFormat.a4,
        ),
        footer: showServiceMark ? _serviceFooter : null,
        build: (context) => [
          _documentHeader(
            template: template,
            accent: accent,
            brandTitle: showBrandHeader ? 'Сметчик' : masterName,
            subtitle: showBrandHeader ? masterName : profile?.specialization,
            phone: profile?.phone,
            docTitle: 'Коммерческое предложение',
            meta: [
              'Дата: ${formatDate(estimate.estimateDate)}',
              'Смета: ${estimate.id.substring(0, 8).toUpperCase()}',
            ],
          ),
          pw.SizedBox(height: template == PdfTemplate.compact ? 16 : 26),
          pw.Container(
            padding: pw.EdgeInsets.all(
              template == PdfTemplate.compact ? 10 : 14,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F7F6F3'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: _infoBlock('Объект', estimate.objectTitle)),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: _infoBlock(
                    'Клиент',
                    [
                          estimate.client?.name,
                          estimate.client?.phone,
                          estimate.client?.objectAddress,
                        ]
                        .whereType<String>()
                        .where((e) => e.trim().isNotEmpty)
                        .join('\n'),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Работы',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: PdfColor.fromHex('#E0DED8'),
              ),
              bottom: pw.BorderSide(color: PdfColor.fromHex('#E0DED8')),
              top: pw.BorderSide(color: PdfColor.fromHex('#E0DED8')),
            ),
            headerDecoration: pw.BoxDecoration(
              color: _tableHeaderColor(template, accent),
            ),
            headerStyle: _tableHeaderStyle(template),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
            },
            headers: ['Работа', 'Кол-во', 'Цена', 'Сумма'],
            data: [
              for (final line in detail.lines)
                [
                  line.title,
                  '${_formatQty(line.quantity)} ${line.unit}',
                  formatMoney(line.unitPrice),
                  formatMoney(line.lineTotal),
                ],
            ],
          ),
          pw.SizedBox(height: 18),
          if (paymentTerms?.isNotEmpty == true) ...[
            _noteBlock('Условия оплаты', paymentTerms!),
            pw.SizedBox(height: 10),
          ],
          if (footerNote?.isNotEmpty == true) ...[
            _noteBlock('Примечание', footerNote!),
            pw.SizedBox(height: 10),
          ],
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                width: 220,
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: template == PdfTemplate.accent
                      ? accent
                      : PdfColor.fromHex('#2D2D2D'),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Итого',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 11,
                      ),
                    ),
                    pw.Text(
                      formatMoney(estimate.totalAmount),
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showSignatures) ...[
            pw.SizedBox(height: 42),
            pw.Row(
              children: [
                _signature('Исполнитель'),
                pw.SizedBox(width: 32),
                _signature('Заказчик'),
              ],
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _infoBlock(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#888780'),
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            value.isEmpty ? 'Не указан' : value,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  static pw.EdgeInsets _pageMargin(String template) {
    return switch (PdfTemplate.normalize(template)) {
      PdfTemplate.compact => const pw.EdgeInsets.fromLTRB(24, 24, 24, 28),
      _ => const pw.EdgeInsets.all(32),
    };
  }

  static PdfColor _tableHeaderColor(String template, PdfColor accent) {
    return switch (PdfTemplate.normalize(template)) {
      PdfTemplate.accent => accent,
      PdfTemplate.compact => PdfColor.fromHex('#F7F6F3'),
      _ => PdfColor.fromHex('#FEF0E0'),
    };
  }

  static pw.TextStyle _tableHeaderStyle(String template) {
    return pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      color: PdfTemplate.normalize(template) == PdfTemplate.accent
          ? PdfColors.white
          : PdfColors.black,
    );
  }

  static pw.Widget _documentHeader({
    required String template,
    required PdfColor accent,
    required String brandTitle,
    required String? subtitle,
    required String? phone,
    required String docTitle,
    required List<String> meta,
  }) {
    final normalized = PdfTemplate.normalize(template);
    final titleColor = normalized == PdfTemplate.accent
        ? PdfColors.white
        : accent;
    final subtitleColor = normalized == PdfTemplate.accent
        ? PdfColors.white
        : PdfColors.black;

    final left = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          brandTitle,
          style: pw.TextStyle(
            fontSize: normalized == PdfTemplate.compact ? 18 : 22,
            fontWeight: pw.FontWeight.bold,
            color: titleColor,
          ),
        ),
        pw.SizedBox(height: 4),
        if (subtitle?.trim().isNotEmpty == true)
          pw.Text(
            subtitle!.trim(),
            style: pw.TextStyle(fontSize: 10, color: subtitleColor),
          ),
        if (phone?.trim().isNotEmpty == true)
          pw.Text(
            phone!.trim(),
            style: pw.TextStyle(fontSize: 10, color: subtitleColor),
          ),
      ],
    );

    final right = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          docTitle,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: subtitleColor,
          ),
        ),
        pw.SizedBox(height: 4),
        for (final value in meta)
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 10, color: subtitleColor),
          ),
      ],
    );

    if (normalized == PdfTemplate.accent) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: accent,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [left, right],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [left, right],
        ),
        if (normalized == PdfTemplate.classic) ...[
          pw.SizedBox(height: 10),
          pw.Container(height: 2, color: accent),
        ],
      ],
    );
  }

  static pw.Widget _signature(String label) {
    return pw.Expanded(
      child: pw.Column(
        children: [
          pw.Container(height: 1, color: PdfColor.fromHex('#888780')),
          pw.SizedBox(height: 4),
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  static pw.Widget _noteBlock(String label, String value) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F7F6F3'),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  static pw.Widget _serviceFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 12),
      child: pw.Text(
        'Создано в Сметчике',
        style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#888780')),
      ),
    );
  }

  static String _formatQty(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
