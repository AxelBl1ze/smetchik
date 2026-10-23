import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart' as xls;

import 'room_calculator.dart';

class RoomExportService {
  static String specification(RoomFinish f) => switch (f.kind) {
    FinishKind.tile =>
      '${f.tileWidth} × ${f.tileHeight} см; ${f.tilesPerPack} шт/уп.; ${f.packArea.toStringAsFixed(3)} м²/уп.',
    FinishKind.paint => '${f.coverage} м²/л за слой; ${f.canLitres} л/бан.',
    FinishKind.wallpaper =>
      '${f.rollWidth} × ${f.rollLength} м; раппорт ${f.repeat * 100} см; подрезка ${f.trim * 100} см',
  };

  static Uint8List workbook(String title, List<ProjectRoom> rooms) {
    final book = xls.Excel.createExcel();
    void write(String name, List<String> headers, List<List<Object>> rows) {
      final sheet = book[name];
      sheet.appendRow([xls.TextCellValue(title)]);
      sheet.appendRow(headers.map(xls.TextCellValue.new).toList());
      for (final row in rows) {
        sheet.appendRow(
          row
              .map<xls.CellValue>(
                (v) => v is num
                    ? xls.DoubleCellValue(v.toDouble())
                    : xls.TextCellValue(v.toString()),
              )
              .toList(),
        );
      }
      for (var i = 0; i < headers.length; i++) {
        sheet.setColumnWidth(i, i == 0 ? 28 : 24);
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1))
            .cellStyle = xls.CellStyle(
          bold: true,
          fontColorHex: xls.ExcelColor.fromHexString('#FFFFFF'),
          backgroundColorHex: xls.ExcelColor.fromHexString('#1A1A1A'),
        );
      }
    }

    write(
      'Помещения',
      [
        'Помещение',
        'Ширина, м',
        'Длина, м',
        'Высота, м',
        'Пол / потолок, м²',
        'Стены без проёмов, м²',
        'Периметр, м',
      ],
      [
        for (final room in rooms)
          [
            room.name,
            room.width,
            room.depth,
            room.height,
            RoomGeometry(room).floorArea,
            RoomGeometry(room).wallArea(),
            RoomGeometry(room).perimeter,
          ],
      ],
    );
    write(
      'К закупке',
      [
        'Материал',
        'Вид',
        'Упаковок / рулонов / банок',
        'Единица',
        'Площадь, м²',
        'Параметры',
      ],
      [
        for (final group in RoomCalculator.summarize(rooms))
          [
            group.finish.name,
            group.finish.kind.label,
            group.packages,
            group.finish.kind.unit,
            group.area,
            specification(group.finish),
          ],
      ],
    );
    write(
      'По помещениям',
      [
        'Помещение',
        'Материал',
        'Поверхность',
        'Площадь, м²',
        'Запас, %',
        'Потребность с запасом',
        'Единица потребности',
        'Слоёв',
        'Высота отделки, м',
        'Стены',
        'Параметры',
      ],
      [
        for (final room in rooms)
          for (final f in room.finishes)
            [
              room.name,
              f.name,
              f.surface.label,
              RoomCalculator.calculate(room, f).area,
              f.waste,
              RoomCalculator.calculate(room, f).amount,
              RoomCalculator.calculate(room, f).amountUnit,
              f.kind == FinishKind.paint ? f.coats : '',
              f.surface == RoomSurface.walls
                  ? (f.finishHeight == 0 ? room.height : f.finishHeight)
                  : '',
              f.surface != RoomSurface.walls
                  ? ''
                  : f.wallKeys.isEmpty
                  ? 'Все'
                  : room.walls
                        .asMap()
                        .entries
                        .where((e) => f.wallKeys.contains(e.value.key))
                        .map((e) => e.key + 1)
                        .join(', '),
              specification(f),
            ],
      ],
    );
    write(
      'Проёмы',
      [
        'Помещение',
        'Вид',
        'Стена',
        'Отступ, м',
        'Ширина, м',
        'Высота, м',
        'От пола, м',
      ],
      [
        for (final room in rooms)
          for (final o in room.openings)
            [
              room.name,
              o.kind == OpeningKind.door ? 'Дверь' : 'Окно',
              room.walls.indexWhere((w) => w.key == o.wallKey) + 1,
              o.offset,
              o.width,
              o.height,
              o.sill,
            ],
      ],
    );
    book['К закупке'].appendRow([
      xls.TextCellValue(
        'Округление выполнено после объединения одинаковых материалов. Обои: полноразмерные полосы, без вычета проёмов. '
        'Результат предварительный: сверьте маркировку и раскладку перед покупкой.',
      ),
    ]);
    final initial = book.getDefaultSheet();
    if (initial != null && initial != 'Помещения') book.delete(initial);
    final bytes = book.save();
    if (bytes == null) {
      throw Exception('Не удалось подготовить ведомость материалов.');
    }
    return Uint8List.fromList(bytes);
  }
}
