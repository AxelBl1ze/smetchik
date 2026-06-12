import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smetchik/src/core/app_config.dart';
import 'package:smetchik/src/app.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  testWidgets('starts with the configured app shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SmetchikApp()));
    await tester.pumpAndSettle();

    expect(find.text('Войти в Сметчик'), findsOneWidget);
  });

  testWidgets('renders the desktop auth layout', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const ProviderScope(child: SmetchikApp()));
    await tester.pumpAndSettle();

    expect(find.text('Смета за пару минут прямо на объекте'), findsOneWidget);
    expect(find.text('Войти в Сметчик'), findsOneWidget);
  });
}
