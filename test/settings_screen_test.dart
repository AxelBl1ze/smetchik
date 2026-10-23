import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smetchik/src/core/app_config.dart';
import 'package:smetchik/src/core/app_theme.dart';
import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/data/pdf_templates.dart';
import 'package:smetchik/src/data/repository.dart';
import 'package:smetchik/src/features/settings/settings_screen.dart';
import 'package:smetchik/src/shared/app_shell.dart';
import 'package:smetchik/src/shared/ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      final font = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'));
      await font.load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => call.method == 'initialize' ? true : null,
        );
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
      expect(find.text('Тариф и бригада'), findsOneWidget);
      expect(find.text('Базовый'), findsWidgets);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
    'settings do not overscroll when they fit and stay scrollable on short screens',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      for (final size in [const Size(1440, 1200), const Size(320, 568)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              profileProvider.overrideWith(
                (_) async => const ProfileModel(
                  id: 'test',
                  fullName: 'Мастер',
                  currency: 'RUB',
                ),
              ),
              estimatesProvider.overrideWith((_) async => <EstimateModel>[]),
            ],
            child: MaterialApp(
              theme: buildAppTheme(),
              home: const AppShell(selectedIndex: 4, child: SettingsScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final list = find.byType(ResponsiveListView);
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        );
        final fits = size.width > 840;
        expect(scroll.position.maxScrollExtent, fits ? 0 : greaterThan(0));
        await tester.drag(list, const Offset(0, 200));
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, 0);
        await tester.drag(list, const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, fits ? 0 : greaterThan(0));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'invitation email and PDF notes stay visible above the keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(
              (_) async => ProfileModel(
                id: 'owner',
                fullName: 'Мастер',
                currency: 'RUB',
                subscriptionPlan: SubscriptionPlan.team,
                subscriptionRenewsAt: DateTime(2099),
              ),
            ),
            estimatesProvider.overrideWith((_) async => <EstimateModel>[]),
            teamWorkspaceProvider.overrideWith(
              (_) async => const TeamWorkspaceModel(
                id: 'team',
                name: 'Бригада',
                ownerUserId: 'owner',
                role: 'owner',
                maxMembers: 6,
                seatsUsed: 1,
                isActive: true,
              ),
            ),
            teamMembersProvider.overrideWith((_) async => <TeamMemberModel>[]),
            teamInvitesProvider.overrideWith((_) async => <TeamInviteModel>[]),
            incomingTeamInvitesProvider.overrideWith(
              (_) async => <IncomingTeamInviteModel>[],
            ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Тариф и бригада'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Пригласить мастера'));
      await tester.tap(find.text('Пригласить мастера'));
      await tester.pumpAndSettle();
      final email = find.widgetWithText(TextField, 'Email мастера');
      await tester.tap(email);
      tester.view.viewInsets = const FakeViewPadding(bottom: 350);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(email).dy, lessThanOrEqualTo(502));
      await tester.enterText(email, 'master@example.com');
      await tester.tap(find.byTooltip('Закрыть').last);
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Оформление PDF'));
      await tester.pumpAndSettle();
      final note = find.widgetWithText(TextField, 'Примечание в PDF');
      await tester.ensureVisible(note);
      await tester.tap(note);
      tester.view.viewInsets = const FakeViewPadding(bottom: 350);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(note).dy, lessThanOrEqualTo(502));
      await tester.enterText(note, 'Смета действует 7 дней');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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

    await tester.tap(find.text('Тариф и бригада'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тарифы'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tariff-sheet-drag-handle')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('tariff-sheet-drag-handle')),
      const Offset(0, 360),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tariff-sheet-drag-handle')), findsNothing);
  });

  testWidgets('opens tariffs from the expiry notice more than once', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/settings?plans=1',
      routes: [
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(
            (_) async => const ProfileModel(
              id: 'test',
              fullName: 'Мастер',
              currency: 'RUB',
            ),
          ),
          estimatesProvider.overrideWith((_) async => <EstimateModel>[]),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tariff-sheet-drag-handle')), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть').last);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.queryParameters['plans'],
      isNull,
    );
    router.go('/settings?plans=1');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tariff-sheet-drag-handle')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'opens a compact theme gallery and renders every preview on phone',
    (tester) async {
      final captureKey = GlobalKey();
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith(
              (_) async => ProfileModel(
                id: 'theme-test',
                fullName: 'Мастер',
                currency: 'RUB',
                subscriptionPlan: SubscriptionPlan.pro,
                subscriptionRenewsAt: DateTime(2099),
              ),
            ),
            estimatesProvider.overrideWith((_) async => <EstimateModel>[]),
          ],
          child: RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              theme: buildAppTheme(),
              home: const SettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Оформление PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Предпросмотр PDF'), findsNothing);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final screenshot = await boundary.toImage(pixelRatio: 2);
          final data = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          Directory('build/test_artifacts').createSync(recursive: true);
          await File(
            'build/test_artifacts/theme-gallery.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          screenshot.dispose();
        });
      }
      for (final preset in SmetaTemplates.premiumValues) {
        await tester.ensureVisible(find.text(preset.shortName).last);
        await tester.tap(find.text(preset.shortName).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.text('Предпросмотр документа'));
      await tester.tap(find.text('Предпросмотр документа'));
      await tester.pumpAndSettle();
      expect(find.text('Предпросмотр PDF'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
