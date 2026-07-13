import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../projects/projects_workspace.dart';
import '../../shared/ui.dart';

enum _EstimateWorkspace { estimates, projects }

class EstimatesScreen extends ConsumerStatefulWidget {
  const EstimatesScreen({super.key});

  @override
  ConsumerState<EstimatesScreen> createState() => _EstimatesScreenState();
}

class _EstimatesScreenState extends ConsumerState<EstimatesScreen> {
  String _query = '';
  String _status = 'all';

  @override
  Widget build(BuildContext context) {
    final estimates = ref.watch(estimatesProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;
    final workspace =
        GoRouterState.of(context).uri.queryParameters['tab'] == 'projects'
        ? _EstimateWorkspace.projects
        : _EstimateWorkspace.estimates;
    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: null,
              actions: [
                IconButton(
                  tooltip: workspace == _EstimateWorkspace.estimates
                      ? 'Новая смета'
                      : 'Новый объект',
                  onPressed: () => context.push(
                    workspace == _EstimateWorkspace.estimates
                        ? '/estimate/new'
                        : '/projects/new',
                  ),
                  icon: Icon(
                    workspace == _EstimateWorkspace.estimates
                        ? Icons.add_circle_outline
                        : Icons.domain_add_outlined,
                  ),
                ),
              ],
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: _WorkspaceSwitcher(
              selected: workspace,
              onSelected: (value) => context.go(
                value == _EstimateWorkspace.projects
                    ? '/estimates?tab=projects'
                    : '/estimates',
              ),
            ),
          ),
          Expanded(
            child: workspace == _EstimateWorkspace.projects
                ? ProjectsWorkspace(isDesktop: isDesktop)
                : RefreshIndicator(
                    onRefresh: () async => ref.invalidate(estimatesProvider),
                    child: ResponsiveListView(
                      maxWidth: 900,
                      children: [
                        ScreenTitle(
                          title: 'Сметы',
                          subtitle:
                              'Черновики, отправленные и работы в процессе',
                          icon: Icons.receipt_long_outlined,
                          actions: isDesktop
                              ? [
                                  SizedBox(
                                    width: 190,
                                    child: FilledButton.icon(
                                      onPressed: () =>
                                          context.push('/estimate/new'),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Новая смета'),
                                    ),
                                  ),
                                ]
                              : const [],
                        ),
                        const SizedBox(height: 14),
                        _EstimateFilters(
                          status: _status,
                          onQueryChanged: _setQuery,
                          onStatusChanged: (value) =>
                              setState(() => _status = value),
                        ),
                        const SizedBox(height: 12),
                        estimates.when(
                          data: (items) {
                            final filtered = items.where((estimate) {
                              final matchesStatus =
                                  _status == 'all' ||
                                  EstimateStatus.normalize(estimate.status) ==
                                      _status;
                              final haystack =
                                  '${estimate.objectTitle} ${estimate.client?.name ?? ''}'
                                      .toLowerCase();
                              return matchesStatus && haystack.contains(_query);
                            }).toList();
                            if (filtered.isEmpty) {
                              return EmptyState(
                                icon: Icons.file_copy_outlined,
                                title: 'Сметы не найдены',
                                body:
                                    'Создайте новую смету или измените фильтр.',
                                action: FilledButton.icon(
                                  onPressed: () =>
                                      context.push('/estimate/new'),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Новая смета'),
                                ),
                              );
                            }
                            return Column(
                              children: [
                                for (final estimate in filtered) ...[
                                  _EstimateListCard(estimate: estimate),
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
                  ),
          ),
        ],
      ),
    );
  }

  void _setQuery(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }
}

class _WorkspaceSwitcher extends StatelessWidget {
  const _WorkspaceSwitcher({required this.selected, required this.onSelected});

  final _EstimateWorkspace selected;
  final ValueChanged<_EstimateWorkspace> onSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 410),
        child: Container(
          height: 56,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _WorkspaceSwitchOption(
                selected: selected == _EstimateWorkspace.estimates,
                icon: Icons.receipt_long_outlined,
                label: 'Сметы',
                onTap: () => onSelected(_EstimateWorkspace.estimates),
              ),
              const SizedBox(width: 4),
              _WorkspaceSwitchOption(
                selected: selected == _EstimateWorkspace.projects,
                icon: Icons.domain_outlined,
                label: 'Объекты',
                onTap: () => onSelected(_EstimateWorkspace.projects),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSwitchOption extends StatelessWidget {
  const _WorkspaceSwitchOption({
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
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected ? AppColors.graphite : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? AppColors.orange : AppColors.textSecondary,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
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

class _EstimateFilters extends StatelessWidget {
  const _EstimateFilters({
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
      label: 'Все сметы',
      icon: Icons.filter_list_rounded,
      color: AppColors.textSecondary,
      background: AppColors.background,
    ),
    FilterPickerOption(
      value: EstimateStatus.draft,
      label: 'Черновики',
      icon: Icons.edit_outlined,
      color: AppColors.textSecondary,
      background: AppColors.background,
    ),
    FilterPickerOption(
      value: EstimateStatus.sent,
      label: 'Отправлены',
      icon: Icons.send_outlined,
      color: AppColors.info,
      background: AppColors.infoBg,
    ),
    FilterPickerOption(
      value: EstimateStatus.accepted,
      label: 'Приняты',
      icon: Icons.thumb_up_alt_outlined,
      color: AppColors.orangeDark,
      background: AppColors.orangeLight,
    ),
    FilterPickerOption(
      value: EstimateStatus.inProgress,
      label: 'В работе',
      icon: Icons.handyman_outlined,
      color: AppColors.success,
      background: AppColors.successBg,
    ),
    FilterPickerOption(
      value: EstimateStatus.completed,
      label: 'Завершены',
      icon: Icons.done_all_outlined,
      color: AppColors.success,
      background: AppColors.successBg,
    ),
    FilterPickerOption(
      value: EstimateStatus.declined,
      label: 'Отклонены',
      icon: Icons.close_rounded,
      color: AppColors.danger,
      background: AppColors.dangerBg,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final filter = FilterPickerField(
          title: 'Статус сметы',
          options: _options,
          selectedValue: status,
          onChanged: onStatusChanged,
        );
        if (constraints.maxWidth >= 620) {
          return Row(
            children: [
              Expanded(child: _EstimatesSearchField(onChanged: onQueryChanged)),
              const SizedBox(width: 10),
              SizedBox(width: 230, child: filter),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EstimatesSearchField(onChanged: onQueryChanged),
            const SizedBox(height: 10),
            filter,
          ],
        );
      },
    );
  }
}

class _EstimatesSearchField extends StatelessWidget {
  const _EstimatesSearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: const InputDecoration(
        hintText: 'Поиск по объекту или клиенту',
        prefixIcon: Icon(Icons.search),
      ),
      onChanged: onChanged,
    );
  }
}

class _EstimateListCard extends StatelessWidget {
  const _EstimateListCard({required this.estimate});

  final EstimateModel estimate;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      onTap: () => context.push('/estimate/${estimate.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  estimate.objectTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatMoney(estimate.totalAmount),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 15,
                color: AppColors.textHint,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  estimate.client?.name ?? 'Клиент не указан',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                formatDate(estimate.estimateDate),
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              StatusBadge(status: estimate.status),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.push('/estimate/${estimate.id}/edit'),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Править'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
