import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_theme.dart';
import '../core/feature_tour_controller.dart';

class FeatureTourOverlay extends ConsumerWidget {
  const FeatureTourOverlay({
    super.key,
    required this.selectedIndex,
    required this.child,
  });

  final int selectedIndex;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tour = ref.watch(featureTourControllerProvider);
    if (!tour.shouldShow(selectedIndex)) return child;

    final stepIndex = selectedIndex.clamp(0, _tourSteps.length - 1);

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: ModalBarrier(
            dismissible: false,
            color: Colors.black.withValues(alpha: 0.44),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            child: _TourCard(
              key: ValueKey(stepIndex),
              step: _tourSteps[stepIndex],
              stepIndex: stepIndex,
              totalSteps: _tourSteps.length,
              onNext: () => ref
                  .read(featureTourControllerProvider)
                  .completeStep(stepIndex),
              onSkip: () => ref.read(featureTourControllerProvider).skip(),
            ),
          ),
        ),
      ],
    );
  }
}

class _TourStep {
  const _TourStep({
    required this.title,
    required this.body,
    required this.action,
    required this.icon,
  });

  final String title;
  final String body;
  final String action;
  final IconData icon;
}

const _tourSteps = [
  _TourStep(
    title: 'Начните со сметы',
    body:
        'Главная нужна для быстрых действий: новая смета, активные работы и переходы в прайс-лист или клиентов.',
    action: 'Нажмите «Новая смета», когда нужно быстро посчитать объект.',
    icon: Icons.receipt_long_outlined,
  ),
  _TourStep(
    title: 'История смет',
    body:
        'Здесь лежат черновики, отправленные предложения, принятые работы и завершённые объекты.',
    action: 'Откройте смету, чтобы отправить PDF или сменить статус работы.',
    icon: Icons.receipt_long_outlined,
  ),
  _TourStep(
    title: 'Прайс-лист',
    body:
        'Это каталог услуг и цен. Разделы помогают не искать работу вручную на объекте.',
    action: 'Добавляйте свои услуги, меняйте цены и отправляйте прайс клиенту.',
    icon: Icons.construction_outlined,
  ),
  _TourStep(
    title: 'Клиенты',
    body:
        'Контакты, телефоны и адреса объектов сохраняются здесь и подтягиваются в сметы.',
    action: 'Добавьте клиента один раз, дальше он будет доступен при расчёте.',
    icon: Icons.contact_phone_outlined,
  ),
  _TourStep(
    title: 'Профиль мастера',
    body:
        'Имя, телефон, аватар, специализация и валюта используются в приложении и PDF.',
    action: 'Заполните профиль, чтобы смета выглядела как ваш документ.',
    icon: Icons.tune_outlined,
  ),
];

class _TourCard extends StatelessWidget {
  const _TourCard({
    super.key,
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
  });

  final _TourStep step;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;

    return Align(
      alignment: isDesktop ? Alignment.centerRight : Alignment.bottomCenter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(
                isDesktop ? (1 - value) * 28 : 0,
                (1 - value) * 24,
              ),
              child: Transform.scale(scale: 0.96 + value * 0.04, child: child),
            ),
          );
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, isDesktop ? 28 : 16, 18),
            child: Material(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _PulsingIcon(icon: step.icon),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Закрыть',
                          onPressed: onSkip,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      step.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      step.body,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.38,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.orangeLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.touch_app_outlined,
                            color: AppColors.orangeDark,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              step.action,
                              style: const TextStyle(
                                color: AppColors.graphite,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onSkip,
                            child: const Text('Не показывать'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: onNext,
                            child: const Text('Понятно'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon({required this.icon});

  final IconData icon;

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: 0,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = Curves.easeInOut.transform(_controller.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 54 + value * 10,
              height: 54 + value * 10,
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.12 - value * 0.04),
                shape: BoxShape.circle,
              ),
            ),
            child!,
          ],
        );
      },
      child: Container(
        width: 54,
        height: 54,
        decoration: const BoxDecoration(
          color: AppColors.orange,
          shape: BoxShape.circle,
        ),
        child: Icon(widget.icon, color: Colors.white, size: 27),
      ),
    );
  }
}
