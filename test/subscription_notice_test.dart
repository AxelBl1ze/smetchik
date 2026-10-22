import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/data/repository.dart';
import 'package:smetchik/src/shared/subscription_notice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => call.method == 'initialize' ? true : null,
        );
  });

  testWidgets(
    'shows expiry once per account and term without hiding saved work',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      Future<void> mount(String id, DateTime until) async {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              profileProvider.overrideWith(
                (_) async => ProfileModel(
                  id: id,
                  fullName: 'Мастер',
                  currency: 'RUB',
                  subscriptionPlan: SubscriptionPlan.team,
                  subscriptionTeamManaged: true,
                  subscriptionRenewsAt: until,
                ),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    SubscriptionNotice(),
                    Expanded(child: Text('Мои сметы')),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount('member-1', DateTime(2020));
      expect(find.text('Бригада неактивна'), findsOneWidget);
      expect(find.text('Мои сметы'), findsOneWidget);
      await tester.tap(find.byTooltip('Скрыть уведомление'));
      await tester.pumpAndSettle();
      expect(find.text('Бригада неактивна'), findsNothing);
      await mount('member-1', DateTime(2020));
      expect(find.text('Бригада неактивна'), findsNothing);
      await mount('member-2', DateTime(2020));
      expect(find.text('Бригада неактивна'), findsOneWidget);
      await mount('member-1', DateTime(2099));
      expect(find.text('Бригада неактивна'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
