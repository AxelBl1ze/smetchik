import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smetchik/src/core/app_theme.dart';
import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/data/repository.dart';
import 'package:smetchik/src/features/clients/client_estimates_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('ru_RU');
  });

  testWidgets('shows only estimates for the selected client', (tester) async {
    final createdAt = DateTime(2026, 7, 27);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientsProvider.overrideWith(
            (_) async => [
              ClientModel(
                id: 'client-1',
                name: 'Алексей',
                createdAt: createdAt,
              ),
              ClientModel(
                id: 'client-2',
                name: 'Дмитрий',
                createdAt: createdAt,
              ),
            ],
          ),
          estimatesProvider.overrideWith(
            (_) async => [
              EstimateModel(
                id: 'estimate-1',
                clientId: 'client-1',
                objectTitle: 'Квартира Алексея',
                estimateDate: createdAt,
                status: EstimateStatus.draft,
                totalAmount: 12000,
                createdAt: createdAt,
              ),
              EstimateModel(
                id: 'estimate-2',
                clientId: 'client-2',
                objectTitle: 'Дом Дмитрия',
                estimateDate: createdAt,
                status: EstimateStatus.draft,
                totalAmount: 18000,
                createdAt: createdAt,
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const ClientEstimatesScreen(clientId: 'client-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Квартира Алексея'), findsOneWidget);
    expect(find.text('Дом Дмитрия'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
