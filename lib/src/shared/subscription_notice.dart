import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_theme.dart';
import '../core/auth_controller.dart';
import '../core/subscription_notifications.dart';
import '../data/models.dart';
import '../data/repository.dart';

class SubscriptionNotice extends ConsumerStatefulWidget {
  const SubscriptionNotice({super.key});
  @override
  ConsumerState<SubscriptionNotice> createState() => _SubscriptionNoticeState();
}

class _SubscriptionNoticeState extends ConsumerState<SubscriptionNotice>
    with WidgetsBindingObserver {
  Timer? _timer;
  String? _event;
  bool _dismissed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(profileProvider, (_, next) {
      next.whenData(_update);
    }, fireImmediately: true);
  }

  void _update(ProfileModel? profile) {
    _timer?.cancel();
    unawaited(SubscriptionNotifications.instance.sync(profile, _openPlans));
    final until = profile?.subscriptionRenewsAt;
    if (until?.isAfter(DateTime.now()) == true &&
        profile?.hasActivePro == true) {
      final delay = until!.difference(DateTime.now());
      _timer = Timer(
        delay > const Duration(days: 1) ? const Duration(days: 1) : delay,
        _refresh,
      );
    }
    final expired =
        profile != null &&
        !profile.hasActivePro &&
        (profile.subscriptionPlan != SubscriptionPlan.basic ||
            profile.subscriptionTeamManaged);
    final event = expired
        ? '${profile.id}:${profile.subscriptionPlan}:${until?.toUtc().toIso8601String() ?? profile.subscriptionStatus}'
        : null;
    _event = event;
    unawaited(_loadDismissed(event));
  }

  Future<void> _loadDismissed(String? event) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _event != event) return;
    setState(
      () => _dismissed =
          event == null || prefs.getString('subscription.dismissed') == event,
    );
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(profileProvider);
    ref.invalidate(teamWorkspaceProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _openPlans() {
    if (mounted && ref.read(authControllerProvider).isLoggedIn) {
      context.go('/settings?plans=1');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || _event == null) return const SizedBox.shrink();
    final profile = ref.watch(profileProvider).asData?.value;
    if (profile == null || profile.hasActivePro) return const SizedBox.shrink();
    return Material(
      color: AppColors.background,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.workspace_premium_outlined,
                  color: AppColors.orangeDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.subscriptionTeamManaged
                          ? 'Бригада неактивна'
                          : 'Срок подписки закончился',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Ваши данные сохранены. Сейчас доступен Базовый тариф.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    TextButton(
                      onPressed: _openPlans,
                      child: const Text('Посмотреть тарифы'),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Скрыть уведомление',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () async {
                  final event = _event;
                  setState(() => _dismissed = true);
                  final prefs = await SharedPreferences.getInstance();
                  if (event != null) {
                    await prefs.setString('subscription.dismissed', event);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
