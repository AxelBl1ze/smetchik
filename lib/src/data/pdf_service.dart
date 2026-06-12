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
    final masterName = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName.trim()
        : 'Сметчик';

    final grouped = <String, List<CatalogItemModel>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          margin: pw.EdgeInsets.all(32),
          pageFormat: PdfPageFormat.a4,
        ),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Сметчик',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#F5820D'),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(masterName, style: const pw.TextStyle(fontSize: 10)),
                  if (profile?.phone?.isNotEmpty == true)
                    pw.Text(
                      profile!.phone!,
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Прайс-лист',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('Дата: ${formatDate(DateTime.now())}'),
                  pw.Text('Позиций: ${items.length}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 24),
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
                color: PdfColor.fromHex('#FEF0E0'),
              ),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
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
    final masterName = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName.trim()
        : 'Сметчик';

    doc.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          margin: pw.EdgeInsets.all(32),
          pageFormat: PdfPageFormat.a4,
        ),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Сметчик',
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#F5820D'),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(masterName, style: const pw.TextStyle(fontSize: 10)),
                  if (profile?.phone?.isNotEmpty == true)
                    pw.Text(
                      profile!.phone!,
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Коммерческое предложение',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('Дата: ${formatDate(estimate.estimateDate)}'),
                  pw.Text(
                    'Смета: ${estimate.id.substring(0, 8).toUpperCase()}',
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 26),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
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
              color: PdfColor.fromHex('#FEF0E0'),
            ),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
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
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                width: 220,
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#2D2D2D'),
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
          pw.SizedBox(height: 42),
          pw.Row(
            children: [
              _signature('Исполнитель'),
              pw.SizedBox(width: 32),
              _signature('Заказчик'),
            ],
          ),
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

  static String _formatQty(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
