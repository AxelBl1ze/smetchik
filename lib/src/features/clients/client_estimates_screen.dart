import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/ui.dart';

class ClientEstimatesScreen extends ConsumerWidget {
  const ClientEstimatesScreen({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider);
    final estimates = ref.watch(estimatesProvider);
    final client = clients.asData?.value
        .where((item) => item.id == clientId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(client?.name ?? 'Сметы клиента')),
      body: estimates.when(
        loading: () => const LoadingPane(),
        error: (error, _) => ErrorPane(error: error),
        data: (items) {
          final clientEstimates = items
              .where((estimate) => estimate.clientId == clientId)
              .toList();
          return ResponsiveListView(
            maxWidth: 720,
            children: [
              SectionHeader(
                title: 'Сметы клиента',
                action: Text(
                  '${clientEstimates.length} ${_estimateWord(clientEstimates.length)}',
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (clientEstimates.isEmpty)
                const EmptyState(
                  icon: Icons.file_copy_outlined,
                  title: 'Смет пока нет',
                  body:
                      'Когда вы создадите смету для этого клиента, она появится здесь.',
                )
              else
                for (final estimate in clientEstimates) ...[
                  _ClientEstimateListItem(estimate: estimate),
                  const SizedBox(height: 8),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _ClientEstimateListItem extends StatelessWidget {
  const _ClientEstimateListItem({required this.estimate});

  final EstimateModel estimate;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      onTap: () => context.push('/estimate/${estimate.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  estimate.objectTitle,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  formatDate(estimate.estimateDate),
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(estimate.totalAmount),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              StatusBadge(status: estimate.status),
            ],
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
