import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smetchik/src/core/app_theme.dart';
import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/data/repository.dart';
import 'package:smetchik/src/data/offline_sync_service.dart';
import 'package:smetchik/src/features/estimates/estimate_form_screen.dart';
import 'package:smetchik/src/features/catalog/catalog_screen.dart';
import 'package:smetchik/src/features/support/support_screen.dart';
import 'package:smetchik/src/shared/form_sheet.dart';
import 'package:smetchik/src/shared/keyboard_form_sheet.dart';
import 'package:smetchik/src/shared/ui.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('ru_RU'));
  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
  }

  Future<void> focusWithKeyboard(
    WidgetTester tester,
    Finder field,
    double height,
  ) async {
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    tester.view.viewInsets = FakeViewPadding(bottom: height);
    await tester.pumpAndSettle();
    final bounds = tester.getRect(field);
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(
      bounds.bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - height),
    );
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  }

  for (final item in [
    (const Size(393, 852), 350.0),
    (const Size(320, 568), 310.0),
    (const Size(844, 390), 210.0),
  ]) {
    testWidgets(
      'keeps a late form field visible at ${item.$1} with a keyboard',
      (tester) async {
        viewport(tester, item.$1);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => KeyboardFormSheet(
                      header: const Text('Редактирование информации'),
                      child: Column(
                        children: [
                          for (var i = 0; i < 6; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextField(
                                decoration: InputDecoration(
                                  labelText: 'Поле $i',
                                ),
                              ),
                            ),
                          TextField(
                            key: const Key('last-field'),
                            controller: controller,
                            decoration: const InputDecoration(
                              labelText: 'Комментарий',
                            ),
                          ),
                        ],
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
        final field = find.byKey(const Key('last-field'));
        await focusWithKeyboard(tester, field, item.$2);
        await tester.enterText(field, 'Текст остаётся виден');
        expect(controller.text, 'Текст остаётся виден');
        expect(tester.testTextInput.isVisible, isTrue);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await focusWithKeyboard(tester, field, item.$2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'a resized web viewport reveals the field without scrolling the page behind the modal',
    (tester) async {
      viewport(tester, const Size(393, 852));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ResponsiveListView(
              children: [
                const SizedBox(height: 300),
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showFormSheet(
                      context: context,
                      title: 'Данные клиента',
                      fields: [
                        for (var i = 0; i < 8; i++)
                          TextField(
                            key: Key('field-$i'),
                            decoration: InputDecoration(labelText: 'Данные $i'),
                          ),
                      ],
                    ),
                    child: const Text('Открыть форму'),
                  ),
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Открыть форму'));
      final page = tester.state<ScrollableState>(find.byType(Scrollable).first);
      final offset = page.position.pixels;
      await tester.tap(find.text('Открыть форму'));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('field-7'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(393, 500);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(field).dy, lessThan(500));
      expect(page.position.pixels, offset);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog search in an estimate fits even in landscape with no results',
    (tester) async {
      viewport(tester, const Size(844, 390));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith((_) async => null),
            clientsProvider.overrideWith((_) async => <ClientModel>[]),
            estimatesProvider.overrideWith((_) async => <EstimateModel>[]),
            catalogItemsProvider.overrideWith(
              (_) async => const [
                CatalogItemModel(
                  id: 'work',
                  category: 'Монтаж',
                  title: 'Монтаж двери',
                  unit: 'шт',
                  unitPrice: 100,
                  isCustom: true,
                ),
              ],
            ),
            offlineSyncProvider.overrideWith(
              (_) => OfflineSyncController(
                repository: _UnusedRepository(),
                onSynced: () {},
              ),
            ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const EstimateFormScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Добавить работу'));
      await tester.tap(find.text('Добавить работу'));
      await tester.pumpAndSettle();
      final search = find.widgetWithText(TextField, 'Поиск по работам');
      await focusWithKeyboard(tester, search, 210);
      await tester.enterText(search, 'Несуществующая работа');
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(search).dy, lessThanOrEqualTo(180));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('support subject and message remain visible with the keyboard', (
    tester,
  ) async {
    viewport(tester, const Size(393, 852));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supportTicketsProvider.overrideWith(
            (_) async => <SupportTicketModel>[],
          ),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const SupportScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новое обращение'));
    await tester.pumpAndSettle();
    await focusWithKeyboard(
      tester,
      find.widgetWithText(TextField, 'Опишите вопрос'),
      350,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Опишите вопрос'),
      'Нужна помощь',
    );
    expect(find.text('Нужна помощь'), findsOneWidget);
  });

  testWidgets('catalog category and service editors fit above the keyboard', (
    tester,
  ) async {
    viewport(tester, const Size(393, 852));
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const CatalogScreen())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogDataProvider.overrideWith(
            (_) async => const CatalogData(items: [], categories: ['Монтаж']),
          ),
        ],
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Добавить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новый раздел'));
    await tester.pumpAndSettle();
    await focusWithKeyboard(
      tester,
      find.widgetWithText(TextField, 'Название раздела'),
      350,
    );
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Закрыть').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Добавить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая услуга'));
    await tester.pumpAndSettle();
    await focusWithKeyboard(
      tester,
      find.widgetWithText(TextField, 'Цена'),
      350,
    );
  });
}

class _UnusedRepository implements SmetchikRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected server call');
}
