import 'package:intl/intl.dart';

import 'models.dart';

String formatProjectPayment(num amount) {
  final rounded = (amount * 100).round() / 100;
  return NumberFormat.currency(
    locale: 'ru_RU',
    symbol: '₽',
    decimalDigits: rounded == rounded.roundToDouble() ? 0 : 2,
  ).format(rounded);
}

class ProjectPaymentGroup {
  const ProjectPaymentGroup({required this.name, required this.transactions});

  final String? name;
  final List<ProjectTransactionModel> transactions;

  String get label => name ?? 'Не указан';
  double get amount =>
      transactions.fold<double>(0, (sum, item) => sum + item.amount);
  double shareOf(double total) => total <= 0 ? 0 : amount / total;
}

/// Одинаковая группировка для экрана объекта, Excel и PDF.
List<ProjectPaymentGroup> groupProjectPayments(
  List<ProjectTransactionModel> transactions, {
  String type = ProjectTransactionType.expense,
}) {
  final groups = <String?, List<ProjectTransactionModel>>{};
  final names = <String?, String?>{};
  for (final item in transactions.where((item) => item.type == type)) {
    final name = item.effectivePayerName;
    final key = name?.toLowerCase();
    names.putIfAbsent(key, () => name);
    groups.putIfAbsent(key, () => []).add(item);
  }
  return groups.entries.map((entry) {
    final items = [...entry.value]
      ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
    return ProjectPaymentGroup(name: names[entry.key], transactions: items);
  }).toList()..sort((a, b) {
    final byAmount = b.amount.compareTo(a.amount);
    return byAmount != 0 ? byAmount : a.label.compareTo(b.label);
  });
}
