import 'package:flutter_test/flutter_test.dart';
import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/data/project_payment_summary.dart';

ProjectTransactionModel payment(
  String id,
  double amount, {
  String? payer,
  String? supplier,
  String type = ProjectTransactionType.expense,
  String projectId = 'house-1',
}) => ProjectTransactionModel(
  id: id,
  projectId: projectId,
  type: type,
  category: ProjectTransactionCategory.materials,
  title: 'Кирпич',
  amount: amount,
  payerName: payer,
  counterparty: supplier,
  transactionDate: DateTime(2026, 10, 22),
);

void main() {
  test('payment formatting preserves kopecks without floating point noise', () {
    expect(formatProjectPayment(125000.5), contains('125\u00a0000,50'));
    expect(formatProjectPayment(125000.000000001), isNot(contains(',00')));
  });
  test(
    'groups expenses by normalized payer, including unspecified expenses',
    () {
      final groups = groupProjectPayments([
        payment('1', 100, payer: '  Джамал '),
        payment('2', 200, payer: 'джамал'),
        payment('3', 50, payer: 'Илья'),
        payment('4', 150, supplier: 'Строймаркет'),
        payment(
          '5',
          1000,
          payer: 'Заказчик',
          type: ProjectTransactionType.income,
        ),
      ]);
      expect(groups.map((g) => g.label), ['Джамал', 'Не указан', 'Илья']);
      expect(groups.first.amount, 300);
      expect(groups.first.shareOf(500), .6);
      expect(groups[1].amount, 150);
      expect(groups.map((g) => g.amount).reduce((a, b) => a + b), 500);
    },
  );

  test('does not confuse a supplier with an expense payer', () {
    expect(payment('1', 100, supplier: 'Магазин').effectivePayerName, isNull);
    expect(
      payment(
        '2',
        100,
        supplier: 'Джамал',
        type: ProjectTransactionType.income,
      ).effectivePayerName,
      'Джамал',
    );
    expect(
      payment('3', 100, payer: 'Алексей   Иванов').effectivePayerName,
      'Алексей Иванов',
    );
    expect(
      ProjectTransactionModel.fromMap({
        'id': '4',
        'project_id': 'house-1',
        'payer_name': 'Илья',
        'transaction_type': 'expense',
        'amount': 50,
        'transaction_date': '2026-10-22',
      }).payerName,
      'Илья',
    );
  });

  test('zero amounts have a zero share rather than NaN', () {
    final groups = groupProjectPayments([payment('1', 0, payer: 'Джамал')]);
    expect(groups.single.shareOf(0), 0);
    expect(groupProjectPayments([]), isEmpty);
  });

  test(
    'payer choices come only from the current project, keeping saved names',
    () {
      final project = ProjectModel(
        id: 'house-1',
        title: 'Дом',
        plannedRevenue: 0,
        startDate: DateTime(2026),
        status: ProjectStatus.active,
        createdAt: DateTime(2026),
      );
      final detail = ProjectDetail(
        project: project,
        payerNames: const ['Джамал', 'Сергей'],
        transactions: [
          payment('1', 50, payer: 'джамал'),
          payment('2', 30, payer: 'Илья'),
        ],
      );
      expect(detail.availablePayerNames, ['Джамал', 'Сергей', 'Илья']);
      expect(
        ProjectDetail(
          project: project,
          transactions: const [],
        ).availablePayerNames,
        isEmpty,
      );
    },
  );
}
