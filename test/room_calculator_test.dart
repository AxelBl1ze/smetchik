import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smetchik/src/data/room_calculator.dart';
import 'package:smetchik/src/data/room_export_service.dart';
import 'package:excel_plus/excel_plus.dart' as xls;

void main() {
  ProjectRoom room({
    String shape = 'rectangle',
    List<RoomFinish> finishes = const [],
  }) => ProjectRoom(
    id: 'room',
    name: 'Кухня',
    walls: ProjectRoom.shape(shape),
    finishes: finishes,
  );
  RoomFinish paint({
    String name = 'Белая краска',
    RoomSurface surface = RoomSurface.walls,
    double coverage = 10,
    double can = 2.5,
    int coats = 2,
    double waste = 10,
  }) => RoomFinish(
    id: 'paint',
    name: name,
    kind: FinishKind.paint,
    surface: surface,
    coverage: coverage,
    canLitres: can,
    coats: coats,
    waste: waste,
  );

  test('rectangle, L shape and diagonal areas use the real dimensions', () {
    final rect = RoomGeometry(room())..validate();
    expect(rect.floorArea, 12);
    expect(rect.perimeter, 14);
    expect(rect.wallArea(), closeTo(37.8, 1e-8));
    final l = RoomGeometry(room(shape: 'l'))..validate();
    expect(l.floorArea, 9);
    expect(l.perimeter, 14);
    final diagonal = RoomGeometry(room(shape: 'diagonal'))..validate();
    expect(diagonal.floorArea, closeTo(11.625, 1e-8));
  });

  test(
    'open contour, branches, duplicates and disconnected loops are rejected',
    () {
      final base = room();
      for (final walls in [
        base.walls.take(3).toList(),
        [...base.walls, base.walls.first],
        [...base.walls, const RoomWall(PlanPoint(0, 0), PlanPoint(6, 6))],
        [...base.walls, ...ProjectRoom.shape('l')],
      ]) {
        expect(
          () => RoomGeometry(base.copyWith(walls: walls)).validate(),
          throwsFormatException,
        );
      }
    },
  );

  test('self-intersections and overlapping adjacent walls are rejected', () {
    List<RoomWall> polygon(List<PlanPoint> p) =>
        List.generate(p.length, (i) => RoomWall(p[i], p[(i + 1) % p.length]));
    expect(
      () => RoomGeometry(
        room().copyWith(
          walls: polygon(const [
            PlanPoint(0, 0),
            PlanPoint(12, 12),
            PlanPoint(12, 0),
            PlanPoint(0, 12),
          ]),
        ),
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => RoomGeometry(
        room().copyWith(
          walls: polygon(const [
            PlanPoint(0, 0),
            PlanPoint(12, 0),
            PlanPoint(6, 0),
            PlanPoint(6, 12),
            PlanPoint(0, 12),
          ]),
        ),
      ).validate(),
      throwsFormatException,
    );
  });

  test(
    'doors and windows are deducted, including only intersection with partial finish height',
    () {
      final base = room();
      final withOpenings = base.copyWith(
        openings: [
          RoomOpening(
            id: 'door',
            wallKey: base.walls[0].key,
            kind: OpeningKind.door,
            offset: .1,
            width: .9,
            height: 2.1,
          ),
          RoomOpening(
            id: 'window',
            wallKey: base.walls[1].key,
            kind: OpeningKind.window,
            offset: .2,
            width: 1.4,
            height: 1.3,
            sill: .8,
          ),
        ],
      );
      final geometry = RoomGeometry(withOpenings)..validate();
      expect(geometry.wallArea(), closeTo(34.09, 1e-8));
      expect(geometry.wallArea(height: 1), closeTo(12.82, 1e-8));
      expect(geometry.floorArea, 12);
      final result = RoomCalculator.calculate(withOpenings, paint());
      expect(result.amount, closeTo(7.4998, 1e-8));
      expect(result.packages, 3);
    },
  );

  test('openings outside wall, above ceiling and overlaps cannot be saved', () {
    final base = room();
    RoomOpening opening({
      double offset = 0,
      double width = 1,
      double height = 2,
      double sill = 0,
    }) => RoomOpening(
      id: 'o',
      wallKey: base.walls.first.key,
      kind: OpeningKind.window,
      offset: offset,
      width: width,
      height: height,
      sill: sill,
    );
    for (final openings in [
      [opening(offset: 3.5)],
      [opening(sill: 1)],
      [opening(), opening(offset: .5)],
      [opening(width: double.nan)],
    ]) {
      expect(
        () => RoomGeometry(base.copyWith(openings: openings)).validate(),
        throwsFormatException,
      );
    }
  });

  test('floor tile uses tile dimensions and pieces per pack, with reserve', () {
    const tile = RoomFinish(
      id: 'tile',
      name: 'Серая плитка',
      kind: FinishKind.tile,
      surface: RoomSurface.floor,
    );
    final result = RoomCalculator.calculate(room(), tile);
    expect(tile.packArea, closeTo(1.44, 1e-8));
    expect(result.amount, closeTo(13.2, 1e-8));
    expect(result.packages, 10);
  });

  test(
    'floor and wall tile can have separate names, packaging and heights',
    () {
      final base = room();
      final finishes = [
        const RoomFinish(
          id: 'floor',
          name: 'Пол',
          kind: FinishKind.tile,
          surface: RoomSurface.floor,
        ),
        RoomFinish(
          id: 'walls',
          name: 'Стены',
          kind: FinishKind.tile,
          surface: RoomSurface.walls,
          wallKeys: [base.walls.first.key],
          finishHeight: 1.2,
          tileWidth: 20,
          tileHeight: 20,
          tilesPerPack: 25,
          waste: 0,
        ),
      ];
      final groups = RoomCalculator.summarize([
        base.copyWith(finishes: finishes),
      ]);
      expect(groups, hasLength(2));
      expect(groups.last.area, closeTo(4.8, 1e-8));
      expect(groups.last.packages, 5);
    },
  );

  test('wallpaper is counted in strips, not gross square metres', () {
    const paper = RoomFinish(
      id: 'paper',
      name: 'Обои',
      kind: FinishKind.wallpaper,
      surface: RoomSurface.walls,
      waste: 0,
    );
    final base = room();
    final result = RoomCalculator.calculate(base, paper);
    expect(result.amount, 28);
    expect(result.packages, 10);
    final withDoor = base.copyWith(
      openings: [
        RoomOpening(
          id: 'door',
          wallKey: base.walls.first.key,
          kind: OpeningKind.door,
          offset: 1,
          width: 2,
          height: 2,
        ),
      ],
    );
    final doorResult = RoomCalculator.calculate(withDoor, paper);
    expect(doorResult.area, lessThan(result.area));
    expect(doorResult.packages, result.packages);
  });

  test('wallpaper rapport and trim affect cut length and roll yield', () {
    const paper = RoomFinish(
      id: 'p',
      name: 'Рисунок',
      kind: FinishKind.wallpaper,
      surface: RoomSurface.walls,
      repeat: .64,
      waste: 0,
      rollLength: 9,
    );
    final result = RoomCalculator.calculate(room(), paper);
    expect(result.stripLengths.first, closeTo(3.2, 1e-8));
    expect(result.packages, 14);
    expect(
      () => RoomCalculator.calculate(
        room(),
        const RoomFinish(
          id: 'p',
          name: 'Короткие',
          kind: FinishKind.wallpaper,
          surface: RoomSurface.walls,
          rollLength: 2,
        ),
      ),
      throwsFormatException,
    );
  });

  test('whole packages round after summing rooms, with shared leftovers', () {
    final f = paint(
      surface: RoomSurface.floor,
      coverage: 1,
      can: 3,
      coats: 1,
      waste: 0,
    );
    final a = room(finishes: [f]).copyWith(width: 1, depth: 1);
    final b = a.copyWith(name: 'Коридор');
    final groups = RoomCalculator.summarize([a, b]);
    expect(groups, hasLength(1));
    expect(groups.single.packages, 1);
    expect(groups.single.amount, 2);
    const paper = RoomFinish(
      id: 'p',
      name: 'Обои',
      kind: FinishKind.wallpaper,
      surface: RoomSurface.walls,
      waste: 0,
    );
    expect(
      RoomCalculator.summarize([
        room(finishes: [paper]),
        room(finishes: [paper]),
      ]).single.packages,
      19,
    );
  });

  test('different products and can volumes are not merged', () {
    final a = room(
      finishes: [
        paint(),
        paint(name: 'Синяя'),
        paint(can: 5),
      ],
    );
    expect(RoomCalculator.summarize([a]), hasLength(3));
  });

  test('wallpaper leftovers can fit shorter strips from another room', () {
    const paper = RoomFinish(
      id: 'p',
      name: 'Обои',
      kind: FinishKind.wallpaper,
      surface: RoomSurface.walls,
      waste: 0,
      rollWidth: 1,
      rollLength: 10,
      trim: 0,
    );
    final tall = room(
      finishes: [paper],
    ).copyWith(width: 1, depth: 1, height: 6);
    final short = room(
      finishes: [paper],
    ).copyWith(width: 1, depth: 1, height: 4);
    expect(RoomCalculator.summarize([tall, short]).single.packages, 4);
  });

  test('dense wallpaper strips have bounded calculation time', () {
    const paper = RoomFinish(
      id: 'p',
      name: 'Широкий объект',
      kind: FinishKind.wallpaper,
      surface: RoomSurface.walls,
      waste: 0,
      rollWidth: .01,
    );
    final timer = Stopwatch()..start();
    final result = RoomCalculator.calculate(
      room().copyWith(width: 200, depth: 200),
      paper,
    );
    expect(result.amount, 80000);
    expect(result.packages, 26667);
    expect(timer.elapsedMilliseconds, lessThan(2000));
  });

  test('invalid numeric parameters are rejected without infinities', () {
    for (final f in [
      paint(coverage: 0),
      paint(can: 0),
      paint(waste: -1),
      paint(coats: 21),
      paint(coverage: double.nan),
    ]) {
      expect(() => RoomCalculator.calculate(room(), f), throwsFormatException);
    }
    expect(
      () => RoomGeometry(room().copyWith(width: double.infinity)).validate(),
      throwsFormatException,
    );
    expect(RoomCalculator.roundUp(10.00000000001), 10);
    expect(RoomCalculator.roundUp(1e-12), 1);
  });

  test(
    'interior corner dimensions preserve perpendiculars and update wall references',
    () {
      final base = room(shape: 'l');
      final corner = base.walls[2].b;
      final f = RoomFinish(
        id: 't',
        name: 'Стена',
        kind: FinishKind.tile,
        surface: RoomSurface.walls,
        wallKeys: [base.walls[2].key],
      );
      final initial = base.copyWith(finishes: [f]);
      final moved = RoomGeometry(initial).positionCorner(corner, 1.15, .7);
      expect(RoomGeometry(moved).floorArea, closeTo(5.445, 1e-8));
      final metric = RoomGeometry(moved).metric(moved.walls[2].b);
      expect(metric.x, closeTo(1.15, 1e-8));
      expect(metric.y, closeTo(.7, 1e-8));
      expect(moved.finishes.single.wallKeys.single, moved.walls[2].key);
      RoomGeometry(moved).validate();
    },
  );

  test(
    'room round trips through JSON with plan, openings and finishes intact',
    () {
      final base = room(finishes: [paint()]);
      final original = base.copyWith(
        openings: [
          RoomOpening(
            id: 'w',
            wallKey: base.walls.first.key,
            kind: OpeningKind.window,
            offset: .4,
            width: 1,
            height: 1,
            sill: 1,
          ),
        ],
      );
      final row =
          jsonDecode(
                jsonEncode({
                  'id': original.id,
                  'revision': 3,
                  'data': original.toMap(),
                }),
              )
              as Map<String, dynamic>;
      final restored = ProjectRoom.fromRow(row);
      expect(restored.toMap(), original.toMap());
      expect(restored.revision, 3);
    },
  );

  test(
    'Excel includes rooms, procurement, per-room calculations and openings',
    () {
      final base = room(finishes: [paint()]);
      final bytes = RoomExportService.workbook('Квартира', [base]);
      final book = xls.Excel.decodeBytes(bytes);
      expect(
        book.tables.keys,
        containsAll(['Помещения', 'К закупке', 'По помещениям', 'Проёмы']),
      );
      expect(book['К закупке'].rows[2][0]!.value.toString(), 'Белая краска');
      expect(book['По помещениям'].rows[2][0]!.value.toString(), 'Кухня');
    },
  );
}
