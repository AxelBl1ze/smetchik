import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/project_payment_summary.dart';
import '../../shared/ui.dart';

class ProjectPaymentAnalytics extends StatefulWidget {
  const ProjectPaymentAnalytics({super.key, required this.transactions});
  final List<ProjectTransactionModel> transactions;

  @override
  State<ProjectPaymentAnalytics> createState() =>
      _ProjectPaymentAnalyticsState();
}

class _ProjectPaymentAnalyticsState extends State<ProjectPaymentAnalytics> {
  bool _byPayer = false;
  bool _showAll = false;
  static const _colors = [
    AppColors.orange,
    AppColors.graphite2,
    AppColors.success,
    AppColors.info,
    AppColors.textHint,
    AppColors.danger,
  ];

  @override
  Widget build(BuildContext context) {
    final expenses = widget.transactions
        .where((item) => item.type == ProjectTransactionType.expense)
        .toList();
    final categories = <String, List<ProjectTransactionModel>>{};
    for (final item in expenses) {
      categories.putIfAbsent(item.category, () => []).add(item);
    }
    final groups = _byPayer
        ? groupProjectPayments(expenses)
        : (categories.entries
              .map(
                (entry) => ProjectPaymentGroup(
                  name: entry.key,
                  transactions: entry.value,
                ),
              )
              .toList()
            ..sort((a, b) => b.amount.compareTo(a.amount)));
    final total = groups.fold<double>(0, (sum, group) => sum + group.amount);
    final visible = _showAll ? groups : groups.take(5).toList();
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < visible.length; index++)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showPayments(context, visible[index], total),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 4,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _colors[index % _colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            visible[index].label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                formatProjectPayment(visible[index].amount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${visible[index].transactions.length} оп. · ${_percent(visible[index].shareOf(total))}',
                                style: const TextStyle(
                                  color: AppColors.textHint,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.textHint,
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (groups.length > 5)
          TextButton.icon(
            onPressed: () => setState(() => _showAll = !_showAll),
            icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more),
            label: Text(
              _showAll ? 'Свернуть' : 'Показать все (${groups.length})',
            ),
          ),
      ],
    );

    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Структура расходов',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                for (final option in [
                  (false, 'Категории'),
                  (true, 'Кто оплатил'),
                ])
                  Expanded(
                    child: Material(
                      color: _byPayer == option.$1
                          ? AppColors.graphite
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() {
                          _byPayer = option.$1;
                          _showAll = false;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 12,
                          ),
                          child: Text(
                            option.$2,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _byPayer == option.$1
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Добавьте расходы, чтобы увидеть разбивку.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final chart = Semantics(
                  label: 'Всего расходов ${formatProjectPayment(total)}',
                  child: SizedBox(
                    width: 196,
                    height: 196,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _PaymentDonutPainter(
                              amounts: groups
                                  .map((group) => group.amount)
                                  .toList(),
                              colors: _colors,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 132,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Потрачено',
                                style: TextStyle(
                                  color: AppColors.textHint,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 5),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  formatProjectPayment(total),
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                if (constraints.maxWidth >= 560) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      chart,
                      const SizedBox(width: 24),
                      Expanded(child: legend),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: chart),
                    const SizedBox(height: 12),
                    legend,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showPayments(
    BuildContext context,
    ProjectPaymentGroup group,
    double total,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.label,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  '${formatProjectPayment(group.amount)} · ${_percent(group.shareOf(total))} расходов',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: group.transactions.length,
                    separatorBuilder: (_, _) => const Divider(height: 24),
                    itemBuilder: (context, index) {
                      final item = group.transactions[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatDate(item.transactionDate),
                            style: const TextStyle(
                              color: AppColors.textHint,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  formatProjectPayment(item.amount),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.category,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (!_byPayer)
                            Text(
                              'Оплатил: ${item.effectivePayerName ?? 'не указан'}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          if (item.counterparty?.trim().isNotEmpty == true)
                            Text(
                              'Получатель: ${item.counterparty}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          if (item.notes?.trim().isNotEmpty == true) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.notes!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
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

String _percent(double fraction) =>
    '${NumberFormat('0.#', 'ru_RU').format(fraction * 100)}%';

class _PaymentDonutPainter extends CustomPainter {
  const _PaymentDonutPainter({required this.amounts, required this.colors});
  final List<double> amounts;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawOval(rect, paint..color = AppColors.background);
    final total = amounts.fold<double>(0, (sum, amount) => sum + amount);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < amounts.length; i++) {
      final sweep = amounts[i] / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        paint..color = colors[i % colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PaymentDonutPainter oldDelegate) =>
      oldDelegate.amounts.length != amounts.length ||
      List.generate(
        amounts.length,
        (i) => oldDelegate.amounts[i] != amounts[i],
      ).any((changed) => changed);
}
