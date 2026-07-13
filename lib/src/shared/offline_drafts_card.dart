import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_theme.dart';
import '../data/models.dart';
import '../data/offline_sync_service.dart';
import 'ui.dart';

class OfflineDraftsCard extends StatelessWidget {
  const OfflineDraftsCard({
    super.key,
    required this.kind,
    required this.entries,
    required this.syncing,
    required this.onRetry,
    required this.onDiscard,
  });

  final String kind;
  final List<OfflineDraftEntry> entries;
  final bool syncing;
  final Future<void> Function() onRetry;
  final Future<void> Function(String id) onDiscard;

  bool get _isEstimate => kind == OfflineDraftKind.estimate;

  @override
  Widget build(BuildContext context) {
    final label = _isEstimate ? 'смет' : 'объектов';
    return SmetchikCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.orangeLight,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  color: AppColors.orangeDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Черновики $label на устройстве',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      syncing
                          ? 'Проверяем подключение...'
                          : 'Сохранятся в аккаунте, когда появится интернет',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Синхронизировать',
                onPressed: syncing ? null : onRetry,
                icon: syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final entry in entries) ...[
            _OfflineDraftTile(
              entry: entry,
              isEstimate: _isEstimate,
              onDiscard: onDiscard,
            ),
            if (entry != entries.last) const Divider(height: 18),
          ],
        ],
      ),
    );
  }
}

class _OfflineDraftTile extends StatelessWidget {
  const _OfflineDraftTile({
    required this.entry,
    required this.isEstimate,
    required this.onDiscard,
  });

  final OfflineDraftEntry entry;
  final bool isEstimate;
  final Future<void> Function(String id) onDiscard;

  @override
  Widget build(BuildContext context) {
    final title = isEstimate
        ? entry.estimateDraft.objectTitle
        : entry.projectDraft.title;
    final subtitle = isEstimate
        ? _estimateSubtitle(entry.estimateDraft)
        : _projectSubtitle(entry.projectDraft);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.push(
          isEstimate
              ? '/estimate/offline/${entry.id}'
              : '/projects/offline/${entry.id}',
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
          child: Row(
            children: [
              Icon(
                isEstimate ? Icons.description_outlined : Icons.domain_outlined,
                color: AppColors.orange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty
                          ? (isEstimate ? 'Новая смета' : 'Новый объект')
                          : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (entry.lastError != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        entry.lastError!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Удалить черновик',
                onPressed: () => onDiscard(entry.id),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _estimateSubtitle(EstimateDraft draft) {
    final client = draft.clientName.trim();
    return '${client.isEmpty ? 'Без клиента' : client} · ${formatMoney(draft.totalAmount)}';
  }

  String _projectSubtitle(ProjectDraft draft) {
    return '${ProjectStatus.label(draft.status)} · ${formatMoney(draft.plannedRevenue)}';
  }
}
