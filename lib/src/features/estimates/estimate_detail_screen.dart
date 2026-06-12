import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/pdf_service.dart';
import '../../data/repository.dart';
import '../../shared/ui.dart';

class EstimateDetailScreen extends ConsumerWidget {
  const EstimateDetailScreen({super.key, required this.estimateId});

  final String estimateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(estimateDetailProvider(estimateId));
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Смета'),
        actions: [
          IconButton(
            tooltip: 'На главную',
            onPressed: () => context.go('/home'),
            icon: const Icon(Icons.home_outlined),
          ),
          IconButton(
            tooltip: 'Редактировать',
            onPressed: () => context.push('/estimate/$estimateId/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: detail.when(
        data: (value) => ResponsiveListView(
          maxWidth: 900,
          children: [
            SmetchikCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          value.estimate.objectTitle,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      StatusBadge(status: value.estimate.status),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _MetricRow(
                    leftLabel: 'Стоимость',
                    leftValue: formatMoney(value.estimate.totalAmount),
                    rightLabel: 'Дата',
                    rightValue: formatDate(value.estimate.estimateDate),
                  ),
                  const SizedBox(height: 10),
                  _MetricRow(
                    leftLabel: 'Клиент',
                    leftValue: value.estimate.client?.name ?? 'Не указан',
                    rightLabel: 'Срок',
                    rightValue: value.estimate.durationDays == null
                        ? 'Не указан'
                        : '${value.estimate.durationDays} дн.',
                  ),
                ],
              ),
            ),
            _EstimateStatusActions(
              status: value.estimate.status,
              onStatusChanged: (status) =>
                  _setStatus(context, ref, value.estimate.id, status),
            ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'Работы'),
            const SizedBox(height: 8),
            for (var i = 0; i < value.lines.length; i++) ...[
              SmetchikCard(
                child: Row(
                  children: [
                    Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: AppColors.orangeDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value.lines[i].title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${formatQuantity(value.lines[i].quantity)} ${value.lines[i].unit} × ${formatMoney(value.lines[i].unitPrice)}',
                            style: const TextStyle(
                              color: AppColors.textHint,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatMoney(value.lines[i].lineTotal),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 10),
            _PdfPreviewCard(detail: value),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () =>
                  _sharePdf(context, ref, value, profile.asData?.value),
              icon: const Icon(Icons.ios_share),
              label: const Text('Поделиться PDF'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  _previewPdf(context, value, profile.asData?.value),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Предпросмотр PDF'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.home_outlined),
              label: const Text('На главную'),
            ),
          ],
        ),
        loading: () => const LoadingPane(),
        error: (error, _) => ErrorPane(error: error),
      ),
    );
  }

  Future<Uint8List> _buildPdf(EstimateDetail detail, ProfileModel? profile) {
    return PdfService.buildEstimatePdf(detail: detail, profile: profile);
  }

  Future<void> _sharePdf(
    BuildContext context,
    WidgetRef ref,
    EstimateDetail detail,
    ProfileModel? profile,
  ) async {
    try {
      final bytes = await _buildPdf(detail, profile);
      final filename = 'smeta-${detail.estimate.id.substring(0, 8)}.pdf';
      await SharePlus.instance.share(
        ShareParams(
          title: 'Смета ${detail.estimate.objectTitle}',
          text: _shareText(detail),
          files: [
            XFile.fromData(bytes, mimeType: 'application/pdf', name: filename),
          ],
          fileNameOverrides: [filename],
          downloadFallbackEnabled: true,
        ),
      );
      if (detail.estimate.status == 'draft') {
        await ref
            .read(repositoryProvider)
            .updateEstimateStatus(detail.estimate.id, 'sent');
      }
      ref.invalidate(estimatesProvider);
      ref.invalidate(estimateDetailProvider(detail.estimate.id));
      if (context.mounted) {
        _showFloatingSnackBar(context, 'PDF готов к отправке');
      }
    } catch (error) {
      if (context.mounted) {
        _showFloatingSnackBar(context, error.toString(), isError: true);
      }
    }
  }

  Future<void> _previewPdf(
    BuildContext context,
    EstimateDetail detail,
    ProfileModel? profile,
  ) async {
    final bytes = await _buildPdf(detail, profile);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    String estimateId,
    String status,
  ) async {
    await ref.read(repositoryProvider).updateEstimateStatus(estimateId, status);
    ref.invalidate(estimatesProvider);
    ref.invalidate(estimateDetailProvider(estimateId));
    if (!context.mounted) return;
    final message = switch (status) {
      'approved' => 'Смета принята в работу',
      'completed' => 'Работа завершена, сумма ушла в полученные',
      'declined' => 'Смета отклонена',
      'draft' => 'Смета возвращена в черновик',
      _ => 'Статус обновлён',
    };
    _showFloatingSnackBar(context, message);
  }

  void _showFloatingSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: isError ? 4 : 2),
        ),
      );
  }

  String _shareText(EstimateDetail detail) {
    final object = detail.estimate.objectTitle.trim();
    final client = detail.estimate.client?.name.trim();
    final total = formatMoney(detail.estimate.totalAmount);
    final greeting = client?.isNotEmpty == true
        ? '$client, добрый день!'
        : 'Добрый день!';
    return '$greeting Направляю смету${object.isEmpty ? '' : ' по объекту «$object»'}. '
        'Итого: $total. PDF во вложении.';
  }
}

class _EstimateStatusActions extends StatelessWidget {
  const _EstimateStatusActions({
    required this.status,
    required this.onStatusChanged,
  });

  final String status;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final primary = switch (status) {
      'draft' ||
      'sent' => ('Принять в работу', Icons.handyman_outlined, 'approved'),
      'approved' => ('Завершить работу', Icons.done_all, 'completed'),
      'completed' => ('Вернуть в работу', Icons.undo, 'approved'),
      'declined' => ('Вернуть в черновик', Icons.undo, 'draft'),
      _ => null,
    };

    final canDecline =
        status == 'draft' || status == 'sent' || status == 'approved';

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 560;
          final primaryButton = primary == null
              ? const SizedBox.shrink()
              : FilledButton.icon(
                  onPressed: () => onStatusChanged(primary.$3),
                  icon: Icon(primary.$2),
                  label: Text(primary.$1),
                );
          final declineButton = !canDecline
              ? const SizedBox.shrink()
              : OutlinedButton.icon(
                  onPressed: () => onStatusChanged('declined'),
                  icon: const Icon(Icons.close),
                  label: const Text('Отклонить'),
                );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                primaryButton,
                if (canDecline) ...[const SizedBox(height: 8), declineButton],
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: primaryButton),
              if (canDecline) ...[
                const SizedBox(width: 8),
                Expanded(child: declineButton),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
  });

  final String leftLabel;
  final String leftValue;
  final String rightLabel;
  final String rightValue;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Metric(label: leftLabel, value: leftValue),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Metric(label: rightLabel, value: rightValue),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textHint, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _PdfPreviewCard extends StatelessWidget {
  const _PdfPreviewCard({required this.detail});

  final EstimateDetail detail;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Сметчик',
                style: TextStyle(
                  color: AppColors.orange,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                formatDate(detail.estimate.estimateDate),
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            detail.estimate.objectTitle,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          for (final line in detail.lines.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      line.title,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    formatMoney(line.lineTotal),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          const Divider(height: 18),
          Row(
            children: [
              const Text(
                'Итого',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                formatMoney(detail.estimate.totalAmount),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
