import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart' as xls;

import 'models.dart';
import 'project_payment_summary.dart';

class ProjectExportService {
  const ProjectExportService._();

  static Uint8List buildWorkbook(ProjectDetail detail) {
    final workbook = xls.Excel.createExcel();
    final summary = workbook['Сводка'];
    final expenses = detail.transactions
        .where((item) => item.type == ProjectTransactionType.expense)
        .toList();
    final income = detail.transactions
        .where((item) => item.type == ProjectTransactionType.income)
        .toList();

    _writeSummary(summary, detail.project);
    _writeTransactionsSheet(workbook['Расходы'], expenses, 'Расходы');
    _writeTransactionsSheet(workbook['Поступления'], income, 'Поступления');
    _writePayersSheet(workbook['По плательщикам'], detail.transactions);

    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Сводка') {
      workbook.delete(defaultSheet);
    }
    final bytes = workbook.save();
    if (bytes == null) {
      throw StateError('Не удалось подготовить Excel-файл');
    }
    return Uint8List.fromList(bytes);
  }

  static void _writeSummary(xls.Sheet sheet, ProjectModel project) {
    sheet.appendRow([xls.TextCellValue('Отчёт по объекту')]);
    sheet.appendRow([xls.TextCellValue(project.title)]);
    sheet.appendRow([xls.TextCellValue('')]);
    sheet.appendRow([
      xls.TextCellValue('Параметр'),
      xls.TextCellValue('Значение'),
    ]);
    final values = <(String, xls.CellValue)>[
      ('Статус', xls.TextCellValue(ProjectStatus.label(project.status))),
      ('Адрес', xls.TextCellValue(project.objectAddress ?? '')),
      ('Заказчик / владелец', xls.TextCellValue(project.customerName ?? '')),
      ('Начало работ', xls.TextCellValue(formatDate(project.startDate))),
      (
        'Плановое завершение',
        xls.TextCellValue(
          project.targetDate == null ? '' : formatDate(project.targetDate!),
        ),
      ),
      ('Плановая выручка, ₽', xls.DoubleCellValue(project.plannedRevenue)),
      ('Получено, ₽', xls.DoubleCellValue(project.incomeAmount)),
      ('Потрачено, ₽', xls.DoubleCellValue(project.expenseAmount)),
      ('Фактическая прибыль, ₽', xls.DoubleCellValue(project.actualProfit)),
      ('Ожидаемая прибыль, ₽', xls.DoubleCellValue(project.expectedProfit)),
    ];
    for (final value in values) {
      sheet.appendRow([xls.TextCellValue(value.$1), value.$2]);
    }
    sheet.setColumnWidth(0, 30);
    sheet.setColumnWidth(1, 34);
    _styleCell(sheet, 'A1', _titleStyle);
    _styleCell(sheet, 'A2', _subtitleStyle);
    _styleHeader(sheet, 4, 2);
    for (var row = 10; row <= 14; row++) {
      _styleCell(sheet, 'B$row', _moneyStyle);
    }
  }

  static void _writeTransactionsSheet(
    xls.Sheet sheet,
    List<ProjectTransactionModel> transactions,
    String title,
  ) {
    sheet.appendRow([xls.TextCellValue(title)]);
    sheet.appendRow([xls.TextCellValue('')]);
    sheet.appendRow([
      xls.TextCellValue('Дата'),
      xls.TextCellValue('Операция'),
      xls.TextCellValue('Категория'),
      xls.TextCellValue('Количество'),
      xls.TextCellValue('Единица'),
      xls.TextCellValue('Контрагент'),
      xls.TextCellValue('Кто оплатил / от кого'),
      xls.TextCellValue('Комментарий'),
      xls.TextCellValue('Сумма, ₽'),
    ]);
    for (final item in transactions) {
      sheet.appendRow([
        xls.TextCellValue(formatDate(item.transactionDate)),
        xls.TextCellValue(item.title),
        xls.TextCellValue(item.category),
        item.quantity == null
            ? xls.TextCellValue('')
            : xls.DoubleCellValue(item.quantity!),
        xls.TextCellValue(item.unit ?? ''),
        xls.TextCellValue(item.counterparty ?? ''),
        xls.TextCellValue(item.effectivePayerName ?? 'Не указан'),
        xls.TextCellValue(item.notes ?? ''),
        xls.DoubleCellValue(item.amount),
      ]);
    }
    sheet.setColumnWidth(0, 14);
    sheet.setColumnWidth(1, 34);
    sheet.setColumnWidth(2, 22);
    sheet.setColumnWidth(3, 12);
    sheet.setColumnWidth(4, 12);
    sheet.setColumnWidth(5, 24);
    sheet.setColumnWidth(6, 24);
    sheet.setColumnWidth(7, 36);
    sheet.setColumnWidth(8, 18);
    _styleCell(sheet, 'A1', _titleStyle);
    _styleHeader(sheet, 3, 9);
    for (var row = 4; row <= transactions.length + 3; row++) {
      _styleCell(sheet, 'I$row', _moneyStyle);
    }
  }

  static void _writePayersSheet(
    xls.Sheet sheet,
    List<ProjectTransactionModel> transactions,
  ) {
    sheet.appendRow([
      xls.TextCellValue('Расходы и поступления по плательщикам'),
    ]);
    sheet.appendRow([xls.TextCellValue('')]);
    sheet.appendRow([
      for (final title in [
        'Тип',
        'Плательщик',
        'Всего, ₽',
        'Доля, %',
        'Дата',
        'За что',
        'Категория',
        'Получатель',
        'Сумма операции, ₽',
      ])
        xls.TextCellValue(title),
    ]);
    var row = 4;
    for (final type in [
      ProjectTransactionType.expense,
      ProjectTransactionType.income,
    ]) {
      final groups = groupProjectPayments(transactions, type: type);
      final total = groups.fold<double>(0, (sum, group) => sum + group.amount);
      for (final group in groups) {
        for (var index = 0; index < group.transactions.length; index++) {
          final item = group.transactions[index];
          sheet.appendRow([
            xls.TextCellValue(ProjectTransactionType.label(type)),
            xls.TextCellValue(group.label),
            index == 0
                ? xls.DoubleCellValue(group.amount)
                : xls.TextCellValue(''),
            index == 0
                ? xls.DoubleCellValue(group.shareOf(total) * 100)
                : xls.TextCellValue(''),
            xls.TextCellValue(formatDate(item.transactionDate)),
            xls.TextCellValue(item.title),
            xls.TextCellValue(item.category),
            xls.TextCellValue(item.counterparty ?? ''),
            xls.DoubleCellValue(item.amount),
          ]);
          _styleCell(sheet, 'C$row', _moneyStyle);
          _styleCell(sheet, 'I$row', _moneyStyle);
          row++;
        }
      }
    }
    for (var col = 0; col < 9; col++) {
      sheet.setColumnWidth(col, col == 5 ? 36 : 22);
    }
    _styleCell(sheet, 'A1', _titleStyle);
    _styleHeader(sheet, 3, 9);
  }

  static void _styleHeader(xls.Sheet sheet, int row, int columns) {
    for (var column = 0; column < columns; column++) {
      _styleCell(sheet, '${_columnLetter(column)}$row', _headerStyle);
    }
  }

  static void _styleCell(xls.Sheet sheet, String address, xls.CellStyle style) {
    sheet.cell(xls.CellIndex.indexByString(address)).cellStyle = style;
  }

  static String _columnLetter(int index) {
    var value = index + 1;
    var result = '';
    while (value > 0) {
      final remainder = (value - 1) % 26;
      result = String.fromCharCode(65 + remainder) + result;
      value = (value - 1) ~/ 26;
    }
    return result;
  }

  static final _titleStyle = xls.CellStyle(
    bold: true,
    fontSize: 18,
    fontColorHex: xls.ExcelColor.fromHexString('FF232221'),
  );
  static final _subtitleStyle = xls.CellStyle(
    bold: true,
    fontSize: 13,
    fontColorHex: xls.ExcelColor.fromHexString('FFD66B00'),
  );
  static final _headerStyle = xls.CellStyle(
    bold: true,
    fontColorHex: xls.ExcelColor.white,
    backgroundColorHex: xls.ExcelColor.fromHexString('FFF5820D'),
  );
  static final _moneyStyle = xls.CellStyle(
    bold: true,
    numberFormat: xls.CustomNumericNumFormat(formatCode: '#,##0 [\$₽-419]'),
  );
}
