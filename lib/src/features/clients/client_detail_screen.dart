import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/ui.dart';

class ClientDetailScreen extends ConsumerWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsProvider);
    final estimates = ref.watch(estimatesProvider);
    return clients.when(
      loading: () => const Scaffold(body: LoadingPane()),
      error: (error, _) => Scaffold(body: ErrorPane(error: error)),
      data: (items) {
        final client = items.where((item) => item.id == clientId).firstOrNull;
        if (client == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Клиент не найден',
              body: 'Возможно, клиент был удалён на другом устройстве.',
            ),
          );
        }
        final clientEstimates =
            estimates.asData?.value
                .where((estimate) => estimate.clientId == client.id)
                .toList() ??
            const <EstimateModel>[];
        return Scaffold(
          appBar: AppBar(
            title: const Text('Клиент'),
            actions: [
              IconButton(
                tooltip: 'Редактировать клиента',
                onPressed: () => context.push('/clients/${client.id}/edit'),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          body: ResponsiveListView(
            maxWidth: 720,
            children: [
              _ClientIdentityCard(
                client: client,
                estimateCount: clientEstimates.length,
              ),
              if (client.phone?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 12),
                _ContactActions(phone: client.phone!),
              ],
              if (client.objectAddress?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 14),
                _InfoCard(
                  icon: Icons.location_on_outlined,
                  title: 'Объект',
                  value: client.objectAddress!,
                ),
              ],
              if (client.notes?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 12),
                _InfoCard(
                  icon: Icons.notes_outlined,
                  title: 'Заметка',
                  value: client.notes!,
                ),
              ],
              const SizedBox(height: 18),
              SectionHeader(
                title: 'Сметы клиента',
                action: clientEstimates.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => context.push(
                          '/estimates/client/${Uri.encodeComponent(client.id)}',
                        ),
                        child: const Text('Все сметы'),
                      ),
              ),
              const SizedBox(height: 8),
              if (estimates.isLoading)
                const LoadingPane()
              else if (clientEstimates.isEmpty)
                const _ClientEstimateEmptyState()
              else
                Column(
                  children: [
                    for (final estimate in clientEstimates.take(4)) ...[
                      _ClientEstimateRow(estimate: estimate),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => context.push('/clients/${client.id}/edit'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Редактировать данные'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ClientIdentityCard extends StatelessWidget {
  const _ClientIdentityCard({
    required this.client,
    required this.estimateCount,
  });

  final ClientModel client;
  final int estimateCount;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 27,
            backgroundColor: AppColors.orangeLight,
            foregroundColor: AppColors.orangeDark,
            child: Text(
              client.name.isEmpty
                  ? '?'
                  : client.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (client.phone?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    client.phone!,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 9),
                const _ClientRoleBadge(),
                if (estimateCount > 0) ...[
                  const SizedBox(height: 7),
                  Text(
                    '$estimateCount ${_estimateWord(estimateCount)}',
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientRoleBadge extends StatelessWidget {
  const _ClientRoleBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.orangeLight,
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Text(
        'Клиент',
        style: TextStyle(
          color: AppColors.orangeDark,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ContactActions extends StatelessWidget {
  const _ContactActions({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_outlined, color: AppColors.orangeDark),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  phone,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _openPhoneUri(context, 'tel:${_phoneDigits(phone)}'),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Позвонить'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      _openPhoneUri(context, 'sms:${_phoneDigits(phone)}'),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Написать'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientEstimateRow extends StatelessWidget {
  const _ClientEstimateRow({required this.estimate});

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

class _ClientEstimateEmptyState extends StatelessWidget {
  const _ClientEstimateEmptyState();

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: const Text(
        'Для этого клиента пока нет смет.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

Future<void> _openPhoneUri(BuildContext context, String value) async {
  final uri = Uri.parse(value);
  final opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
  if (!context.mounted || opened) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'На этом устройстве не удалось открыть приложение для связи',
      ),
    ),
  );
}

String _phoneDigits(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 11 && digits.startsWith('8')) {
    return '7${digits.substring(1)}';
  }
  return digits;
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
