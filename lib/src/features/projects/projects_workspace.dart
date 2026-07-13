import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/ui.dart';
import '../../shared/upgrade_sheet.dart';
import 'project_status_widgets.dart';

class ProjectsWorkspace extends ConsumerStatefulWidget {
  const ProjectsWorkspace({super.key, required this.isDesktop});

  final bool isDesktop;

  @override
  ConsumerState<ProjectsWorkspace> createState() => _ProjectsWorkspaceState();
}

class _ProjectsWorkspaceState extends ConsumerState<ProjectsWorkspace> {
  String _query = '';
  String _status = 'all';

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final projects = ref.watch(projectsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(projectsProvider),
      child: ResponsiveListView(
        maxWidth: 900,
        children: [
          ScreenTitle(
            title: 'Объекты',
            subtitle: 'Доходы, расходы и прибыль по строительству',
            icon: Icons.domain_add_outlined,
            actions: widget.isDesktop
                ? [
                    SizedBox(
                      width: 190,
                      child: FilledButton.icon(
                        onPressed: () => _openProject(profile, projects),
                        icon: const Icon(Icons.add),
                        label: const Text('Новый объект'),
                      ),
                    ),
                  ]
                : const [],
          ),
          const SizedBox(height: 14),
          _ProjectFilters(
            status: _status,
            onQueryChanged: (value) {
              setState(() => _query = value.trim().toLowerCase());
            },
            onStatusChanged: (value) => setState(() => _status = value),
          ),
          const SizedBox(height: 12),
          profile.when(
            data: (value) => projects.when(
              data: (items) => _ProjectLimitBanner(
                profile: value,
                activeProjects: items
                    .where(
                      (item) =>
                          ProjectStatus.countsTowardsBasicLimit(item.status),
                    )
                    .length,
                onUpgrade: () => context.go('/settings'),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          projects.when(
            data: (items) {
              final filtered = items.where((project) {
                final statusMatches =
                    _status == 'all' || project.status == _status;
                final haystack =
                    '${project.title} ${project.objectAddress ?? ''} ${project.customerName ?? ''}'
                        .toLowerCase();
                return statusMatches && haystack.contains(_query);
              }).toList();
              if (filtered.isEmpty) {
                return EmptyState(
                  icon: Icons.domain_add_outlined,
                  title: items.isEmpty
                      ? 'Объектов ещё нет'
                      : 'Объекты не найдены',
                  body: items.isEmpty
                      ? 'Создайте объект, чтобы видеть расходы, поступления и прибыль по стройке.'
                      : 'Измените поиск или фильтр статуса.',
                  action: FilledButton.icon(
                    onPressed: () => _openProject(profile, projects),
                    icon: const Icon(Icons.add),
                    label: const Text('Новый объект'),
                  ),
                );
              }
              return Column(
                children: [
                  for (final project in filtered) ...[
                    _ProjectCard(project: project),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
            loading: () => const LoadingPane(),
            error: (error, _) => ErrorPane(error: error),
          ),
        ],
      ),
    );
  }

  void _openProject(
    AsyncValue<ProfileModel?> profile,
    AsyncValue<List<ProjectModel>> projects,
  ) {
    final current = profile.asData?.value;
    final activeCount = (projects.asData?.value ?? const <ProjectModel>[])
        .where((item) => ProjectStatus.countsTowardsBasicLimit(item.status))
        .length;
    if (current?.hasActivePro != true && activeCount >= 1) {
      showUpgradeSheet(
        context: context,
        message:
            'На Базовом тарифе доступен один активный объект. В Профи можно вести объекты и затраты по ним без ограничений.',
        onOpenPlans: () => context.go('/settings'),
      );
      return;
    }
    context.push('/projects/new');
  }
}

class _ProjectSearchField extends StatelessWidget {
  const _ProjectSearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: const InputDecoration(
        hintText: 'Поиск по объекту, адресу или заказчику',
        prefixIcon: Icon(Icons.search),
      ),
    );
  }
}

class _ProjectFilters extends StatelessWidget {
  const _ProjectFilters({
    required this.status,
    required this.onQueryChanged,
    required this.onStatusChanged,
  });

  final String status;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onStatusChanged;

  static const _options = [
    FilterPickerOption(
      value: 'all',
      label: 'Все объекты',
      icon: Icons.filter_list_rounded,
      color: AppColors.textSecondary,
      background: AppColors.background,
    ),
    FilterPickerOption(
      value: ProjectStatus.planning,
      label: 'Планируются',
      icon: Icons.event_note_outlined,
      color: AppColors.info,
      background: AppColors.infoBg,
    ),
    FilterPickerOption(
      value: ProjectStatus.active,
      label: 'Строятся',
      icon: Icons.construction_outlined,
      color: AppColors.orangeDark,
      background: AppColors.orangeLight,
    ),
    FilterPickerOption(
      value: ProjectStatus.completed,
      label: 'Завершены',
      icon: Icons.task_alt_outlined,
      color: AppColors.success,
      background: AppColors.successBg,
    ),
    FilterPickerOption(
      value: ProjectStatus.sold,
      label: 'Проданы',
      icon: Icons.home_work_outlined,
      color: AppColors.success,
      background: AppColors.successBg,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final filter = FilterPickerField(
          title: 'Статус объекта',
          options: _options,
          selectedValue: status,
          onChanged: onStatusChanged,
        );
        if (constraints.maxWidth >= 620) {
          return Row(
            children: [
              Expanded(child: _ProjectSearchField(onChanged: onQueryChanged)),
              const SizedBox(width: 10),
              SizedBox(width: 230, child: filter),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProjectSearchField(onChanged: onQueryChanged),
            const SizedBox(height: 10),
            filter,
          ],
        );
      },
    );
  }
}

class _ProjectLimitBanner extends StatelessWidget {
  const _ProjectLimitBanner({
    required this.profile,
    required this.activeProjects,
    required this.onUpgrade,
  });

  final ProfileModel? profile;
  final int activeProjects;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    if (profile?.hasActivePro == true) return const SizedBox.shrink();
    final reached = activeProjects >= 1;
    return SmetchikCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: reached ? AppColors.orangeLight : AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              reached ? Icons.lock_outline : Icons.domain_outlined,
              color: AppColors.orangeDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reached
                      ? 'Активный объект уже используется'
                      : 'Базовый: 1 активный объект',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                const Text(
                  'В Профи доступны объекты без лимита и аналитика затрат.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 7),
                TextButton.icon(
                  onPressed: onUpgrade,
                  icon: const Icon(Icons.workspace_premium, size: 16),
                  label: const Text('Открыть Профи'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});

  final ProjectModel project;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      onTap: () => context.push('/projects/${project.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  project.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ProjectStatusBadge(status: project.status),
            ],
          ),
          if (project.objectAddress?.isNotEmpty == true) ...[
            const SizedBox(height: 5),
            Text(
              project.objectAddress!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          if (project.customerName?.isNotEmpty == true) ...[
            const SizedBox(height: 3),
            Text(
              project.customerName!,
              style: const TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ProjectMetric(
                  label: 'Получено',
                  value: formatMoney(project.incomeAmount),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProjectMetric(
                  label: 'Потрачено',
                  value: formatMoney(project.expenseAmount),
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProjectMetric(
                  label: 'Ожидаемо',
                  value: formatMoney(project.expectedProfit),
                  color: project.expectedProfit >= 0
                      ? AppColors.success
                      : AppColors.danger,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectMetric extends StatelessWidget {
  const _ProjectMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
