import 'package:excel_plus/excel_plus.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/data/pdf_service.dart';
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
        transactionDate: DateTime(2026, 7, 3),
      ),
      ProjectTransactionModel(
        id: 'income-1',
        projectId: project.id,
        type: ProjectTransactionType.income,
        category: 'Оплата',
        title: 'Аванс',
        amount: 400000,
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
      containsAll(['Сводка', 'Расходы', 'Поступления']),
    );
  });

  test('creates PDF project report', () async {
    final bytes = await PdfService.buildProjectReportPdf(
      detail: detail,
      profile: null,
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
