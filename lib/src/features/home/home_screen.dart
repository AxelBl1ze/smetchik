import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/ui.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isDesktop = MediaQuery.sizeOf(context).width >= 840;
      Future<void>.delayed(Duration(milliseconds: isDesktop ? 250 : 1800), () {
        if (!mounted) return;
        ref
            .read(catalogDataProvider.future)
            .catchError((_) => CatalogData.empty);
      });
      ref.read(clientsProvider.future).catchError((_) => <ClientModel>[]);
      ref.read(projectsProvider.future).catchError((_) => <ProjectModel>[]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final estimates = ref.watch(estimatesProvider);
    final projects = ref.watch(projectsProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 760;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(profileProvider);
            ref.invalidate(estimatesProvider);
            ref.invalidate(clientsProvider);
            ref.invalidate(catalogDataProvider);
            ref.invalidate(projectsProvider);
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 20 : 16,
              isDesktop ? 20 : 12,
              isDesktop ? 20 : 16,
              20,
            ),
            children: [
              profile.when(
                data: (value) => _Header(
                  name: value?.fullName.trim().isNotEmpty == true
                      ? value!.fullName
                      : 'мастер',
                  initials: value?.initials ?? 'СМ',
                  imageUrl: ref
                      .read(repositoryProvider)
                      .logoPublicUrl(value?.logoPath),
                ),
                loading: () => const _Header(name: 'мастер', initials: 'СМ'),
                error: (_, _) => const _Header(name: 'мастер', initials: 'СМ'),
              ),
              const SizedBox(height: 14),
              projects.when(
                data: (items) => _ProjectSummaryCard(
                  projects: items,
                  onTap: () => context.go('/estimates?tab=projects'),
                ),
                loading: () => const _ProjectSummaryCard.loading(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              estimates.when(
                data: (items) {
                  final active = items
                      .where(
                        (estimate) =>
                            EstimateStatus.isActiveWork(estimate.status),
                      )
                      .toList();
                  final activeTotal = active.fold<double>(
                    0,
                    (sum, estimate) => sum + estimate.totalAmount,
                  );
                  return Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: 'Смет в работе',
                          value: '${active.length}',
                          sub: 'сейчас выполняются',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatCard(
                          label: 'Денег в работе',
                          value: formatMoney(activeTotal),
                          sub: 'по работам в процессе',
                          accent: true,
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Смет в работе',
                        value: '—',
                        sub: 'сейчас выполняются',
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        label: 'Денег в работе',
                        value: '—',
                        sub: 'по работам',
                      ),
                    ),
                  ],
                ),
                error: (error, _) => ErrorPane(error: error),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, actionConstraints) {
                  final compact = actionConstraints.maxWidth < 520;
                  final newEstimate = FilledButton.icon(
                    onPressed: () => context.push('/estimate/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('Новая смета'),
                  );
                  final newClient = OutlinedButton.icon(
                    onPressed: () => context.push('/clients/new'),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Клиент'),
                  );

                  if (compact) {
                    return Row(
                      children: [
                        Expanded(flex: 3, child: newEstimate),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: newClient),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      SizedBox(width: 220, child: newEstimate),
                      const SizedBox(width: 10),
                      SizedBox(width: 172, child: newClient),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              estimates.when(
                data: (items) {
                  final waiting = items
                      .where(
                        (estimate) =>
                            EstimateStatus.normalize(estimate.status) ==
                            EstimateStatus.sent,
                      )
                      .length;
                  if (waiting == 0) return const SizedBox.shrink();
                  return _AttentionCard(
                    count: waiting,
                    onTap: () => context.go('/estimates'),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 18),
              SectionHeader(
                title: 'Сметы в работе',
                action: TextButton(
                  onPressed: () => context.go('/estimates'),
                  child: const Text('Все'),
                ),
              ),
              const SizedBox(height: 8),
              estimates.when(
                data: (items) {
                  final active = items
                      .where(
                        (estimate) =>
                            EstimateStatus.isActiveWork(estimate.status),
                      )
                      .toList();
                  if (active.isEmpty) {
                    return const _QuietWorkEmptyState();
                  }
                  return Column(
                    children: [
                      for (final estimate in active.take(3)) ...[
                        _EstimateCard(estimate: estimate),
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
      },
    );
  }
}

class _ProjectSummaryCard extends StatelessWidget {
  const _ProjectSummaryCard({required this.projects, required this.onTap})
    : loading = false;

  const _ProjectSummaryCard.loading()
    : projects = const [],
      onTap = null,
      loading = true;

  final List<ProjectModel> projects;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final active = projects
        .where(
          (project) => ProjectStatus.countsTowardsBasicLimit(project.status),
        )
        .toList();
    final expenses = active.fold<double>(
      0,
      (sum, project) => sum + project.expenseAmount,
    );
    if (!loading && active.isEmpty) return const SizedBox.shrink();
    return SmetchikCard(
      onTap: onTap,
      child: loading
          ? const Text(
              'Загружаем объекты...',
              style: TextStyle(color: AppColors.textSecondary),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Активные объекты',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      'Все объекты',
                      style: TextStyle(
                        color: AppColors.orangeDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.orangeDark,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 28,
                  runSpacing: 8,
                  children: [
                    _ProjectMetric(
                      value: '${active.length}',
                      label: 'в работе',
                    ),
                    _ProjectMetric(
                      value: formatMoney(expenses),
                      label: 'потрачено на объекты',
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _ProjectMetric extends StatelessWidget {
  const _ProjectMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
      ),
      Text(
        label,
        style: const TextStyle(color: AppColors.textHint, fontSize: 11),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.initials, this.imageUrl});

  final String name;
  final String initials;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Добрый день,',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              Text(
                name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () => context.go('/settings'),
          borderRadius: BorderRadius.circular(99),
          child: Container(
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.orange, width: 2),
            ),
            child: CircleAvatar(
              backgroundColor: AppColors.orangeLight,
              foregroundColor: AppColors.orangeDark,
              backgroundImage: imageUrl == null
                  ? null
                  : NetworkImage(imageUrl!),
              child: imageUrl == null
                  ? Text(
                      initials,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    this.accent = false,
  });

  final String label;
  final String value;
  final String sub;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: accent ? AppColors.success : AppColors.graphite,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            sub,
            style: const TextStyle(color: AppColors.textHint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.orangeLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.mark_email_unread_outlined,
                color: AppColors.orangeDark,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count ${_estimateWord(count)} жд${count == 1 ? 'ёт' : 'ут'} ответа клиента',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Открыть сметы',
                      style: TextStyle(
                        color: AppColors.orangeDark,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.orangeDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuietWorkEmptyState extends StatelessWidget {
  const _QuietWorkEmptyState();

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.hourglass_empty_rounded,
              color: AppColors.textHint,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Text(
              'Нет работ в процессе. Создайте смету, когда появится новый объект.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

String _estimateWord(int count) {
  final remainder = count % 100;
  if (remainder >= 11 && remainder <= 14) return 'смет';
  return switch (count % 10) {
    1 => 'смета',
    2 || 3 || 4 => 'сметы',
    _ => 'смет',
  };
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({required this.estimate});

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
              Text(
                formatMoney(estimate.totalAmount),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
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
          const SizedBox(height: 8),
          StatusBadge(status: estimate.status),
        ],
      ),
    );
  }
}
