import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/onboarding_controller.dart';
import '../../shared/ui.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _page = 0;
  int _direction = 1;

  static const _pages = [
    _OnboardingPageData(
      icon: Icons.bolt,
      title: 'Смета за пару минут',
      body:
          'Добавьте клиента, выберите работы из каталога и соберите аккуратную смету прямо на объекте.',
      bullets: ['Клиент', 'Работы', 'Итог'],
    ),
    _OnboardingPageData(
      icon: Icons.playlist_add_check,
      title: 'Работы всегда под рукой',
      body:
          'Используйте готовый каталог или добавляйте свои позиции с ценой, единицей измерения и количеством.',
      bullets: ['Сантехника', 'Электрика', 'Отделка'],
    ),
    _OnboardingPageData(
      icon: Icons.picture_as_pdf,
      title: 'PDF для клиента',
      body:
          'Покажите клиенту понятное коммерческое предложение и отправьте его удобным способом.',
      bullets: ['PDF', 'Поделиться', 'Любое приложение'],
    ),
  ];

  bool get _isLastPage => _page == _pages.length - 1;

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingControllerProvider);
    final current = _pages[_page];
    return Scaffold(
      body: SafeArea(
        child: ScreenPadding(
          maxWidth: 520,
          child: Column(
            children: [
              const SizedBox(height: 28),
              Expanded(
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity < -180) {
                      _nextPage();
                    } else if (velocity > 180) {
                      _previousPage();
                    }
                  },
                  child: _OnboardingCard(
                    data: current,
                    page: _page,
                    direction: _direction,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++) _dot(i == _page),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onboarding.ready ? _primaryAction : null,
                icon: Icon(_isLastPage ? Icons.check : Icons.arrow_forward),
                label: Text(_isLastPage ? 'Начать работу' : 'Далее'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onboarding.ready ? onboarding.markSeen : null,
                child: const Text('Пропустить'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _primaryAction() async {
    final onboarding = ref.read(onboardingControllerProvider);
    if (_isLastPage) {
      await onboarding.markSeen();
      return;
    }

    _nextPage();
  }

  void _nextPage() {
    if (_isLastPage) return;
    setState(() {
      _direction = 1;
      _page += 1;
    });
  }

  void _previousPage() {
    if (_page == 0) return;
    setState(() {
      _direction = -1;
      _page -= 1;
    });
  }

  Widget _dot(bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: active ? 24 : 8,
      height: 8,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: active ? AppColors.orange : AppColors.border,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({
    required this.data,
    required this.page,
    required this.direction,
  });

  final _OnboardingPageData data;
  final int page;
  final int direction;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 360),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: Offset(0.10 * direction, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    final scale = Tween<double>(
                      begin: 0.96,
                      end: 1,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: slide,
                        child: ScaleTransition(scale: scale, child: child),
                      ),
                    );
                  },
                  child: Column(
                    key: ValueKey(page),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TweenAnimationBuilder<double>(
                        key: ValueKey('icon-$page'),
                        tween: Tween(begin: -0.08, end: 0),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutBack,
                        builder: (context, angle, child) {
                          return Transform.rotate(angle: angle, child: child);
                        },
                        child: Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            color: AppColors.orangeLight,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: Icon(
                            data.icon,
                            size: 46,
                            color: AppColors.orangeDark,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        data.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data.body,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in data.bullets) _OnboardingTag(item),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OnboardingTag extends StatelessWidget {
  const _OnboardingTag(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.orangeLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.orangeDark,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.body,
    required this.bullets,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;
}
