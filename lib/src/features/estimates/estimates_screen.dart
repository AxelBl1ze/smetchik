import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/ui.dart';

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
    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: null,
              actions: [
                IconButton(
                  tooltip: 'Новая смета',
                  onPressed: () => context.push('/estimate/new'),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(estimatesProvider),
        child: ResponsiveListView(
          maxWidth: 900,
          children: [
            ScreenTitle(
              title: 'Сметы',
              subtitle: 'Черновики, отправленные и работы в процессе',
              icon: Icons.receipt_long_outlined,
              actions: isDesktop
                  ? [
                      SizedBox(
                        width: 190,
                        child: FilledButton.icon(
                          onPressed: () => context.push('/estimate/new'),
                          icon: const Icon(Icons.add),
                          label: const Text('Новая смета'),
                        ),
                      ),
                    ]
                  : const [],
            ),
            const SizedBox(height: 14),
            _EstimatesSearchField(onChanged: _setQuery),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', 'Все'),
                  _filterChip(EstimateStatus.draft, 'Черновики'),
                  _filterChip(EstimateStatus.sent, 'Отправлены'),
                  _filterChip(EstimateStatus.accepted, 'Приняты'),
                  _filterChip(EstimateStatus.inProgress, 'В работе'),
                  _filterChip(EstimateStatus.completed, 'Завершены'),
                  _filterChip(EstimateStatus.declined, 'Отклонены'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            estimates.when(
              data: (items) {
                final filtered = items.where((estimate) {
                  final matchesStatus =
                      _status == 'all' ||
                      EstimateStatus.normalize(estimate.status) == _status;
                  final haystack =
                      '${estimate.objectTitle} ${estimate.client?.name ?? ''}'
                          .toLowerCase();
                  return matchesStatus && haystack.contains(_query);
                }).toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.file_copy_outlined,
                    title: 'Сметы не найдены',
                    body: 'Создайте новую смету или измените фильтр.',
                    action: FilledButton.icon(
                      onPressed: () => context.push('/estimate/new'),
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
    );
  }

  Widget _filterChip(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: _status == value,
        label: Text(label),
        onSelected: (_) => setState(() => _status = value),
      ),
    );
  }

  void _setQuery(String value) {
    setState(() => _query = value.trim().toLowerCase());
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
