import 'dart:io';

import 'package:excel_plus/excel_plus.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/data/pdf_service.dart';
import 'package:smetchik/src/data/pdf_templates.dart';
import 'package:smetchik/src/data/project_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('ru_RU');
  });

  final project = ProjectModel(
    id: 'project-1',
    title: 'Дом на Садовой',
    objectAddress: 'Оренбург, улица Садовая, 12',
    customerName: 'Алексей',
    plannedRevenue: 2400000,
    startDate: DateTime(2026, 7, 1),
    targetDate: DateTime(2026, 11, 1),
    status: ProjectStatus.active,
    notes: 'Фундамент готов.',
    createdAt: DateTime(2026, 7, 1),
    incomeAmount: 400000,
    expenseAmount: 125000,
  );
  final detail = ProjectDetail(
    project: project,
    transactions: [
      ProjectTransactionModel(
        id: 'expense-1',
        projectId: project.id,
        type: ProjectTransactionType.expense,
        category: 'Материалы',
        title: 'Кирпич',
        amount: 125000,
        quantity: 1000,
        unit: 'шт.',
        payerName: 'Джамал',
        counterparty: 'Строймаркет',
        transactionDate: DateTime(2026, 7, 3),
      ),
      ProjectTransactionModel(
        id: 'income-1',
        projectId: project.id,
        type: ProjectTransactionType.income,
        category: 'Оплата',
        title: 'Аванс',
        amount: 400000,
        payerName: 'Алексей',
        transactionDate: DateTime(2026, 7, 2),
      ),
    ],
  );

  test('creates Excel workbook with summary, expenses and income sheets', () {
    final bytes = ProjectExportService.buildWorkbook(detail);
    final workbook = xls.Excel.decodeBytes(bytes);

    expect(bytes, isNotEmpty);
    expect(
      workbook.tables.keys,
      containsAll(['Сводка', 'Расходы', 'Поступления', 'По плательщикам']),
    );
    final payments = workbook['По плательщикам'];
    final expense = payments.rows[3];
    expect(expense[1]?.value?.toString(), 'Джамал');
    expect(expense[2]?.value, xls.IntCellValue(125000));
    expect(expense[3]?.value, xls.IntCellValue(100));
    expect(expense[4]?.value?.toString(), '03.07.2026');
    expect(expense[5]?.value?.toString(), 'Кирпич');
    expect(expense[7]?.value?.toString(), 'Строймаркет');
    expect(expense[8]?.value, xls.IntCellValue(125000));
    expect(payments.rows[4][1]?.value?.toString(), 'Алексей');
    expect(workbook['Расходы'].rows[3][6]?.value?.toString(), 'Джамал');
  });

  test('creates PDF project report', () async {
    final bytes = await PdfService.buildProjectReportPdf(
      detail: detail,
      profile: null,
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    if (const bool.fromEnvironment('CAPTURE_PROJECT_PAYMENTS')) {
      final directory = Directory('build/test_artifacts')
        ..createSync(recursive: true);
      await File('${directory.path}/project-payments.pdf').writeAsBytes(bytes);
    }
  });

  test('creates project reports and price lists for every template', () async {
    for (final template in SmetaTemplates.values) {
      final profile = ProfileModel(
        id: 'test',
        fullName: 'Илья',
        currency: 'RUB',
        subscriptionPlan: SubscriptionPlan.pro,
        subscriptionRenewsAt: DateTime(2099),
        pdfTemplate: template.id,
        pdfAccentColor: template.colors.accent,
      );
      final report = await PdfService.buildProjectReportPdf(
        detail: detail,
        profile: profile,
      );
      final catalog = await PdfService.buildCatalogPdf(
        items: const [
          CatalogItemModel(
            id: '1',
            category: 'Сантехника',
            title: 'Разводка труб водоснабжения',
            unit: 'м',
            unitPrice: 750,
            isCustom: true,
          ),
          CatalogItemModel(
            id: '2',
            category: 'Отделка',
            title: 'Укладка плитки',
            unit: 'м²',
            unitPrice: 2500,
            isCustom: true,
          ),
        ],
        profile: profile,
      );
      expect(report, isNotEmpty, reason: template.id);
      expect(catalog, isNotEmpty, reason: template.id);
      if (const bool.fromEnvironment('WRITE_SAMPLE_PDF')) {
        Directory('build/test_artifacts/pdfs').createSync(recursive: true);
        File(
          'build/test_artifacts/pdfs/report-${template.id}.pdf',
        ).writeAsBytesSync(report);
        File(
          'build/test_artifacts/pdfs/catalog-${template.id}.pdf',
        ).writeAsBytesSync(catalog);
      }
    }
  });

  test(
    'paginates a project report with many payers and long descriptions',
    () async {
      final bytes = await PdfService.buildProjectReportPdf(
        detail: ProjectDetail(
          project: project,
          transactions: [
            for (var i = 0; i < 90; i++)
              ProjectTransactionModel(
                id: '$i',
                projectId: project.id,
                type: i % 3 == 0
                    ? ProjectTransactionType.income
                    : ProjectTransactionType.expense,
                category: ProjectTransactionCategory.materials,
                title:
                    'Закупка облицовочного кирпича и доставка на строительный участок, этап $i',
                amount: 125000.50,
                payerName: 'Александр Константинович Иванов ${i % 8}',
                counterparty: 'Строймаркет, склад строительных материалов',
                transactionDate: DateTime(2026, 10, (i % 28) + 1),
              ),
          ],
        ),
        profile: null,
      );
      expect(bytes, isNotEmpty);
      if (const bool.fromEnvironment('CAPTURE_PROJECT_PAYMENTS')) {
        await File(
          'build/test_artifacts/project-payments-long.pdf',
        ).writeAsBytes(bytes);
      }
    },
  );
}
