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
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final estimates = ref.watch(estimatesProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 760;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(profileProvider);
            ref.invalidate(estimatesProvider);
            ref.invalidate(clientsProvider);
            ref.invalidate(catalogDataProvider);
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
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: isDesktop ? 220 : double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push('/estimate/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('Новая смета'),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _QuickActions(isDesktop: isDesktop),
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
                    return EmptyState(
                      icon: Icons.assignment_turned_in_outlined,
                      title: 'Нет работ в процессе',
                      body:
                          'Когда клиент примет смету, откройте её и нажмите «Начать работу».',
                      action: FilledButton.icon(
                        onPressed: () => context.push('/estimate/new'),
                        icon: const Icon(Icons.add),
                        label: const Text('Создать смету'),
                      ),
                    );
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
        Container(
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
            backgroundImage: imageUrl == null ? null : NetworkImage(imageUrl!),
            child: imageUrl == null
                ? Text(
                    initials,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  )
                : null,
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

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(
        icon: Icons.construction_outlined,
        title: 'Прайс-лист',
        onTap: () => context.go('/catalog'),
      ),
      _QuickAction(
        icon: Icons.person_add_alt_1,
        title: 'Добавить клиента',
        onTap: () => context.push('/clients/new'),
      ),
      _QuickAction(
        icon: Icons.receipt_long_outlined,
        title: 'Все сметы',
        onTap: () => context.go('/estimates'),
      ),
      _QuickAction(
        icon: Icons.contact_phone_outlined,
        title: 'Клиенты',
        onTap: () => context.go('/clients'),
      ),
    ];

    if (isDesktop) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final action in actions)
            SizedBox(width: 270, height: 68, child: action),
        ],
      );
    }

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.25,
      physics: const NeverScrollableScrollPhysics(),
      children: actions,
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.orangeDark, size: 19),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
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
