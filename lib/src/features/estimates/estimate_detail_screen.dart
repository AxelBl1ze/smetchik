import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/pdf_service.dart';
import '../../data/repository.dart';
import '../../data/signing.dart';
import '../../shared/ui.dart';
import '../../shared/upgrade_sheet.dart';

class EstimateDetailScreen extends ConsumerStatefulWidget {
  const EstimateDetailScreen({super.key, required this.estimateId});

  final String estimateId;

  @override
  ConsumerState<EstimateDetailScreen> createState() =>
      _EstimateDetailScreenState();
}

class _EstimateDetailScreenState extends ConsumerState<EstimateDetailScreen> {
  Future<Uint8List>? _pdfFuture;
  String? _pdfFingerprint;
  bool _pdfActionBusy = false;

  String get estimateId => widget.estimateId;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(estimateDetailProvider(estimateId));
    final profile = ref.watch(profileProvider);
    final isLocked = detail.asData?.value.estimate.isLocked == true;

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
            tooltip: isLocked ? 'Создать новую версию' : 'Редактировать',
            onPressed: () => context.push(
              '/estimate/$estimateId/edit${isLocked ? '?revision=true' : ''}',
            ),
            icon: Icon(isLocked ? Icons.copy_outlined : Icons.edit_outlined),
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
              hasClientSignature: value.estimate.isLocked,
              onAcceptWithSignature: () => _acceptWithClientSignature(
                context,
                ref,
                value,
                profile.asData?.value,
              ),
              onStatusChanged: (status) =>
                  _setStatus(context, ref, value.estimate.id, status),
            ),
            if (value.estimate.isLocked) ...[
              const SizedBox(height: 10),
              _ClientSignatureStatusCard(
                estimate: value.estimate,
                onCreateRevision: () => context.push(
                  '/estimate/${value.estimate.id}/edit?revision=true',
                ),
              ),
            ],
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
              onPressed: _pdfActionBusy
                  ? null
                  : () => _sharePdf(context, ref, value, profile.asData?.value),
              icon: _pdfActionBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share),
              label: Text(_pdfActionBusy ? 'Готовим PDF...' : 'Поделиться PDF'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pdfActionBusy
                  ? null
                  : () =>
                        _previewPdf(context, ref, value, profile.asData?.value),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Предпросмотр PDF'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _duplicateEstimate(
                context,
                ref,
                value,
                profile.asData?.value,
              ),
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Дублировать смету'),
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
    final fingerprint = _buildPdfFingerprint(detail, profile);
    if (_pdfFuture == null || _pdfFingerprint != fingerprint) {
      _pdfFingerprint = fingerprint;
      _pdfFuture = PdfService.buildEstimatePdf(
        detail: detail,
        profile: profile,
      );
    }
    return _pdfFuture!;
  }

  String _buildPdfFingerprint(EstimateDetail detail, ProfileModel? profile) {
    final estimate = detail.estimate;
    return Object.hashAll([
      estimate.id,
      estimate.objectTitle,
      estimate.estimateDate,
      estimate.durationDays,
      estimate.totalAmount,
      estimate.clientSignatureUrl,
      estimate.clientSignedAt,
      estimate.client?.name,
      estimate.client?.phone,
      estimate.client?.objectAddress,
      for (final line in detail.lines) ...[
        line.id,
        line.title,
        line.unit,
        line.quantity,
        line.unitPrice,
        line.lineTotal,
        line.sortOrder,
      ],
      profile?.fullName,
      profile?.phone,
      profile?.specialization,
      profile?.currency,
      profile?.hasActivePro,
      profile?.logoUrl,
      profile?.signatureUrl,
      profile?.paymentQrUrl,
      profile?.paymentQrLabel,
      profile?.contactQrUrl,
      profile?.contactQrLabel,
      profile?.pdfShowBrandHeader,
      profile?.pdfShowSignatures,
      profile?.pdfShowServiceMark,
      profile?.pdfTemplate,
      profile?.pdfAccentColor,
      profile?.pdfPaymentTerms,
      profile?.pdfFooterNote,
    ]).toString();
  }

  Future<void> _sharePdf(
    BuildContext context,
    WidgetRef ref,
    EstimateDetail detail,
    ProfileModel? profile,
  ) async {
    setState(() => _pdfActionBusy = true);
    try {
      final bytes = await _resolvePdf(ref, detail, profile);
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
      if (EstimateStatus.normalize(detail.estimate.status) ==
          EstimateStatus.draft) {
        await ref
            .read(repositoryProvider)
            .updateEstimateStatus(detail.estimate.id, EstimateStatus.sent);
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
    } finally {
      if (mounted) setState(() => _pdfActionBusy = false);
    }
  }

  Future<void> _previewPdf(
    BuildContext context,
    WidgetRef ref,
    EstimateDetail detail,
    ProfileModel? profile,
  ) async {
    setState(() => _pdfActionBusy = true);
    try {
      final bytes = await _resolvePdf(ref, detail, profile);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (error) {
      if (context.mounted) {
        _showFloatingSnackBar(context, error.toString(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _pdfActionBusy = false);
    }
  }

  Future<Uint8List> _resolvePdf(
    WidgetRef ref,
    EstimateDetail detail,
    ProfileModel? profile,
  ) {
    final signedPath = detail.estimate.signedPdfStoragePath;
    if (signedPath != null && signedPath.isNotEmpty) {
      return ref.read(repositoryProvider).downloadSignedEstimatePdf(signedPath);
    }
    return _buildPdf(detail, profile);
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
      EstimateStatus.sent => 'Смета отмечена как отправленная',
      EstimateStatus.accepted => 'Смета принята клиентом',
      EstimateStatus.inProgress => 'Смета перешла в работу',
      EstimateStatus.completed => 'Работа завершена, сумма ушла в полученные',
      EstimateStatus.declined => 'Смета отклонена',
      EstimateStatus.draft => 'Смета возвращена в черновик',
      _ => 'Статус обновлён',
    };
    _showFloatingSnackBar(context, message);
  }

  Future<void> _acceptWithClientSignature(
    BuildContext context,
    WidgetRef ref,
    EstimateDetail detail,
    ProfileModel? profile,
  ) async {
    final clientName = detail.estimate.client?.name.trim() ?? '';
    if (clientName.isEmpty) {
      _showFloatingSnackBar(
        context,
        'Перед принятием укажите ФИО клиента в смете.',
        isError: true,
      );
      return;
    }
    final clientPhone = (detail.estimate.client?.phone ?? '').trim();
    if (clientPhone.isEmpty) {
      _showFloatingSnackBar(
        context,
        'Перед принятием укажите телефон клиента в смете.',
        isError: true,
      );
      return;
    }
    final verification =
        await showModalBottomSheet<EstimateSignatureOtpChallenge>(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          builder: (context) => _ClientSignatureVerificationSheet(
            clientName: clientName,
            clientPhone: clientPhone,
            onRequestCode: () => ref
                .read(repositoryProvider)
                .requestEstimateSignatureCode(estimateId: detail.estimate.id),
            onVerifyCode: (challengeId, code) => ref
                .read(repositoryProvider)
                .verifyEstimateSignatureCode(
                  challengeId: challengeId,
                  code: code,
                ),
          ),
        );
    if (verification == null) return;
    if (!context.mounted) return;

    final bytes = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => _ClientSignaturePadSheet(
        clientName: clientName,
        verifiedPhone: clientPhone,
      ),
    );
    if (bytes == null) return;

    setState(() => _pdfActionBusy = true);
    try {
      final signedAt = DateTime.now().toUtc();
      final signedDetail = EstimateDetail(
        estimate: detail.estimate.copyWith(
          clientSignedAt: signedAt,
          clientSignedName: clientName,
          clientSignedPhone: clientPhone,
          clientSignatureOtpChallengeId: verification.id,
          clientPhoneVerifiedAt: verification.verifiedAt,
          clientSignatureStatementVersion: clientSignatureStatementVersion,
        ),
        lines: detail.lines,
      );
      final signedPdfBytes = await PdfService.buildEstimatePdf(
        detail: signedDetail,
        profile: profile,
        clientSignatureBytes: bytes,
      );
      await ref
          .read(repositoryProvider)
          .acceptEstimateWithClientSignature(
            estimateId: detail.estimate.id,
            signatureBytes: bytes,
            signedPdfBytes: signedPdfBytes,
            signedSnapshot: buildSignedEstimateSnapshot(
              detail: signedDetail,
              profile: profile,
              signedAt: signedAt,
              phoneVerifiedAt: verification.verifiedAt,
              signatureChallengeId: verification.id,
            ),
            signedAt: signedAt,
            clientName: clientName,
            clientPhone: clientPhone,
            documentVersion: detail.estimate.documentVersion,
            signatureChallengeId: verification.id,
          );
      ref.invalidate(estimatesProvider);
      ref.invalidate(estimateDetailProvider(detail.estimate.id));
      if (!context.mounted) return;
      _showFloatingSnackBar(context, 'Смета принята и подписана клиентом');
    } catch (error) {
      if (context.mounted) {
        _showFloatingSnackBar(context, error.toString(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _pdfActionBusy = false);
    }
  }

  Future<void> _duplicateEstimate(
    BuildContext context,
    WidgetRef ref,
    EstimateDetail detail,
    ProfileModel? profile,
  ) async {
    if (profile?.hasActivePro != true) {
      _showUpgradeDialog(
        context,
        'Дублирование смет доступно на тарифе Профи.',
      );
      return;
    }

    try {
      final repository = ref.read(repositoryProvider);
      final copiedAt = DateTime.now().microsecondsSinceEpoch;
      final copyId = await repository.saveEstimateDraft(
        EstimateDraft(
          objectTitle: '${detail.estimate.objectTitle} (копия)',
          clientId: detail.estimate.clientId,
          clientName: detail.estimate.client?.name ?? '',
          clientPhone: detail.estimate.client?.phone,
          estimateDate: DateTime.now(),
          durationDays: detail.estimate.durationDays,
          lines: [
            for (var i = 0; i < detail.lines.length; i++)
              detail.lines[i].copyWith(id: 'copy-$i-$copiedAt', sortOrder: i),
          ],
        ),
      );
      ref.invalidate(estimatesProvider);
      ref.invalidate(estimateDetailProvider(copyId));
      if (!context.mounted) return;
      _showFloatingSnackBar(context, 'Копия сметы создана');
      context.go('/estimate/$copyId');
    } catch (error) {
      if (context.mounted) {
        _showFloatingSnackBar(context, error.toString(), isError: true);
      }
    }
  }

  void _showUpgradeDialog(BuildContext context, String message) {
    showUpgradeSheet(
      context: context,
      title: 'Нужен тариф Профи',
      message: message,
      onOpenPlans: () => context.go('/settings'),
    );
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
    required this.hasClientSignature,
    required this.onAcceptWithSignature,
    required this.onStatusChanged,
  });

  final String status;
  final bool hasClientSignature;
  final VoidCallback onAcceptWithSignature;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = EstimateStatus.normalize(status);
    final primary = switch (normalizedStatus) {
      EstimateStatus.draft => (
        'Отметить отправленной',
        Icons.send_outlined,
        EstimateStatus.sent,
      ),
      EstimateStatus.sent => (
        hasClientSignature ? 'Клиент принял' : 'Принять с подписью',
        Icons.draw_outlined,
        EstimateStatus.accepted,
      ),
      EstimateStatus.accepted => (
        'Начать работу',
        Icons.handyman_outlined,
        EstimateStatus.inProgress,
      ),
      EstimateStatus.inProgress => (
        'Завершить работу',
        Icons.done_all,
        EstimateStatus.completed,
      ),
      EstimateStatus.completed => (
        'Вернуть в работу',
        Icons.undo,
        EstimateStatus.inProgress,
      ),
      EstimateStatus.declined => (
        'Вернуть в черновик',
        Icons.undo,
        EstimateStatus.draft,
      ),
      _ => null,
    };

    final canDecline =
        normalizedStatus == EstimateStatus.sent ||
        normalizedStatus == EstimateStatus.accepted ||
        normalizedStatus == EstimateStatus.inProgress;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 560;
          final primaryButton = primary == null
              ? const SizedBox.shrink()
              : FilledButton.icon(
                  onPressed:
                      normalizedStatus == EstimateStatus.sent &&
                          !hasClientSignature
                      ? onAcceptWithSignature
                      : () => onStatusChanged(primary.$3),
                  icon: Icon(primary.$2),
                  label: Text(primary.$1),
                );
          final declineButton = !canDecline
              ? const SizedBox.shrink()
              : OutlinedButton.icon(
                  onPressed: () => onStatusChanged(EstimateStatus.declined),
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

class _ClientSignatureStatusCard extends StatelessWidget {
  const _ClientSignatureStatusCard({
    required this.estimate,
    required this.onCreateRevision,
  });

  final EstimateModel estimate;
  final VoidCallback onCreateRevision;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.orangeLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.verified_outlined,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Версия ${estimate.documentVersion} подписана клиентом',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      estimate.clientSignedAt == null
                          ? 'Подпись добавлена в финальный PDF'
                          : 'Подписано ${formatDateTime(estimate.clientSignedAt!)}${estimate.clientPhoneVerifiedAt == null ? '' : ' · номер подтверждён'}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onCreateRevision,
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Создать новую версию'),
          ),
        ],
      ),
    );
  }
}

class _ClientSignatureVerificationSheet extends StatefulWidget {
  const _ClientSignatureVerificationSheet({
    required this.clientName,
    required this.clientPhone,
    required this.onRequestCode,
    required this.onVerifyCode,
  });

  final String clientName;
  final String clientPhone;
  final Future<EstimateSignatureOtpChallenge> Function() onRequestCode;
  final Future<EstimateSignatureOtpChallenge> Function(
    String challengeId,
    String code,
  )
  onVerifyCode;

  @override
  State<_ClientSignatureVerificationSheet> createState() =>
      _ClientSignatureVerificationSheetState();
}

class _ClientSignatureVerificationSheetState
    extends State<_ClientSignatureVerificationSheet> {
  final _code = TextEditingController();
  EstimateSignatureOtpChallenge? _challenge;
  bool _sending = false;
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sending || _verifying;
    final challenge = _challenge;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.orangeLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Подтвердите клиента',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${widget.clientName} · ${widget.clientPhone}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    challenge == null
                        ? 'Отправим одноразовый код в Telegram на номер клиента. После проверки станет доступна подпись сметы.'
                        : 'Код отправлен на ${challenge.maskedPhone}. Он действует 10 минут и будет использован только для этой сметы.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (challenge == null)
                  FilledButton.icon(
                    onPressed: busy ? null : _requestCode,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.telegram),
                    label: const Text('Отправить код в Telegram'),
                  )
                else ...[
                  TextField(
                    controller: _code,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Код из Telegram',
                      counterText: '',
                      prefixIcon: Icon(Icons.password_outlined),
                    ),
                    autofillHints: const [AutofillHints.oneTimeCode],
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => busy ? null : _verifyCode(),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: busy ? null : _verifyCode,
                    icon: _verifying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Подтвердить код'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : _requestCode,
                    child: const Text('Отправить новый код'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestCode() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final challenge = await widget.onRequestCode();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _code.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    final challenge = _challenge;
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    if (challenge == null || code.length != 6) {
      setState(() => _error = 'Введите все 6 цифр кода.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final verified = await widget.onVerifyCode(challenge.id, code);
      if (mounted) Navigator.of(context).pop(verified);
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  String _readableError(Object error) {
    final message = error.toString().replaceFirst(
      'AuthException(message: ',
      '',
    );
    return message.replaceFirst(RegExp(r', statusCode: .*\)$'), '');
  }
}

class _ClientSignaturePadSheet extends StatefulWidget {
  const _ClientSignaturePadSheet({
    required this.clientName,
    required this.verifiedPhone,
  });

  final String? clientName;
  final String verifiedPhone;

  @override
  State<_ClientSignaturePadSheet> createState() =>
      _ClientSignaturePadSheetState();
}

class _ClientSignaturePadSheetState extends State<_ClientSignaturePadSheet> {
  final _paintKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  bool _confirmedStatement = false;

  bool get _canSave =>
      _confirmedStatement && _strokes.any((stroke) => stroke.length > 1);

  @override
  Widget build(BuildContext context) {
    final clientName = widget.clientName?.trim();
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.orangeLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.draw_outlined,
                        color: AppColors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Подпись клиента',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            clientName?.isNotEmpty == true
                                ? '$clientName · номер ${widget.verifiedPhone} подтверждён'
                                : 'Клиент подтверждает принятие сметы',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    clientSignatureStatement,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
                Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _confirmedStatement,
                    onChanged: (value) =>
                        setState(() => _confirmedStatement = value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Ознакомился(ась) со сметой и подтверждаю принятие',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: 2.6,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _confirmedStatement
                            ? (details) => _startStroke(details.localPosition)
                            : null,
                        onPanUpdate: _confirmedStatement
                            ? (details) => _appendPoint(details.localPosition)
                            : null,
                        child: CustomPaint(
                          key: _paintKey,
                          painter: _ClientSignaturePainter(strokes: _strokes),
                          child: _strokes.isNotEmpty
                              ? const SizedBox.expand()
                              : Center(
                                  child: Text(
                                    _confirmedStatement
                                        ? 'клиент расписывается здесь'
                                        : 'подтвердите принятие перед подписью',
                                    style: TextStyle(
                                      color: AppColors.textHint,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _strokes.isNotEmpty ? _clear : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Очистить'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _canSave ? _save : null,
                        icon: const Icon(Icons.check),
                        label: const Text('Принять'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startStroke(Offset point) {
    setState(() => _strokes.add([point]));
  }

  void _appendPoint(Offset point) {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.add(point));
  }

  void _clear() {
    setState(_strokes.clear);
  }

  Future<void> _save() async {
    final box = _paintKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? const Size(520, 200);
    final bytes = await _renderSignature(size);
    if (!mounted) return;
    Navigator.of(context).pop(bytes);
  }

  Future<Uint8List> _renderSignature(Size sourceSize) async {
    const targetSize = Size(720, 280);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(
      targetSize.width / sourceSize.width,
      targetSize.height / sourceSize.height,
    );
    _ClientSignaturePainter(strokes: _strokes).paint(canvas, sourceSize);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      targetSize.width.round(),
      targetSize.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}

class _ClientSignaturePainter extends CustomPainter {
  const _ClientSignaturePainter({required this.strokes});

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.graphite
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ClientSignaturePainter oldDelegate) => true;
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
