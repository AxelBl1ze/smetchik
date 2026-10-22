import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smetchik/src/core/subscription_notifications.dart';
import 'package:smetchik/src/data/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            calls.add(call);
            return switch (call.method) {
              'initialize' || 'requestNotificationsPermission' => true,
              'getNotificationAppLaunchDetails' => {
                'notificationLaunchedApp': false,
              },
              _ => null,
            };
          },
        );
  });

  test(
    'schedules expiry once, replaces it on renewal and cancels on logout',
    () async {
      final service = SubscriptionNotifications();
      final profile = ProfileModel(
        id: 'master',
        fullName: 'Мастер',
        currency: 'RUB',
        subscriptionPlan: SubscriptionPlan.team,
        subscriptionRenewsAt: DateTime(2099),
      );
      await service.sync(profile, () {});
      expect(calls.where((c) => c.method == 'zonedSchedule').length, 1);
      final scheduled =
          calls.firstWhere((c) => c.method == 'zonedSchedule').arguments as Map;
      expect(scheduled['payload'], 'master');
      expect(scheduled['title'], contains('Бригада'));
      await service.sync(profile, () {});
      expect(calls.where((c) => c.method == 'zonedSchedule').length, 1);
      await service.sync(
        profile.copyWith(subscriptionRenewsAt: DateTime(2099, 2)),
        () {},
      );
      expect(calls.where((c) => c.method == 'zonedSchedule').length, 2);
      calls.clear();
      await service.sync(null, () {});
      expect(calls.any((c) => c.method == 'cancel'), isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'subscription.scheduled',
        ),
        isNull,
      );
    },
  );

  test(
    'expired and canceled subscriptions have no future premium access',
    () async {
      final service = SubscriptionNotifications();
      final expired = ProfileModel(
        id: 'member',
        fullName: 'Мастер',
        currency: 'RUB',
        subscriptionPlan: SubscriptionPlan.team,
        subscriptionTeamManaged: true,
        subscriptionRenewsAt: DateTime(2020),
      );
      expect(expired.hasActivePro, isFalse);
      expect(expired.effectiveSubscriptionPlan, SubscriptionPlan.basic);
      await service.sync(expired, () {});
      await service.sync(
        expired.copyWith(
          subscriptionStatus: 'canceled',
          subscriptionRenewsAt: DateTime(2099),
        ),
        () {},
      );
      expect(calls.any((c) => c.method == 'zonedSchedule'), isFalse);
    },
  );
}
