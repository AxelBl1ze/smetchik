import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smetchik/src/core/app_theme.dart';
import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/data/repository.dart';
import 'package:smetchik/src/features/projects/project_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('ru_RU');
  });

  final detail = ProjectDetail(
    project: ProjectModel(
      id: 'project-1',
      title: 'Дом на Садовой',
      objectAddress: 'Оренбург, улица Садовая, 12',
      customerName: 'Алексей',
      plannedRevenue: 2400000,
      startDate: DateTime(2026, 7, 1),
      status: ProjectStatus.active,
      createdAt: DateTime(2026, 7, 1),
      incomeAmount: 400000,
      expenseAmount: 125000,
    ),
    transactions: const [],
  );

  testWidgets('shows project detail on an iPhone-sized viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    final semantics = tester.ensureSemantics();
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(
            (_) async => const ProfileModel(
              id: 'master-1',
              fullName: 'Илья',
              currency: 'RUB',
              subscriptionPlan: SubscriptionPlan.pro,
            ),
          ),
          projectDetailProvider('project-1').overrideWith((_) async => detail),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const ProjectDetailScreen(projectId: 'project-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Дом на Садовой'), findsWidgets);
    expect(find.text('Деньги по объекту'), findsOneWidget);
    expect(find.byTooltip('Экспортировать'), findsOneWidget);

    await tester.tap(find.byTooltip('Экспортировать'));
    await tester.pumpAndSettle();
    expect(find.text('Экспорт отчёта'), findsOneWidget);
    expect(find.text('Excel-таблица'), findsOneWidget);
    expect(find.text('PDF-отчёт'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть').first);
    await tester.pumpAndSettle();

    final addOperation = find.text('Операцию');
    await tester.ensureVisible(addOperation);
    await tester.tap(addOperation);
    await tester.pumpAndSettle();
    expect(find.text('Новая операция'), findsOneWidget);
    expect(find.text(ProjectTransactionCategory.materials), findsWidgets);

    await tester.tap(find.text(ProjectTransactionCategory.materials).last);
    await tester.pumpAndSettle();
    expect(find.text('Категория расхода'), findsOneWidget);
    expect(
      find.text(ProjectTransactionCategory.sitePreparation),
      findsOneWidget,
    );
    await tester.tap(find.text(ProjectTransactionCategory.sitePreparation));
    await tester.pumpAndSettle();
    expect(
      find.text(ProjectTransactionCategory.sitePreparation),
      findsOneWidget,
    );

    await tester.tap(find.text('Поступление'));
    await tester.pumpAndSettle();
    expect(find.text(ProjectTransactionCategory.advance), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
