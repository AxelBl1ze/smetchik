import 'package:flutter/material.dart';

import '../core/app_theme.dart';

Future<void> showUpgradeSheet({
  required BuildContext context,
  required String message,
  required VoidCallback onOpenPlans,
  String title = 'Нужен Профи',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _UpgradeSheet(
      title: title,
      message: message,
      onOpenPlans: () {
        Navigator.of(sheetContext).pop();
        onOpenPlans();
      },
    ),
  );
}

class _UpgradeSheet extends StatelessWidget {
  const _UpgradeSheet({
    required this.title,
    required this.message,
    required this.onOpenPlans,
  });

  final String title;
  final String message;
  final VoidCallback onOpenPlans;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.graphite,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.workspace_premium,
                        color: AppColors.orange,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            message,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.orangeLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _UpgradeBenefit(text: 'Безлимитные сметы и клиенты'),
                      SizedBox(height: 7),
                      _UpgradeBenefit(text: 'Дублирование смет'),
                      SizedBox(height: 7),
                      _UpgradeBenefit(text: 'Настройки PDF'),
                      SizedBox(height: 7),
                      _UpgradeBenefit(text: 'Расширенная статистика'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onOpenPlans,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Оформить Профи'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Позже'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpgradeBenefit extends StatelessWidget {
  const _UpgradeBenefit({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: AppColors.orangeDark, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.graphite,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}
