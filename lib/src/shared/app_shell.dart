import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/app_theme.dart';
import 'feature_tour_overlay.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.selectedIndex, required this.child});

  final int selectedIndex;
  final Widget child;

  static const _mobilePaths = [
    '/home',
    '/estimates',
    '/catalog',
    '/clients',
    '/settings',
  ];
  static const _desktopPaths = [
    '/home',
    '/estimates',
    '/catalog',
    '/clients',
    '/settings',
  ];
  static const _desktopLabels = [
    'Главная',
    'Сметы',
    'Прайс-лист',
    'Клиенты',
    'Настройки',
  ];
  static const _desktopIcons = [
    Icons.space_dashboard_outlined,
    Icons.receipt_long_outlined,
    Icons.construction_outlined,
    Icons.contact_phone_outlined,
    Icons.tune_outlined,
  ];
  static const _mobileLabels = [
    'Главная',
    'Сметы',
    'Прайс',
    'Клиенты',
    'Настройки',
  ];
  static const _mobileIcons = [
    Icons.space_dashboard_outlined,
    Icons.receipt_long_outlined,
    Icons.construction_outlined,
    Icons.contact_phone_outlined,
    Icons.tune_outlined,
  ];
  static const _mobileSelectedIcons = [
    Icons.space_dashboard,
    Icons.receipt_long,
    Icons.construction,
    Icons.contact_phone,
    Icons.tune,
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;
    final shell = isDesktop ? _desktopShell(context) : _mobileShell(context);
    return FeatureTourOverlay(selectedIndex: selectedIndex, child: shell);
  }

  Widget _mobileShell(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: _FloatingCapsuleNavBar(
        selectedIndex: selectedIndex,
        labels: _mobileLabels,
        icons: _mobileIcons,
        selectedIcons: _mobileSelectedIcons,
        onTap: (index) => context.go(_mobilePaths[index]),
      ),
    );
  }

  Widget _desktopShell(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 66,
              decoration: const BoxDecoration(
                color: AppColors.card,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.orangeLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.receipt_long,
                            color: AppColors.orange,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Сметчик',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const Spacer(),
                        for (
                          var index = 0;
                          index < _desktopLabels.length;
                          index++
                        ) ...[
                          _DesktopTab(
                            selected: selectedIndex == index,
                            icon: _desktopIcons[index],
                            label: _desktopLabels[index],
                            onTap: () => context.go(_desktopPaths[index]),
                          ),
                          if (index != _desktopLabels.length - 1)
                            const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingCapsuleNavBar extends StatelessWidget {
  const _FloatingCapsuleNavBar({
    required this.selectedIndex,
    required this.labels,
    required this.icons,
    required this.selectedIcons,
    required this.onTap,
  });

  final int selectedIndex;
  final List<String> labels;
  final List<IconData> icons;
  final List<IconData> selectedIcons;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      color: AppColors.background,
      padding: EdgeInsets.fromLTRB(10, 14, 10, bottom > 0 ? bottom + 6 : 10),
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF7EF),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth / labels.length;
            final capsuleWidth = (itemWidth - 4).clamp(58.0, 82.0).toDouble();
            final capsuleLeft =
                itemWidth * selectedIndex + (itemWidth - capsuleWidth) / 2;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: capsuleLeft,
                  top: -12,
                  width: capsuleWidth,
                  height: 52,
                  child: DecoratedBox(
                    key: const Key('floating-nav-capsule'),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF0A25E), AppColors.orange],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.orange.withValues(alpha: 0.34),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var index = 0; index < labels.length; index++)
                      Expanded(
                        child: _FloatingCapsuleNavItem(
                          selected: selectedIndex == index,
                          icon: icons[index],
                          selectedIcon: selectedIcons[index],
                          label: labels[index],
                          onTap: () {
                            if (selectedIndex == index) return;
                            HapticFeedback.selectionClick();
                            onTap(index);
                          },
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FloatingCapsuleNavItem extends StatelessWidget {
  const _FloatingCapsuleNavItem({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: AnimatedSlide(
          offset: selected ? const Offset(0, -0.28) : Offset.zero,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(maxWidth: 82),
            padding: selected
                ? const EdgeInsets.symmetric(horizontal: 9, vertical: 7)
                : const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: selected ? 1.05 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    selected ? selectedIcon : icon,
                    size: selected ? 20 : 21,
                    color: selected ? Colors.white : AppColors.textHint,
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: selected ? 58 : 62,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: selected ? Colors.white : AppColors.textHint,
                        fontSize: selected ? 10.5 : 10,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopTab extends StatelessWidget {
  const _DesktopTab({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.orangeLight : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: selected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.orange : AppColors.textSecondary,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.orange : AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
