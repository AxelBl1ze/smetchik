import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/pdf_service.dart';
import '../../data/project_export_service.dart';
import '../../data/repository.dart';
import '../../shared/form_sheet.dart';
import '../../shared/smetchik_date_picker.dart';
import '../../shared/ui.dart';
import '../../shared/upgrade_sheet.dart';
import 'project_status_widgets.dart';

enum _ProjectExportFormat { excel, pdf }

extension on _ProjectExportFormat {
  String get label => switch (this) {
    _ProjectExportFormat.excel => 'Excel-таблица',
    _ProjectExportFormat.pdf => 'PDF-отчёт',
  };

  String get subtitle => switch (this) {
    _ProjectExportFormat.excel => 'Сводка, расходы и поступления',
    _ProjectExportFormat.pdf => 'Готовый отчёт по объекту',
  };

  IconData get icon => switch (this) {
    _ProjectExportFormat.excel => Icons.table_view_outlined,
    _ProjectExportFormat.pdf => Icons.picture_as_pdf_outlined,
  };

  String get mimeType => switch (this) {
    _ProjectExportFormat.excel =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ProjectExportFormat.pdf => 'application/pdf',
  };
}

class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  bool _busy = false;
  bool _exporting = false;
  bool _showMaterials = false;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(projectDetailProvider(widget.projectId));
    final profile = ref.watch(profileProvider);
    final projectDetail = detail.asData?.value;
    final hasPro = profile.asData?.value?.hasActivePro == true;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Назад к сметам',
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          projectDetail?.project.title ?? 'Объект',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (projectDetail != null && hasPro)
            IconButton(
              tooltip: 'Экспортировать',
              onPressed: _exporting
                  ? null
                  : () => _openExportSheet(projectDetail),
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_outlined),
            ),
          if (projectDetail != null && !hasPro)
            IconButton(
              tooltip: 'Экспорт доступен в Профи',
              onPressed: () => showUpgradeSheet(
                context: context,
                message:
                    'Экспорт операций в Excel и PDF доступен на тарифе Профи.',
                onOpenPlans: () => context.go('/settings'),
              ),
              icon: const Icon(Icons.ios_share_outlined),
            ),
          IconButton(
            tooltip: 'Редактировать объект',
            onPressed: () => context.push('/projects/${widget.projectId}/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: detail.when(
        data: (value) => ResponsiveListView(
          maxWidth: 900,
          children: [
            _ProjectOverviewCard(
              project: value.project,
              busy: _busy,
              onStatusChanged: (status) => _changeStatus(value.project, status),
            ),
            const SizedBox(height: 12),
            _ProjectFinanceCard(project: value.project),
            const SizedBox(height: 12),
            if (profile.asData?.value?.hasActivePro == true)
              _ExpenseAnalyticsCard(transactions: value.transactions)
            else
              _LockedAnalyticsCard(onUpgrade: () => context.go('/settings')),
            const SizedBox(height: 16),
            _ProjectDetailModeSwitcher(
              showMaterials: _showMaterials,
              onChanged: (value) => setState(() => _showMaterials = value),
            ),
            const SizedBox(height: 12),
            SectionHeader(
              title: _showMaterials ? 'Материалы' : 'Операции',
              action: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : _showMaterials
                    ? () => _openMaterialSheet(value)
                    : () => _openTransactionSheet(value),
                icon: const Icon(Icons.add, size: 18),
                label: Text(_showMaterials ? 'Материал' : 'Операцию'),
              ),
            ),
            const SizedBox(height: 8),
            if (_showMaterials && !hasPro)
              _LockedMaterialsCard(onUpgrade: () => context.go('/settings'))
            else if (_showMaterials)
              _MaterialsPanel(
                materials: value.materials,
                busy: _busy,
                onAdd: () => _openMaterialSheet(value),
                onEdit: (material) => _openMaterialSheet(value, material),
                onPurchase: (material) =>
                    _openMaterialPurchaseSheet(value, material),
                onDelete: _deleteMaterial,
              )
            else if (value.transactions.isEmpty)
              EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Операций пока нет',
                body:
                    'Добавьте расход на материалы или поступление по объекту.',
                action: FilledButton.icon(
                  onPressed: _busy ? null : () => _openTransactionSheet(value),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить операцию'),
                ),
              )
            else
              for (final transaction in value.transactions) ...[
                _TransactionCard(
                  transaction: transaction,
                  onEdit: () => _openTransactionSheet(value, transaction),
                  onDelete: () => _deleteTransaction(transaction),
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _deleteProject(value.project),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Удалить объект'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
              ),
            ),
          ],
        ),
        loading: () => const LoadingPane(),
        error: (error, _) => ErrorPane(error: error),
      ),
    );
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/estimates');
  }

  Future<void> _openExportSheet(ProjectDetail detail) async {
    final format = await showModalBottomSheet<_ProjectExportFormat>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ProjectExportSheet(),
    );
    if (format != null) await _exportProject(detail, format);
  }

  Future<void> _exportProject(
    ProjectDetail detail,
    _ProjectExportFormat format,
  ) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final profile = await ref.read(profileProvider.future);
      if (profile?.hasActivePro != true) {
        if (mounted) {
          showUpgradeSheet(
            context: context,
            message: 'Экспорт операций в Excel и PDF доступен на тарифе Профи.',
            onOpenPlans: () => context.go('/settings'),
          );
        }
        return;
      }
      final slug = detail.project.title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-zа-я0-9]+', caseSensitive: false), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final filename = switch (format) {
        _ProjectExportFormat.excel =>
          'obekt-${slug.isEmpty ? 'otchet' : slug}.xlsx',
        _ProjectExportFormat.pdf =>
          'obekt-${slug.isEmpty ? 'otchet' : slug}.pdf',
      };
      final bytes = switch (format) {
        _ProjectExportFormat.excel => ProjectExportService.buildWorkbook(
          detail,
        ),
        _ProjectExportFormat.pdf => await PdfService.buildProjectReportPdf(
          detail: detail,
          profile: profile,
        ),
      };
      await SharePlus.instance.share(
        ShareParams(
          title: 'Отчёт по объекту ${detail.project.title}',
          text: 'Отчёт по объекту «${detail.project.title}»',
          files: [
            XFile.fromData(bytes, mimeType: format.mimeType, name: filename),
          ],
          fileNameOverrides: [filename],
          downloadFallbackEnabled: true,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось подготовить экспорт: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _changeStatus(ProjectModel project, String status) async {
    if (status == project.status) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .updateProjectStatus(project.id, status);
      ref.invalidate(projectsProvider);
      ref.invalidate(projectDetailProvider(project.id));
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst('Exception: ', '');
        if (message.contains('Базовом тарифе')) {
          showUpgradeSheet(
            context: context,
            message: message,
            onOpenPlans: () => context.go('/settings'),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openTransactionSheet(
    ProjectDetail detail, [
    ProjectTransactionModel? transaction,
  ]) async {
    final result = await showModalBottomSheet<ProjectTransactionDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProjectTransactionSheet(transaction: transaction),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .saveProjectTransaction(
            projectId: detail.project.id,
            draft: result,
            transactionId: transaction?.id,
          );
      ref.invalidate(projectsProvider);
      ref.invalidate(projectDetailProvider(detail.project.id));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTransaction(ProjectTransactionModel transaction) async {
    final confirmed = await showConfirmSheet(
      context: context,
      title: 'Удалить операцию?',
      message: '«${transaction.title}» будет удалена из учёта объекта.',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .deleteProjectTransaction(transaction.id);
      ref.invalidate(projectsProvider);
      ref.invalidate(projectDetailProvider(widget.projectId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMaterialSheet(
    ProjectDetail detail, [
    ProjectMaterialModel? material,
  ]) async {
    final result = await showModalBottomSheet<ProjectMaterialDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProjectMaterialSheet(material: material),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .saveProjectMaterial(
            projectId: detail.project.id,
            draft: result,
            materialId: material?.id,
          );
      ref.invalidate(projectDetailProvider(detail.project.id));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMaterialPurchaseSheet(
    ProjectDetail detail,
    ProjectMaterialModel material,
  ) async {
    final result = await showModalBottomSheet<_MaterialPurchase>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MaterialPurchaseSheet(material: material),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .purchaseProjectMaterial(
            projectId: detail.project.id,
            material: material,
            amount: result.amount,
            quantity: result.quantity,
            purchasedAt: result.date,
            counterparty: result.counterparty,
          );
      ref.invalidate(projectDetailProvider(detail.project.id));
      ref.invalidate(projectsProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteMaterial(ProjectMaterialModel material) async {
    final confirmed = await showConfirmSheet(
      context: context,
      title: 'Удалить материал?',
      message:
          'План «${material.title}» будет удалён. Уже учтённая покупка останется в операциях.',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).deleteProjectMaterial(material.id);
      ref.invalidate(projectDetailProvider(widget.projectId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteProject(ProjectModel project) async {
    final confirmed = await showConfirmSheet(
      context: context,
      title: 'Удалить объект?',
      message: 'Все операции объекта «${project.title}» тоже будут удалены.',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).deleteProject(project.id);
      ref.invalidate(projectsProvider);
      if (!mounted) return;
      context.go('/estimates');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ProjectOverviewCard extends StatelessWidget {
  const _ProjectOverviewCard({
    required this.project,
    required this.busy,
    required this.onStatusChanged,
  });

  final ProjectModel project;
  final bool busy;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
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
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ProjectStatusSelectorButton(
                status: project.status,
                enabled: !busy,
                onChanged: onStatusChanged,
              ),
            ],
          ),
          if (project.objectAddress?.isNotEmpty == true) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: AppColors.textHint,
                  size: 16,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    project.objectAddress!,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (project.customerName?.isNotEmpty == true) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  color: AppColors.textHint,
                  size: 16,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    project.customerName!,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (project.notes?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              project.notes!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProjectFinanceCard extends StatelessWidget {
  const _ProjectFinanceCard({required this.project});

  final ProjectModel project;

  @override
  Widget build(BuildContext context) {
    final actualColor = project.actualProfit >= 0
        ? AppColors.success
        : AppColors.danger;
    final expectedColor = project.expectedProfit >= 0
        ? AppColors.success
        : AppColors.danger;
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ProjectSectionTitle(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Деньги по объекту',
            subtitle: 'План, фактические поступления и траты',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow =
                  !constraints.maxWidth.isFinite || constraints.maxWidth < 520;
              final tiles = [
                _FinanceTile(
                  label: 'Плановая выручка',
                  value: formatMoney(project.plannedRevenue),
                  color: AppColors.graphite,
                ),
                _FinanceTile(
                  label: 'Получено',
                  value: formatMoney(project.incomeAmount),
                  color: AppColors.success,
                ),
                _FinanceTile(
                  label: 'Потрачено',
                  value: formatMoney(project.expenseAmount),
                  color: AppColors.danger,
                ),
                _FinanceTile(
                  label: 'Фактическая прибыль',
                  value: formatMoney(project.actualProfit),
                  color: actualColor,
                ),
              ];
              // This screen is already vertically scrollable. Keeping the
              // summary as regular rows avoids an extra ScrollView and the
              // iOS semantics crash it can trigger during navigation.
              if (narrow) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: tiles[0]),
                        const SizedBox(width: 8),
                        Expanded(child: tiles[1]),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: tiles[2]),
                        const SizedBox(width: 8),
                        Expanded(child: tiles[3]),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  for (var index = 0; index < tiles.length; index++) ...[
                    Expanded(child: tiles[index]),
                    if (index != tiles.length - 1) const SizedBox(width: 8),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ожидаемая прибыль',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  formatMoney(project.expectedProfit),
                  style: TextStyle(
                    color: expectedColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceTile extends StatelessWidget {
  const _FinanceTile({
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _ExpenseAnalyticsCard extends StatelessWidget {
  const _ExpenseAnalyticsCard({required this.transactions});

  final List<ProjectTransactionModel> transactions;

  @override
  Widget build(BuildContext context) {
    final totals = <String, double>{};
    for (final transaction in transactions.where(
      (item) => item.type == ProjectTransactionType.expense,
    )) {
      totals[transaction.category] =
          (totals[transaction.category] ?? 0) + transaction.amount;
    }
    final total = totals.values.fold<double>(0, (sum, value) => sum + value);
    final rows = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ProjectSectionTitle(
            icon: Icons.pie_chart_outline,
            title: 'Структура расходов',
            subtitle: 'Аналитика Профи по категориям затрат',
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Text(
              'Добавьте расходы, чтобы увидеть разбивку.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            for (final entry in rows.take(5)) ...[
              _CategoryExpenseRow(
                category: entry.key,
                amount: entry.value,
                total: total,
              ),
              const SizedBox(height: 9),
            ],
        ],
      ),
    );
  }
}

class _CategoryExpenseRow extends StatelessWidget {
  const _CategoryExpenseRow({
    required this.category,
    required this.amount,
    required this.total,
  });

  final String category;
  final double amount;
  final double total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : amount / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                category,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              formatMoney(amount),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 7,
            color: AppColors.orange,
            backgroundColor: AppColors.orangeLight,
          ),
        ),
      ],
    );
  }
}

class _LockedAnalyticsCard extends StatelessWidget {
  const _LockedAnalyticsCard({required this.onUpgrade});

  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.insights_outlined,
              color: AppColors.orangeDark,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Аналитика затрат в Профи',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 3),
                Text(
                  'Разбивка расходов и прибыльность по объекту.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Открыть тарифы',
            onPressed: onUpgrade,
            icon: const Icon(
              Icons.workspace_premium,
              color: AppColors.orangeDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectSectionTitle extends StatelessWidget {
  const _ProjectSectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.orangeLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.orangeDark),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProjectDetailModeSwitcher extends StatelessWidget {
  const _ProjectDetailModeSwitcher({
    required this.showMaterials,
    required this.onChanged,
  });
  final bool showMaterials;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Expanded(
          child: _ModeButton(
            active: !showMaterials,
            icon: Icons.receipt_long_outlined,
            label: 'Операции',
            onTap: () => onChanged(false),
          ),
        ),
        Expanded(
          child: _ModeButton(
            active: showMaterials,
            icon: Icons.inventory_2_outlined,
            label: 'Материалы',
            onTap: () => onChanged(true),
          ),
        ),
      ],
    ),
  );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: active ? AppColors.graphite : Colors.transparent,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? AppColors.orange : AppColors.textSecondary,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LockedMaterialsCard extends StatelessWidget {
  const _LockedMaterialsCard({required this.onUpgrade});
  final VoidCallback onUpgrade;
  @override
  Widget build(BuildContext context) => SmetchikCard(
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.orangeLight,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.inventory_2_outlined,
            color: AppColors.orangeDark,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'План материалов в Профи',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 3),
              Text(
                'Планируйте закупки и автоматически учитывайте фактические траты.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onUpgrade,
          icon: const Icon(
            Icons.workspace_premium,
            color: AppColors.orangeDark,
          ),
        ),
      ],
    ),
  );
}

class _MaterialsPanel extends StatelessWidget {
  const _MaterialsPanel({
    required this.materials,
    required this.busy,
    required this.onAdd,
    required this.onEdit,
    required this.onPurchase,
    required this.onDelete,
  });
  final List<ProjectMaterialModel> materials;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<ProjectMaterialModel> onEdit;
  final ValueChanged<ProjectMaterialModel> onPurchase;
  final ValueChanged<ProjectMaterialModel> onDelete;
  @override
  Widget build(BuildContext context) {
    final planned = materials.fold<double>(
      0,
      (sum, item) => sum + item.plannedAmount,
    );
    final actual = materials.fold<double>(
      0,
      (sum, item) => sum + (item.actualAmount ?? 0),
    );
    if (materials.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Материалов пока нет',
        body: 'Добавьте план закупок, затем отмечайте фактические покупки.',
        action: FilledButton.icon(
          onPressed: busy ? null : onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Добавить материал'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SmetchikCard(
          child: Row(
            children: [
              Expanded(
                child: _MaterialSummary(
                  label: 'План',
                  value: formatMoney(planned),
                ),
              ),
              Container(width: 1, height: 34, color: AppColors.border),
              Expanded(
                child: _MaterialSummary(
                  label: 'Куплено',
                  value: formatMoney(actual),
                  accent: AppColors.success,
                ),
              ),
              Container(width: 1, height: 34, color: AppColors.border),
              Expanded(
                child: _MaterialSummary(
                  label: 'Осталось',
                  value: formatMoney(planned - actual),
                  accent: planned - actual < 0
                      ? AppColors.danger
                      : AppColors.orangeDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final material in materials) ...[
          _MaterialCard(
            material: material,
            busy: busy,
            onEdit: () => onEdit(material),
            onPurchase: () => onPurchase(material),
            onDelete: () => onDelete(material),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _MaterialSummary extends StatelessWidget {
  const _MaterialSummary({
    required this.label,
    required this.value,
    this.accent,
  });
  final String label;
  final String value;
  final Color? accent;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textHint,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: accent ?? AppColors.graphite,
          ),
        ),
      ],
    ),
  );
}

class _MaterialCard extends StatelessWidget {
  const _MaterialCard({
    required this.material,
    required this.busy,
    required this.onEdit,
    required this.onPurchase,
    required this.onDelete,
  });
  final ProjectMaterialModel material;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onPurchase;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => SmetchikCard(
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: material.isPurchased
                ? AppColors.success.withValues(alpha: .12)
                : AppColors.orangeLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            material.isPurchased
                ? Icons.check_circle_outline
                : Icons.inventory_2_outlined,
            color: material.isPurchased
                ? AppColors.success
                : AppColors.orangeDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                material.title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                '${_formatQuantity(material.plannedQuantity)} ${material.unit} × ${formatMoney(material.plannedUnitPrice)} · план ${formatMoney(material.plannedAmount)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (material.isPurchased)
                Text(
                  'Куплено: ${formatMoney(material.actualAmount!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'purchase') {
              onPurchase();
            } else if (value == 'edit') {
              onEdit();
            } else {
              onDelete();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'purchase',
              child: Text(
                material.isPurchased ? 'Изменить покупку' : 'Отметить покупку',
              ),
            ),
            const PopupMenuItem(value: 'edit', child: Text('Изменить план')),
            const PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
          icon: const Icon(Icons.more_horiz),
        ),
      ],
    ),
  );
  static String _formatQuantity(double value) =>
      value.toString().replaceFirst(RegExp(r'\.0$'), '');
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.transaction,
    required this.onEdit,
    required this.onDelete,
  });

  final ProjectTransactionModel transaction;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final income = transaction.type == ProjectTransactionType.income;
    final color = income ? AppColors.success : AppColors.danger;
    return SmetchikCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              income ? Icons.south_west : Icons.north_east,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  '${transaction.category}${_quantityLabel(transaction)} · ${formatDate(transaction.transactionDate)}',
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                  ),
                ),
                if (transaction.counterparty?.isNotEmpty == true)
                  Text(
                    transaction.counterparty!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${income ? '+' : '−'}${formatMoney(transaction.amount)}',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Изменить')),
                  PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
                icon: const Icon(Icons.more_horiz, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _quantityLabel(ProjectTransactionModel transaction) {
    if (transaction.quantity == null) return '';
    final quantity = transaction.quantity!.toString().replaceFirst(
      RegExp(r'\.0$'),
      '',
    );
    final unit = transaction.unit?.trim();
    return ' · $quantity${unit == null || unit.isEmpty ? '' : ' $unit'}';
  }
}

class _ProjectTransactionSheet extends StatefulWidget {
  const _ProjectTransactionSheet({this.transaction});

  final ProjectTransactionModel? transaction;

  @override
  State<_ProjectTransactionSheet> createState() =>
      _ProjectTransactionSheetState();
}

class _ProjectTransactionSheetState extends State<_ProjectTransactionSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _quantity = TextEditingController();
  final _unit = TextEditingController();
  final _counterparty = TextEditingController();
  final _notes = TextEditingController();
  late String _type;
  late String _category;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final item = widget.transaction;
    _type = item?.type ?? ProjectTransactionType.expense;
    _title.text = item?.title ?? '';
    _category =
        item?.category ?? ProjectTransactionCategory.defaultForType(_type);
    _amount.text = item == null ? '' : item.amount.toStringAsFixed(0);
    _quantity.text = item?.quantity == null
        ? ''
        : item!.quantity!.toString().replaceFirst(RegExp(r'\.0$'), '');
    _unit.text = item?.unit ?? '';
    _counterparty.text = item?.counterparty ?? '';
    _notes.text = item?.notes ?? '';
    _date = item?.transactionDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _quantity.dispose();
    _unit.dispose();
    _counterparty.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final editing = widget.transaction != null;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ProjectSectionTitle(
                            icon: _type == ProjectTransactionType.income
                                ? Icons.add_card_outlined
                                : Icons.receipt_long_outlined,
                            title: editing
                                ? 'Редактировать операцию'
                                : 'Новая операция',
                            subtitle: 'Поступление или расход по объекту',
                          ),
                        ),
                        IconButton(
                          tooltip: 'Закрыть',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: ProjectTransactionType.expense,
                          label: Text('Расход'),
                          icon: Icon(Icons.north_east),
                        ),
                        ButtonSegment(
                          value: ProjectTransactionType.income,
                          label: Text('Поступление'),
                          icon: Icon(Icons.south_west),
                        ),
                      ],
                      selected: {_type},
                      onSelectionChanged: (values) {
                        final type = values.first;
                        setState(() {
                          _type = type;
                          if (!ProjectTransactionCategory.valuesForType(
                            type,
                          ).contains(_category)) {
                            _category =
                                ProjectTransactionCategory.defaultForType(type);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _title,
                      autofocus: !editing,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Что произошло',
                        hintText: 'Покупка кирпича',
                      ),
                    ),
                    const SizedBox(height: 10),
                    _TransactionCategoryField(
                      category: _category,
                      type: _type,
                      onChanged: (category) =>
                          setState(() => _category = category),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Сумма операции',
                        suffixText: '₽',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _quantity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Количество',
                              hintText: 'Необязательно',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _unit,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Единица',
                              hintText: 'шт., м², кг',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _counterparty,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Поставщик / плательщик',
                        hintText: 'Необязательно',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(formatDate(_date)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notes,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Комментарий',
                        hintText: 'Необязательно',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(editing ? 'Сохранить' : 'Добавить операцию'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final selected = await showSmetchikDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      title: 'Дата операции',
    );
    if (selected != null) setState(() => _date = selected);
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(
      ProjectTransactionDraft(
        type: _type,
        category: _category,
        title: title,
        amount: double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0,
        quantity: double.tryParse(_quantity.text.replaceAll(',', '.')),
        unit: _unit.text,
        transactionDate: _date,
        counterparty: _counterparty.text,
        notes: _notes.text,
      ),
    );
  }
}

class _ProjectMaterialSheet extends StatefulWidget {
  const _ProjectMaterialSheet({this.material});
  final ProjectMaterialModel? material;
  @override
  State<_ProjectMaterialSheet> createState() => _ProjectMaterialSheetState();
}

class _ProjectMaterialSheetState extends State<_ProjectMaterialSheet> {
  final _title = TextEditingController();
  final _quantity = TextEditingController();
  final _unit = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();
  @override
  void initState() {
    super.initState();
    final item = widget.material;
    _title.text = item?.title ?? '';
    _quantity.text = item == null
        ? '1'
        : item.plannedQuantity.toString().replaceFirst(RegExp(r'\.0$'), '');
    _unit.text = item?.unit ?? 'шт';
    _price.text = item == null
        ? ''
        : item.plannedUnitPrice.toString().replaceFirst(RegExp(r'\.0$'), '');
    _notes.text = item?.notes ?? '';
  }

  @override
  void dispose() {
    _title.dispose();
    _quantity.dispose();
    _unit.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CompactProjectSheet(
    title: widget.material == null ? 'Новый материал' : 'План материала',
    subtitle: 'Плановая закупка по объекту',
    icon: Icons.inventory_2_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _title,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Материал',
            hintText: 'Кирпич облицовочный',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Количество'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _unit,
                decoration: const InputDecoration(
                  labelText: 'Единица',
                  hintText: 'шт., м³',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Плановая цена за единицу',
            suffixText: '₽',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Комментарий',
            hintText: 'Необязательно',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_outlined),
          label: Text(
            widget.material == null ? 'Добавить материал' : 'Сохранить план',
          ),
        ),
      ],
    ),
  );
  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(
      ProjectMaterialDraft(
        title: title,
        plannedQuantity:
            double.tryParse(_quantity.text.replaceAll(',', '.')) ?? 1,
        unit: _unit.text,
        plannedUnitPrice:
            double.tryParse(_price.text.replaceAll(',', '.')) ?? 0,
        notes: _notes.text,
      ),
    );
  }
}

class _MaterialPurchase {
  const _MaterialPurchase({
    required this.amount,
    required this.quantity,
    required this.date,
    this.counterparty,
  });
  final double amount;
  final double quantity;
  final DateTime date;
  final String? counterparty;
}

class _MaterialPurchaseSheet extends StatefulWidget {
  const _MaterialPurchaseSheet({required this.material});
  final ProjectMaterialModel material;
  @override
  State<_MaterialPurchaseSheet> createState() => _MaterialPurchaseSheetState();
}

class _MaterialPurchaseSheetState extends State<_MaterialPurchaseSheet> {
  final _amount = TextEditingController();
  final _quantity = TextEditingController();
  final _counterparty = TextEditingController();
  late DateTime _date;
  @override
  void initState() {
    super.initState();
    final item = widget.material;
    _amount.text = (item.actualAmount ?? item.plannedAmount)
        .toString()
        .replaceFirst(RegExp(r'\.0$'), '');
    _quantity.text = (item.actualQuantity ?? item.plannedQuantity)
        .toString()
        .replaceFirst(RegExp(r'\.0$'), '');
    _date = item.purchasedAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    _quantity.dispose();
    _counterparty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CompactProjectSheet(
    title: 'Отметить покупку',
    subtitle: widget.material.title,
    icon: Icons.shopping_bag_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Фактическая сумма',
            suffixText: '₽',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _quantity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Купленное количество',
            suffixText: widget.material.unit,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _counterparty,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Поставщик',
            hintText: 'Необязательно',
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(formatDate(_date)),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check),
          label: const Text('Учесть покупку'),
        ),
      ],
    ),
  );
  Future<void> _pickDate() async {
    final date = await showSmetchikDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      title: 'Дата покупки',
    );
    if (date != null) setState(() => _date = date);
  }

  void _submit() => Navigator.of(context).pop(
    _MaterialPurchase(
      amount: double.tryParse(_amount.text.replaceAll(',', '.')) ?? 0,
      quantity: double.tryParse(_quantity.text.replaceAll(',', '.')) ?? 1,
      date: _date,
      counterparty: _counterparty.text.trim().isEmpty
          ? null
          : _counterparty.text.trim(),
    ),
  );
}

class _CompactProjectSheet extends StatelessWidget {
  const _CompactProjectSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _ProjectSectionTitle(
                          icon: icon,
                          title: title,
                          subtitle: subtitle,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Закрыть',
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ProjectExportSheet extends StatelessWidget {
  const _ProjectExportSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                        Icons.ios_share_outlined,
                        color: AppColors.orangeDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Экспорт отчёта',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Выберите формат для объекта',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final format in _ProjectExportFormat.values) ...[
                  _ProjectExportOption(
                    format: format,
                    onTap: () => Navigator.of(context).pop(format),
                  ),
                  if (format != _ProjectExportFormat.values.last)
                    const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectExportOption extends StatelessWidget {
  const _ProjectExportOption({required this.format, required this.onTap});

  final _ProjectExportFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.orangeLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(format.icon, color: AppColors.orangeDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      format.label,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      format.subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, color: AppColors.orangeDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionCategoryField extends StatelessWidget {
  const _TransactionCategoryField({
    required this.category,
    required this.type,
    required this.onChanged,
  });

  final String category;
  final String type;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final visual = _projectCategoryVisual(category);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final selected = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => _ProjectCategoryPickerSheet(
              type: type,
              currentCategory: category,
            ),
          );
          if (selected != null) onChanged(selected);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Категория',
            prefixIcon: Icon(visual.icon, color: AppColors.orangeDark),
            suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          child: Text(
            category,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _ProjectCategoryPickerSheet extends StatelessWidget {
  const _ProjectCategoryPickerSheet({
    required this.type,
    required this.currentCategory,
  });

  final String type;
  final String currentCategory;

  @override
  Widget build(BuildContext context) {
    final categories = ProjectTransactionCategory.valuesForType(type);
    final income =
        ProjectTransactionType.normalize(type) == ProjectTransactionType.income;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              income
                                  ? 'Категория поступления'
                                  : 'Категория расхода',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              income
                                  ? 'Для выручки по объекту'
                                  : 'Для учёта затрат на стройку',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (final category in categories) ...[
                    _ProjectCategoryOption(
                      category: category,
                      selected: category == currentCategory,
                      onTap: () => Navigator.of(context).pop(category),
                    ),
                    if (category != categories.last) const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectCategoryOption extends StatelessWidget {
  const _ProjectCategoryOption({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final String category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = _projectCategoryVisual(category);
    return Material(
      color: selected ? AppColors.orangeLight : AppColors.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : AppColors.orangeLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(visual.icon, color: AppColors.orangeDark),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppColors.orangeDark)
              else
                const Icon(Icons.chevron_right, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

_ProjectCategoryVisual _projectCategoryVisual(String category) {
  final icon = switch (category) {
    ProjectTransactionCategory.materials => Icons.inventory_2_outlined,
    ProjectTransactionCategory.labor => Icons.groups_2_outlined,
    ProjectTransactionCategory.contractors => Icons.engineering_outlined,
    ProjectTransactionCategory.equipment => Icons.construction_outlined,
    ProjectTransactionCategory.delivery => Icons.local_shipping_outlined,
    ProjectTransactionCategory.tools => Icons.handyman_outlined,
    ProjectTransactionCategory.sitePreparation => Icons.landscape_outlined,
    ProjectTransactionCategory.designAndDocuments =>
      Icons.architecture_outlined,
    ProjectTransactionCategory.utilitiesAndSecurity => Icons.bolt_outlined,
    ProjectTransactionCategory.taxesAndPermits => Icons.description_outlined,
    ProjectTransactionCategory.salesAndMarketing => Icons.campaign_outlined,
    ProjectTransactionCategory.advance => Icons.payments_outlined,
    ProjectTransactionCategory.stagePayment =>
      Icons.account_balance_wallet_outlined,
    ProjectTransactionCategory.finalPayment => Icons.task_alt_outlined,
    ProjectTransactionCategory.propertySale => Icons.home_work_outlined,
    ProjectTransactionCategory.refund => Icons.replay_outlined,
    _ => Icons.more_horiz,
  };
  return _ProjectCategoryVisual(icon: icon);
}

class _ProjectCategoryVisual {
  const _ProjectCategoryVisual({required this.icon});

  final IconData icon;
}
