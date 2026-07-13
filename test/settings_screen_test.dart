import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smetchik/src/core/app_config.dart';
import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/data/repository.dart';
import 'package:smetchik/src/features/settings/settings_screen.dart';
import 'package:smetchik/src/shared/app_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  });

  testWidgets('renders settings screen on mobile and desktop', (tester) async {
    for (final size in [
      const Size(320, 720),
      const Size(390, 844),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(
              (_) async => const ProfileModel(
                id: 'user-id',
                fullName: 'Илья Очень Длинное Имя Мастера',
                currency: 'RUB',
                subscriptionPlan: SubscriptionPlan.pro,
                subscriptionStatus: 'past_due',
              ),
            ),
            estimatesProvider.overrideWith(
              (_) async => const <EstimateModel>[],
            ),
          ],
          child: const MaterialApp(
            home: AppShell(selectedIndex: 4, child: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Илья'), findsOneWidget);
      expect(find.text('Тариф Базовый'), findsOneWidget);
      expect(find.text('Профи истёк'), findsOneWidget);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('dismisses the tariff sheet by dragging its fixed header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(
            (_) async => const ProfileModel(
              id: 'user-id',
              fullName: 'Илья',
              currency: 'RUB',
            ),
          ),
          estimatesProvider.overrideWith((_) async => const <EstimateModel>[]),
        ],
        child: const MaterialApp(
          home: AppShell(selectedIndex: 4, child: SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Базовый').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tariff-sheet-drag-handle')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('tariff-sheet-drag-handle')),
      const Offset(0, 360),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tariff-sheet-drag-handle')), findsNothing);
  });
}
