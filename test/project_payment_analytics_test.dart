import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smetchik/src/core/app_theme.dart';
import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/features/projects/project_payer_field.dart';
import 'package:smetchik/src/features/projects/project_payment_analytics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('ru_RU');
    final fonts = FontLoader('Inter');
    for (final weight in ['Regular', 'Bold', 'ExtraBold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('payer chart and payment details fit phone and desktop widths', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final transactions = [
      for (var i = 0; i < 7; i++)
        ProjectTransactionModel(
          id: '$i',
          projectId: 'house-1',
          type: ProjectTransactionType.expense,
          category: 'Материалы',
          title: 'Кирпич, поставка $i',
          amount: (7 - i) * 15000,
          payerName: i == 0 ? 'Джамал' : 'Александр Константинович Иванов $i',
          counterparty: 'Строймаркет',
          transactionDate: DateTime(2026, 10, 22),
        ),
    ];

    for (final width in [320.0, 393.0, 1000.0]) {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: RepaintBoundary(
              key: const Key('payment-chart-capture'),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ProjectPaymentAnalytics(
                  key: ValueKey(width),
                  transactions: transactions,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Кто оплатил'));
      await tester.pumpAndSettle();
      expect(find.text('Джамал'), findsOneWidget);
      expect(find.text('1 оп. · 25%'), findsOneWidget);
      expect(tester.takeException(), isNull);

      if (const bool.fromEnvironment('CAPTURE_PROJECT_PAYMENTS')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('payment-chart-capture')),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/test_artifacts')
            ..createSync(recursive: true);
          await File(
            '${directory.path}/payment-chart-${width.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.tap(find.text('Джамал'));
      await tester.pumpAndSettle();
      expect(find.text('Кирпич, поставка 0'), findsOneWidget);
      expect(find.text('22.10.2026'), findsOneWidget);
      expect(find.text('Получатель: Строймаркет'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();
      final showAll = find.text('Показать все (7)');
      await tester.ensureVisible(showAll);
      await tester.tap(showAll);
      await tester.pumpAndSettle();
      expect(find.text('Александр Константинович Иванов 6'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'selects a saved payer and allows a new name with keyboard open',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ProjectPayerField(
                controller: controller,
                names: const ['Джамал', 'Илья'],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Выбрать плательщика'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Джамал'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Джамал');
      await tester.tap(find.byTooltip('Выбрать плательщика'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Сергей');
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Добавить «Сергей»'));
      await tester.tap(find.text('Добавить «Сергей»'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Сергей');
    },
  );
}
