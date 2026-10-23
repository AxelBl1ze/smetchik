import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:geometry_kit/geometry_kit.dart' as geo;

class PlanPoint {
  const PlanPoint(this.x, this.y);
  final double x;
  final double y;
  String get key => '$x,$y';
  Map<String, dynamic> toMap() => {'x': x, 'y': y};
  factory PlanPoint.fromMap(Map<String, dynamic> m) =>
      PlanPoint((m['x'] as num).toDouble(), (m['y'] as num).toDouble());
}

class RoomWall {
  const RoomWall(this.a, this.b);
  final PlanPoint a;
  final PlanPoint b;
  String get key =>
      a.key.compareTo(b.key) < 0 ? '${a.key}/${b.key}' : '${b.key}/${a.key}';
  Map<String, dynamic> toMap() => {'a': a.toMap(), 'b': b.toMap()};
  factory RoomWall.fromMap(Map<String, dynamic> m) => RoomWall(
    PlanPoint.fromMap(Map<String, dynamic>.from(m['a'] as Map)),
    PlanPoint.fromMap(Map<String, dynamic>.from(m['b'] as Map)),
  );
}

enum OpeningKind { door, window }

class RoomOpening {
  const RoomOpening({
    required this.id,
    required this.wallKey,
    required this.kind,
    required this.offset,
    required this.width,
    required this.height,
    this.sill = 0,
  });
  final String id;
  final String wallKey;
  final OpeningKind kind;

  /// Metres from the wall's stored first endpoint.
  final double offset;
  final double width;
  final double height;
  final double sill;
  Map<String, dynamic> toMap() => {
    'id': id,
    'wall': wallKey,
    'kind': kind.name,
    'offset': offset,
    'width': width,
    'height': height,
    'sill': sill,
  };
  factory RoomOpening.fromMap(Map<String, dynamic> m) => RoomOpening(
    id: m['id'] as String,
    wallKey: m['wall'] as String,
    kind: OpeningKind.values.byName(m['kind'] as String),
    offset: (m['offset'] as num).toDouble(),
    width: (m['width'] as num).toDouble(),
    height: (m['height'] as num).toDouble(),
    sill: (m['sill'] as num? ?? 0).toDouble(),
  );
}

enum RoomSurface {
  floor('Пол'),
  walls('Стены'),
  ceiling('Потолок');

  const RoomSurface(this.label);
  final String label;
}

enum FinishKind {
  tile('Плитка', 'уп.'),
  paint('Краска', 'бан.'),
  wallpaper('Обои', 'рул.');

  const FinishKind(this.label, this.unit);
  final String label;
  final String unit;
}

class RoomFinish {
  const RoomFinish({
    required this.id,
    required this.name,
    required this.kind,
    required this.surface,
    this.wallKeys = const [],
    this.finishHeight = 0,
    this.waste = 10,
    this.tileWidth = 30,
    this.tileHeight = 60,
    this.tilesPerPack = 8,
    this.coverage = 10,
    this.coats = 2,
    this.canLitres = 2.5,
    this.rollWidth = .53,
    this.rollLength = 10.05,
    this.repeat = 0,
    this.trim = .1,
  });
  final String id;
  final String name;
  final FinishKind kind;
  final RoomSurface surface;
  final List<String> wallKeys;

  /// Zero means full room height.
  final double finishHeight;
  final double waste;

  /// Tile size is in centimetres; all other lengths are in metres.
  final double tileWidth, tileHeight;
  final int tilesPerPack;
  final double coverage, canLitres;
  final int coats;
  final double rollWidth, rollLength, repeat, trim;
  double get packArea => tileWidth * tileHeight / 10000 * tilesPerPack;

  // Only identical products AND packing specifications can share leftovers.
  String get groupKey => jsonEncode([
    name.trim().toLowerCase(),
    kind.name,
    switch (kind) {
      FinishKind.tile => [tileWidth, tileHeight, tilesPerPack],
      FinishKind.paint => [coverage, canLitres],
      FinishKind.wallpaper => [rollWidth, rollLength, repeat, trim],
    },
  ]);
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'surface': surface.name,
    'walls': wallKeys,
    'finishHeight': finishHeight,
    'waste': waste,
    'tileWidth': tileWidth,
    'tileHeight': tileHeight,
    'tilesPerPack': tilesPerPack,
    'coverage': coverage,
    'coats': coats,
    'canLitres': canLitres,
    'rollWidth': rollWidth,
    'rollLength': rollLength,
    'repeat': repeat,
    'trim': trim,
  };
  factory RoomFinish.fromMap(Map<String, dynamic> m) => RoomFinish(
    id: m['id'] as String,
    name: m['name'] as String,
    kind: FinishKind.values.byName(m['kind'] as String),
    surface: RoomSurface.values.byName(m['surface'] as String),
    wallKeys: (m['walls'] as List? ?? []).cast<String>(),
    finishHeight: _n(m, 'finishHeight', 0),
    waste: _n(m, 'waste', 10),
    tileWidth: _n(m, 'tileWidth', 30),
    tileHeight: _n(m, 'tileHeight', 60),
    tilesPerPack: _n(m, 'tilesPerPack', 8).toInt(),
    coverage: _n(m, 'coverage', 10),
    coats: _n(m, 'coats', 2).toInt(),
    canLitres: _n(m, 'canLitres', 2.5),
    rollWidth: _n(m, 'rollWidth', .53),
    rollLength: _n(m, 'rollLength', 10.05),
    repeat: _n(m, 'repeat', 0),
    trim: _n(m, 'trim', .1),
  );
  static double _n(Map<String, dynamic> m, String k, double d) =>
      (m[k] as num? ?? d).toDouble();
}

class ProjectRoom {
  const ProjectRoom({
    required this.id,
    required this.name,
    required this.walls,
    this.width = 4,
    this.depth = 3,
    this.height = 2.7,
    this.openings = const [],
    this.finishes = const [],
    this.revision = 0,
  });
  final String id, name;
  final List<RoomWall> walls;
  final double width, depth, height;
  final List<RoomOpening> openings;
  final List<RoomFinish> finishes;
  final int revision;
  ProjectRoom copyWith({
    String? name,
    List<RoomWall>? walls,
    double? width,
    double? depth,
    double? height,
    List<RoomOpening>? openings,
    List<RoomFinish>? finishes,
    int? revision,
  }) => ProjectRoom(
    id: id,
    name: name ?? this.name,
    walls: walls ?? this.walls,
    width: width ?? this.width,
    depth: depth ?? this.depth,
    height: height ?? this.height,
    openings: openings ?? this.openings,
    finishes: finishes ?? this.finishes,
    revision: revision ?? this.revision,
  );
  Map<String, dynamic> toMap() => {
    'name': name,
    'width': width,
    'depth': depth,
    'height': height,
    'walls': walls.map((w) => w.toMap()).toList(),
    'openings': openings.map((o) => o.toMap()).toList(),
    'finishes': finishes.map((f) => f.toMap()).toList(),
  };
  factory ProjectRoom.fromRow(Map<String, dynamic> row) {
    final m = Map<String, dynamic>.from(row['data'] as Map);
    List<T> read<T>(String key, T Function(Map<String, dynamic>) parse) =>
        (m[key] as List)
            .map((v) => parse(Map<String, dynamic>.from(v as Map)))
            .toList();
    return ProjectRoom(
      id: row['id'] as String,
      name: m['name'] as String,
      walls: read('walls', RoomWall.fromMap),
      width: (m['width'] as num).toDouble(),
      depth: (m['depth'] as num).toDouble(),
      height: (m['height'] as num).toDouble(),
      openings: read('openings', RoomOpening.fromMap),
      finishes: read('finishes', RoomFinish.fromMap),
      revision: (row['revision'] as num).toInt(),
    );
  }

  static List<RoomWall> shape(String shape) {
    final points = switch (shape) {
      'l' => const [
        PlanPoint(0, 0),
        PlanPoint(12, 0),
        PlanPoint(12, 6),
        PlanPoint(6, 6),
        PlanPoint(6, 12),
        PlanPoint(0, 12),
      ],
      'diagonal' => const [
        PlanPoint(0, 0),
        PlanPoint(9, 0),
        PlanPoint(12, 3),
        PlanPoint(12, 12),
        PlanPoint(0, 12),
      ],
      _ => const [
        PlanPoint(0, 0),
        PlanPoint(12, 0),
        PlanPoint(12, 12),
        PlanPoint(0, 12),
      ],
    };
    return List.generate(
      points.length,
      (i) => RoomWall(points[i], points[(i + 1) % points.length]),
    );
  }
}

class RoomGeometry {
  RoomGeometry(this.room);
  final ProjectRoom room;

  List<PlanPoint> get outline {
    if (room.walls.length < 3 || room.walls.length > 64) {
      throw const FormatException(
        'Замкните контур помещения: нужно не менее трёх стен.',
      );
    }
    final adjacency = <String, List<RoomWall>>{};
    for (final wall in room.walls) {
      for (final p in [wall.a, wall.b]) {
        if (!p.x.isFinite ||
            !p.y.isFinite ||
            p.x < 0 ||
            p.x > 12 ||
            p.y < 0 ||
            p.y > 12) {
          throw const FormatException(
            'Точки плана должны находиться на сетке.',
          );
        }
        adjacency.putIfAbsent(p.key, () => []).add(wall);
      }
      if (wall.a.key == wall.b.key) {
        throw const FormatException('Стена не может иметь нулевую длину.');
      }
    }
    if (adjacency.values.any((list) => list.length != 2) ||
        room.walls.map((w) => w.key).toSet().length != room.walls.length) {
      throw const FormatException(
        'Контур должен быть замкнутым, без разрывов и ответвлений.',
      );
    }
    final points = <PlanPoint>[];
    final visited = <String>{};
    var point = room.walls.first.a;
    while (visited.length < room.walls.length) {
      points.add(point);
      final next = adjacency[point.key]!.where((w) => !visited.contains(w.key));
      if (next.isEmpty) break;
      final wall = next.first;
      visited.add(wall.key);
      point = wall.a.key == point.key ? wall.b : wall.a;
    }
    if (visited.length != room.walls.length || point.key != points.first.key) {
      throw const FormatException(
        'В одном помещении должен быть один замкнутый контур.',
      );
    }
    final poly = geo.Polygon(points.map((p) => geo.Point(p.x, p.y)).toList());
    for (var i = 0; i < poly.edges.length; i++) {
      for (var j = i + 1; j < poly.edges.length; j++) {
        if (j == i + 1 || (i == 0 && j == poly.edges.length - 1)) continue;
        final a = poly.edges[i], b = poly.edges[j];
        if (a.intersect(b) ||
            a.hasPoint(b.a) ||
            a.hasPoint(b.b) ||
            b.hasPoint(a.a) ||
            b.hasPoint(a.b)) {
          throw const FormatException(
            'Стены пересекаются. Исправьте контур помещения.',
          );
        }
      }
    }
    // Adjacent collinear walls must not double back over one another.
    for (var i = 0; i < poly.edges.length; i++) {
      final a = poly.edges[i], b = poly.edges[(i + 1) % poly.edges.length];
      if (a.hasPoint(b.b) || b.hasPoint(a.a)) {
        throw const FormatException('Стены накладываются друг на друга.');
      }
    }
    if (poly.area < .01) {
      throw const FormatException('У помещения нет площади.');
    }
    return points;
  }

  geo.Point metric(PlanPoint p) {
    final all = room.walls.expand((w) => [w.a, w.b]);
    final minX = all.map((p) => p.x).reduce(math.min);
    final maxX = all.map((p) => p.x).reduce(math.max);
    final minY = all.map((p) => p.y).reduce(math.min);
    final maxY = all.map((p) => p.y).reduce(math.max);
    return geo.Point(
      maxX == minX ? 0 : (p.x - minX) / (maxX - minX) * room.width,
      maxY == minY ? 0 : (p.y - minY) / (maxY - minY) * room.depth,
    );
  }

  geo.Polygon get polygon => geo.Polygon(outline.map(metric).toList());
  double get floorArea => polygon.area;
  double get perimeter => polygon.perimeter;
  double wallLength(RoomWall wall) =>
      geo.Line(metric(wall.a), metric(wall.b)).length;

  /// Move the internal X/Y rails together, preserving perpendicular walls in
  /// L-shaped plans. Overall bounds remain controlled by width/depth inputs.
  ProjectRoom positionCorner(PlanPoint corner, double x, double y) {
    final origin = metric(corner);
    if (!x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        x > room.width ||
        y < 0 ||
        y > room.depth) {
      throw const FormatException(
        'Угол должен оставаться внутри размеров помещения.',
      );
    }
    final points = room.walls.expand((w) => [w.a, w.b]).toList();
    final minX = points.map((p) => p.x).reduce(math.min);
    final maxX = points.map((p) => p.x).reduce(math.max);
    final minY = points.map((p) => p.y).reduce(math.min);
    final maxY = points.map((p) => p.y).reduce(math.max);
    final interiorX = origin.x > 1e-7 && origin.x < room.width - 1e-7;
    final interiorY = origin.y > 1e-7 && origin.y < room.depth - 1e-7;
    PlanPoint move(PlanPoint p) => PlanPoint(
      interiorX && p.x == corner.x
          ? minX + x / room.width * (maxX - minX)
          : p.x,
      interiorY && p.y == corner.y
          ? minY + y / room.depth * (maxY - minY)
          : p.y,
    );
    final walls = room.walls
        .map((w) => RoomWall(move(w.a), move(w.b)))
        .toList();
    final keys = {
      for (var i = 0; i < walls.length; i++) room.walls[i].key: walls[i].key,
    };
    final result = room.copyWith(
      walls: walls,
      openings: room.openings
          .map(
            (o) => RoomOpening.fromMap({...o.toMap(), 'wall': keys[o.wallKey]}),
          )
          .toList(),
      finishes: room.finishes
          .map(
            (f) => RoomFinish.fromMap({
              ...f.toMap(),
              'walls': f.wallKeys.map((key) => keys[key]).toList(),
            }),
          )
          .toList(),
    );
    RoomGeometry(result).validate();
    for (final f in result.finishes) {
      RoomCalculator.calculate(result, f);
    }
    return result;
  }

  List<RoomWall> selectedWalls(RoomFinish finish) => finish.wallKeys.isEmpty
      ? room.walls
      : room.walls.where((w) => finish.wallKeys.contains(w.key)).toList();
  double wallArea({double? height, List<RoomWall>? walls}) {
    final h = height ?? room.height;
    final selected = walls ?? room.walls;
    var area = selected.fold<double>(0, (s, w) => s + wallLength(w) * h);
    for (final o in room.openings) {
      if (!selected.any((w) => w.key == o.wallKey)) continue;
      area -= o.width * math.max(0, math.min(h, o.sill + o.height) - o.sill);
    }
    return math.max(0, area);
  }

  void validate() {
    outline;
    for (final value in [room.width, room.depth, room.height]) {
      if (!value.isFinite || value < .1 || value > 200) {
        throw const FormatException(
          'Размеры помещения должны быть от 0,1 до 200 м.',
        );
      }
    }
    if (room.name.trim().isEmpty || room.name.length > 120) {
      throw const FormatException(
        'Укажите название помещения, не длиннее 120 символов.',
      );
    }
    if (room.openings.length > 64 || room.finishes.length > 60) {
      throw const FormatException(
        'В помещении слишком много проёмов или материалов.',
      );
    }
    for (final o in room.openings) {
      final walls = room.walls.where((w) => w.key == o.wallKey);
      if (walls.isEmpty ||
          [o.offset, o.width, o.height, o.sill].any((n) => !n.isFinite) ||
          o.width <= 0 ||
          o.height <= 0 ||
          o.sill < 0 ||
          o.offset < 0 ||
          o.offset + o.width > wallLength(walls.first) + 1e-7 ||
          o.height + o.sill > room.height + 1e-7) {
        throw const FormatException(
          'Проём выходит за пределы стены. Проверьте размеры и отступ.',
        );
      }
      for (final other in room.openings) {
        if (identical(o, other) || o.wallKey != other.wallKey) continue;
        if (o.offset < other.offset + other.width - 1e-7 &&
            other.offset < o.offset + o.width - 1e-7 &&
            o.sill < other.sill + other.height - 1e-7 &&
            other.sill < o.sill + o.height - 1e-7) {
          throw const FormatException(
            'Проёмы на одной стене не должны пересекаться.',
          );
        }
      }
    }
  }
}

class FinishRequirement {
  const FinishRequirement({
    required this.finish,
    required this.roomName,
    required this.area,
    required this.amount,
    required this.packages,
    this.stripLengths = const [],
  });
  final RoomFinish finish;
  final String roomName;
  final double area;

  /// Litres, tile m², or full-height wallpaper strips including reserve.
  final double amount;
  final int packages;
  final List<double> stripLengths;
  String get amountUnit => switch (finish.kind) {
    FinishKind.paint => 'л',
    FinishKind.tile => 'м²',
    FinishKind.wallpaper => 'полос',
  };
}

class MaterialRequirement {
  const MaterialRequirement(this.items, this.packages);
  final List<FinishRequirement> items;
  final int packages;
  RoomFinish get finish => items.first.finish;
  double get area => items.fold(0, (s, i) => s + i.area);
  double get amount => items.fold(0, (s, i) => s + i.amount);
}

class RoomCalculator {
  static int roundUp(double value) {
    final nearest = value.round();
    if (nearest > 0 && (value - nearest).abs() < 1e-9) return nearest;
    return value.ceil();
  }

  static FinishRequirement calculate(ProjectRoom room, RoomFinish f) {
    final g = RoomGeometry(room)..validate();
    void positive(double v) {
      if (!v.isFinite || v <= 0 || v > 100000) {
        throw const FormatException(
          'Проверьте параметры материала: значения должны быть больше нуля.',
        );
      }
    }

    if (f.name.trim().isEmpty ||
        f.name.length > 120 ||
        !f.waste.isFinite ||
        f.waste < 0 ||
        f.waste > 100 ||
        !f.finishHeight.isFinite ||
        f.finishHeight < 0 ||
        f.finishHeight > room.height ||
        f.wallKeys.any((key) => !room.walls.any((w) => w.key == key))) {
      throw const FormatException(
        'Проверьте название, запас и выбранные стены материала.',
      );
    }
    final h = f.finishHeight == 0 ? room.height : f.finishHeight;
    final walls = g.selectedWalls(f);
    final area = f.surface == RoomSurface.walls
        ? g.wallArea(height: h, walls: walls)
        : g.floorArea;
    if (area <= 1e-7) {
      throw const FormatException('Нет площади для отделки. Проверьте проёмы.');
    }
    final reserve = 1 + f.waste / 100;
    double amount;
    int count;
    var strips = <double>[];
    switch (f.kind) {
      case FinishKind.tile:
        positive(f.tileWidth);
        positive(f.tileHeight);
        positive(f.tilesPerPack.toDouble());
        amount = area * reserve;
        count = roundUp(amount / f.packArea);
      case FinishKind.paint:
        positive(f.coverage);
        positive(f.canLitres);
        positive(f.coats.toDouble());
        if (f.coats > 20) {
          throw const FormatException('Укажите не более 20 слоёв.');
        }
        amount = area * f.coats / f.coverage * reserve;
        count = roundUp(amount / f.canLitres);
      case FinishKind.wallpaper:
        if (f.surface != RoomSurface.walls) {
          throw const FormatException('Обои рассчитываются для стен.');
        }
        positive(f.rollWidth);
        positive(f.rollLength);
        if (!f.repeat.isFinite ||
            !f.trim.isFinite ||
            f.repeat < 0 ||
            f.repeat > 5 ||
            f.trim < 0 ||
            f.trim > 1) {
          throw const FormatException(
            'Проверьте раппорт и припуск на подрезку.',
          );
        }
        var cut = h + f.trim;
        if (f.repeat > 0) cut = roundUp(cut / f.repeat) * f.repeat;
        if (cut > f.rollLength + 1e-7) {
          throw const FormatException(
            'Длины рулона не хватает на одну полосу с подрезкой и раппортом.',
          );
        }
        final n = walls.fold<int>(
          0,
          (s, w) => s + roundUp(g.wallLength(w) / f.rollWidth),
        );
        final reserved = roundUp(n * reserve);
        if (reserved > 100000) {
          throw const FormatException(
            'Слишком много полос. Проверьте ширину рулона.',
          );
        }
        strips = List.filled(reserved, cut);
        amount = reserved.toDouble();
        count = _rolls(strips, f.rollLength);
    }
    return FinishRequirement(
      finish: f,
      roomName: room.name,
      area: area,
      amount: amount,
      packages: count,
      stripLengths: strips,
    );
  }

  static List<MaterialRequirement> summarize(List<ProjectRoom> rooms) {
    final groups = <String, List<FinishRequirement>>{};
    for (final room in rooms) {
      for (final f in room.finishes) {
        groups.putIfAbsent(f.groupKey, () => []).add(calculate(room, f));
      }
    }
    return groups.values.map((items) {
      final f = items.first.finish;
      final amount = items.fold<double>(0, (s, i) => s + i.amount);
      final packages = switch (f.kind) {
        FinishKind.paint => roundUp(amount / f.canLitres),
        FinishKind.tile => roundUp(amount / f.packArea),
        FinishKind.wallpaper => _rolls(
          items.expand((i) => i.stripLengths).toList(),
          f.rollLength,
        ),
      };
      return MaterialRequirement(items, packages);
    }).toList();
  }

  /// Best-fit decreasing: reuses whole-strip leftovers across rooms without
  /// joining short offcuts into a full-height strip.
  static int _rolls(List<double> lengths, double capacity) {
    if (lengths.isEmpty) return 0;
    if (lengths.every((length) => (length - lengths.first).abs() < 1e-9)) {
      final stripsPerRoll = ((capacity + 1e-7) / lengths.first).floor();
      return roundUp(lengths.length / stripsPerRoll);
    }
    final remaining = SplayTreeMap<double, int>();
    final sorted = [...lengths]..sort((a, b) => b.compareTo(a));
    var rolls = 0;
    for (final length in sorted) {
      final space = remaining.firstKeyAfter(length - 1e-7);
      double rest;
      if (space == null) {
        rolls++;
        rest = capacity - length;
      } else {
        final count = remaining[space]!;
        if (count == 1) {
          remaining.remove(space);
        } else {
          remaining[space] = count - 1;
        }
        rest = space - length;
      }
      if (rest > 1e-7) remaining.update(rest, (n) => n + 1, ifAbsent: () => 1);
    }
    return rolls;
  }
}
