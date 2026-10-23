import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smetchik/src/core/app_theme.dart';
import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/data/repository.dart';
import 'package:smetchik/src/data/room_calculator.dart';
import 'package:smetchik/src/data/room_repository.dart';
import 'package:smetchik/src/features/projects/project_rooms_screen.dart';
import 'package:smetchik/src/features/projects/room_editor_screen.dart';
import 'package:smetchik/src/features/projects/room_plan_view.dart';

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Inter');
    for (final file in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Inter-$file.ttf'));
    }
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
  }

  ProjectRoom room({bool saved = false}) {
    final base = ProjectRoom(
      id: 'room',
      name: saved ? 'Кухня' : '',
      walls: ProjectRoom.shape('l'),
      revision: saved ? 1 : 0,
    );
    if (!saved) return base;
    return base.copyWith(
      openings: [
        RoomOpening(
          id: 'window',
          wallKey: base.walls.first.key,
          kind: OpeningKind.window,
          offset: 1,
          width: 1.4,
          height: 1.3,
          sill: .8,
        ),
      ],
      finishes: const [
        RoomFinish(
          id: 'tile',
          name: 'Керамогранит, серый 30×60',
          kind: FinishKind.tile,
          surface: RoomSurface.floor,
        ),
        RoomFinish(
          id: 'paint',
          name: 'Краска белая, матовая',
          kind: FinishKind.paint,
          surface: RoomSurface.ceiling,
        ),
      ],
    );
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(
    WidgetTester tester,
    GlobalKey key,
    String name,
  ) async {
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/test_artifacts/rooms').createSync(recursive: true);
      File(
        'build/test_artifacts/rooms/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('new room: confirm plan, calculate floor tile, save and return', (
    tester,
  ) async {
    viewport(tester, const Size(393, 852));
    ProjectRoom? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RoomEditorScreen(
                    initial: room(),
                    onSave: (room) async {
                      saved = room;
                      return room.copyWith(revision: 1);
                    },
                  ),
                ),
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Гараж');
    await tapVisible(tester, find.text('Подтвердить план'));
    await tapVisible(tester, find.text('Рассчитать материал'));
    await tester.enterText(field('Название материала'), 'Серая плитка');
    await tapVisible(tester, find.text('Рассчитать'));
    expect(find.text('Серая плитка'), findsOneWidget);
    await tester.tap(find.text('Сохранить помещение'));
    await tester.pumpAndSettle();
    expect(saved?.name, 'Гараж');
    expect(saved?.finishes.single.surface, RoomSurface.floor);
    expect(find.text('Открыть'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tapping a wall removes it; drawing its endpoints restores the closed plan',
    (tester) async {
      viewport(tester, const Size(393, 852));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: RoomEditorScreen(
            initial: ProjectRoom(
              id: 'r',
              name: 'Комната',
              walls: ProjectRoom.shape('rectangle'),
            ),
            onSave: (r) async => r,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final view = find.byType(RoomPlanView);
      final rect = RoomPlanView.drawingRect(tester.getSize(view), false);
      final origin = tester.getTopLeft(view);
      await tester.tapAt(origin + rect.topCenter);
      await tester.pumpAndSettle();
      expect(find.textContaining('без разрывов'), findsOneWidget);
      await tester.tapAt(origin + rect.topLeft);
      await tester.pumpAndSettle();
      await tester.tapAt(origin + rect.topRight);
      await tester.pumpAndSettle();
      expect(find.textContaining('без разрывов'), findsNothing);
      await tapVisible(tester, find.text('Подтвердить план'));
      expect(find.text('Изменить'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(393, 852),
    const Size(320, 568),
    const Size(844, 390),
  ]) {
    testWidgets(
      'opening and material forms stay visible with keyboard at $size',
      (tester) async {
        viewport(tester, size);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: RoomEditorScreen(
              initial: room(saved: true),
              onSave: (r) async => r,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapVisible(tester, find.byTooltip('Добавить проём'));
        final offset = field('Отступ от начала стены');
        await tapVisible(tester, offset);
        final keyboard = size.height < 500
            ? 210.0
            : size.width < 350
            ? 300.0
            : 340.0;
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(offset).bottom,
          lessThanOrEqualTo(size.height - keyboard),
        );
        await tester.enterText(offset, '0,5');
        expect(find.text('0,5'), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Закрыть'));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.byTooltip('Рассчитать материал'));
        await tapVisible(tester, find.text('Краска'));
        final can = field('Объём банки');
        await tapVisible(tester, can);
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(can).bottom,
          lessThanOrEqualTo(size.height - keyboard),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('save failure keeps the draft and shows a readable error', (
    tester,
  ) async {
    viewport(tester, const Size(393, 852));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: RoomEditorScreen(
          initial: room(saved: true),
          onSave: (_) async =>
              throw StateError('Помещение изменено на другом устройстве.'),
        ),
      ),
    );
    await tester.tap(find.text('Сохранить помещение'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Помещение изменено'), findsWidgets);
    expect(find.text('Кухня'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(393, 852), const Size(1440, 900)]) {
    testWidgets('room editor and procurement render cleanly at $size', (
      tester,
    ) async {
      viewport(tester, size);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: RoomEditorScreen(
              initial: room(saved: true),
              onSave: (r) async => r,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await screenshot(tester, key, 'editor-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectRoomsProvider('p').overrideWith(
              (_) async => [
                room(saved: true),
                room(saved: true).copyWith(name: 'Гостиная'),
              ],
            ),
            projectDetailProvider('p').overrideWith(
              (_) async => ProjectDetail(
                project: ProjectModel(
                  id: 'p',
                  title: 'Квартира на Садовой',
                  plannedRevenue: 0,
                  startDate: DateTime(2026),
                  status: ProjectStatus.active,
                  createdAt: DateTime(2026),
                ),
                transactions: const [],
              ),
            ),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: const ProjectRoomsScreen(projectId: 'p'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('18 м²'), findsNothing);
      await tester.tap(find.text('Ведомость'));
      await tester.pumpAndSettle();
      expect(find.text('К закупке'), findsOneWidget);
      await screenshot(tester, key, 'summary-${size.width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }
}
