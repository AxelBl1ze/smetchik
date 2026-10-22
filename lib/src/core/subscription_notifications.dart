import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';

class SubscriptionNotifications {
  static final instance = SubscriptionNotifications();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void> _pending = Future.value();
  static const _id = 7301;
  VoidCallback? _onOpen;
  String? _activeUserId;
  String? _launchUserId;

  Future<void> sync(ProfileModel? profile, VoidCallback onOpen) {
    _onOpen = onOpen;
    _pending = _pending.then((_) => _sync(profile)).catchError((Object error) {
      debugPrint('Не удалось обновить уведомление о подписке: $error');
    });
    return _pending;
  }

  Future<void> _sync(ProfileModel? profile) async {
    _activeUserId = profile?.id;
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    if (!_ready) {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(
            'ic_subscription_notification',
          ),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (response.payload == _activeUserId) _onOpen?.call();
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _launchUserId = launch?.notificationResponse?.payload;
      }
      _ready = true;
    }
    if (_launchUserId != null && _launchUserId == profile?.id) {
      _launchUserId = null;
      _onOpen?.call();
    }
    final prefs = await SharedPreferences.getInstance();
    final date = profile?.subscriptionRenewsAt;
    final key = profile?.hasActivePro == true && date != null
        ? '${profile!.id}:${profile.subscriptionPlan}:${date.toUtc().toIso8601String()}'
        : null;
    if (prefs.getString('subscription.scheduled') == key && key != null) return;
    await _plugin.cancel(id: _id);
    await prefs.remove('subscription.scheduled');
    if (key == null) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await ios?.requestPermissions(alert: true, badge: false, sound: true);
    await _plugin.zonedSchedule(
      id: _id,
      title:
          'Подписка «${SubscriptionPlan.label(profile!.subscriptionPlan)}» закончилась',
      body:
          'Доступен Базовый тариф. Продлите подписку в Сметчике, чтобы вернуть все возможности.',
      scheduledDate: tz.TZDateTime.from(date!, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'subscription',
          'Подписка',
          channelDescription: 'Окончание срока подписки',
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: profile.id,
    );
    await prefs.setString('subscription.scheduled', key);
  }
}
