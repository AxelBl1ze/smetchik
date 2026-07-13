import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';

class ProjectStatusBadge extends StatelessWidget {
  const ProjectStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final data = _projectStatusVisual(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: data.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: data.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 15, color: data.foreground),
          const SizedBox(width: 5),
          Text(
            data.label,
            style: TextStyle(
              color: data.foreground,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class ProjectStatusField extends StatelessWidget {
  const ProjectStatusField({
    super.key,
    required this.status,
    required this.onChanged,
    this.label = 'Статус объекта',
  });

  final String status;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final selected = await showProjectStatusPicker(
          context: context,
          currentStatus: status,
        );
        if (selected != null) onChanged(selected);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.unfold_more_rounded),
        ),
        child: ProjectStatusBadge(status: status),
      ),
    );
  }
}

class ProjectStatusSelectorButton extends StatelessWidget {
  const ProjectStatusSelectorButton({
    super.key,
    required this.status,
    required this.onChanged,
    this.enabled = true,
  });

  final String status;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: !enabled
          ? null
          : () async {
              final selected = await showProjectStatusPicker(
                context: context,
                currentStatus: status,
              );
              if (selected != null) onChanged(selected);
            },
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProjectStatusBadge(status: status),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down,
              color: enabled ? AppColors.textSecondary : AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> showProjectStatusPicker({
  required BuildContext context,
  required String currentStatus,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _ProjectStatusPickerSheet(currentStatus: currentStatus),
  );
}

class _ProjectStatusPickerSheet extends StatelessWidget {
  const _ProjectStatusPickerSheet({required this.currentStatus});

  final String currentStatus;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Статус объекта',
                        style: TextStyle(
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
                const SizedBox(height: 6),
                for (final status in ProjectStatus.values) ...[
                  _ProjectStatusOption(
                    status: status,
                    selected:
                        ProjectStatus.normalize(status) ==
                        ProjectStatus.normalize(currentStatus),
                    onTap: () => Navigator.of(context).pop(status),
                  ),
                  if (status != ProjectStatus.values.last)
                    const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectStatusOption extends StatelessWidget {
  const _ProjectStatusOption({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final String status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = _projectStatusVisual(status);
    return Material(
      color: selected ? data.background : AppColors.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: data.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(data.icon, color: data.foreground),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: data.foreground)
              else
                const Icon(Icons.chevron_right, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

_ProjectStatusVisual _projectStatusVisual(String status) {
  return switch (ProjectStatus.normalize(status)) {
    ProjectStatus.active => const _ProjectStatusVisual(
      label: 'Строится',
      icon: Icons.construction_outlined,
      foreground: AppColors.orangeDark,
      background: AppColors.orangeLight,
      border: AppColors.orangeLight,
    ),
    ProjectStatus.completed => const _ProjectStatusVisual(
      label: 'Завершён',
      icon: Icons.task_alt_outlined,
      foreground: AppColors.info,
      background: AppColors.infoBg,
      border: AppColors.infoBg,
    ),
    ProjectStatus.sold => const _ProjectStatusVisual(
      label: 'Продан',
      icon: Icons.sell_outlined,
      foreground: AppColors.success,
      background: AppColors.successBg,
      border: AppColors.successBg,
    ),
    _ => const _ProjectStatusVisual(
      label: 'Планируется',
      icon: Icons.event_note_outlined,
      foreground: AppColors.textSecondary,
      background: AppColors.background,
      border: AppColors.border,
    ),
  };
}

class _ProjectStatusVisual {
  const _ProjectStatusVisual({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;
  final Color border;
}
