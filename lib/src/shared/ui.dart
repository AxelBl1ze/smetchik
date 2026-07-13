import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../data/models.dart';

class ScreenPadding extends StatelessWidget {
  const ScreenPadding({super.key, required this.child, this.maxWidth = 460});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _boundedContentWidth(constraints, maxWidth);
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

double _boundedContentWidth(BoxConstraints constraints, double maxWidth) {
  final viewportWidth = constraints.maxWidth;
  if (!viewportWidth.isFinite) return maxWidth;
  return viewportWidth < maxWidth ? viewportWidth : maxWidth;
}

bool _isNarrow(BoxConstraints constraints, double breakpoint) {
  return !constraints.maxWidth.isFinite || constraints.maxWidth < breakpoint;
}

class ResponsiveListView extends StatelessWidget {
  const ResponsiveListView({
    super.key,
    required this.children,
    this.maxWidth = 760,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 20),
  });

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _boundedContentWidth(constraints, maxWidth);
        final minHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0.0;
        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Center(
            child: SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Padding(
                  padding: padding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        ?action,
      ],
    );
  }
}

class FilterPickerOption {
  const FilterPickerOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final Color background;
}

/// Compact, consistent status filtering for long work lists.
class FilterPickerField extends StatelessWidget {
  const FilterPickerField({
    super.key,
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
  });

  final String title;
  final List<FilterPickerOption> options;
  final String selectedValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere(
      (option) => option.value == selectedValue,
      orElse: () => options.first,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final value = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => _FilterPickerSheet(
              title: title,
              options: options,
              selectedValue: selectedValue,
            ),
          );
          if (value != null) onChanged(value);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected.background,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(selected.icon, color: selected.color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      selected.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPickerSheet extends StatelessWidget {
  const _FilterPickerSheet({
    required this.title,
    required this.options,
    required this.selectedValue,
  });

  final String title;
  final List<FilterPickerOption> options;
  final String selectedValue;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final option in options) ...[
                    _FilterPickerOption(
                      option: option,
                      selected: option.value == selectedValue,
                      onTap: () => Navigator.of(context).pop(option.value),
                    ),
                    if (option != options.last) const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterPickerOption extends StatelessWidget {
  const _FilterPickerOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final FilterPickerOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? option.background : AppColors.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : option.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(option.icon, color: option.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  option.label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: option.color)
              else
                const Icon(Icons.chevron_right, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class ScreenTitle extends StatelessWidget {
  const ScreenTitle({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = _isNarrow(constraints, 640) || actions.isEmpty;
        final heading = Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, color: AppColors.orangeDark, size: 25),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppColors.graphite,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            ...actions.map(
              (action) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: action,
              ),
            ),
          ],
        );
      },
    );
  }
}

class SmetchikCard extends StatelessWidget {
  const SmetchikCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: card,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, color: AppColors.orangeDark, size: 40),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 22), action!],
          ],
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = EstimateStatus.normalize(status);
    final data = switch (normalizedStatus) {
      EstimateStatus.sent => (
        'Отправлена',
        Icons.send,
        AppColors.info,
        AppColors.infoBg,
      ),
      EstimateStatus.accepted => (
        'Принята',
        Icons.thumb_up_alt_outlined,
        AppColors.orangeDark,
        AppColors.orangeLight,
      ),
      EstimateStatus.inProgress => (
        'В работе',
        Icons.handyman_outlined,
        AppColors.success,
        AppColors.successBg,
      ),
      EstimateStatus.completed => (
        'Завершена',
        Icons.done_all,
        AppColors.success,
        AppColors.successBg,
      ),
      EstimateStatus.declined => (
        'Отклонена',
        Icons.close,
        AppColors.danger,
        AppColors.dangerBg,
      ),
      _ => (
        'Черновик',
        Icons.edit,
        AppColors.textSecondary,
        AppColors.background,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: data.$4,
        borderRadius: BorderRadius.circular(999),
        border: normalizedStatus == EstimateStatus.draft
            ? Border.all(color: AppColors.border)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.$2, size: 14, color: data.$3),
          const SizedBox(width: 4),
          Text(
            data.$1,
            style: TextStyle(
              color: data.$3,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class LoadingPane extends StatelessWidget {
  const LoadingPane({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class ErrorPane extends StatelessWidget {
  const ErrorPane({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'Не удалось загрузить данные',
      body: error.toString(),
    );
  }
}
