import 'package:flutter_test/flutter_test.dart';
import 'package:smetchik/src/data/models.dart';

void main() {
  test(
    'provides construction categories and a fallback for project expenses',
    () {
      final categories = ProjectTransactionCategory.valuesForType(
        ProjectTransactionType.expense,
      );

      expect(categories, contains(ProjectTransactionCategory.materials));
      expect(categories, contains(ProjectTransactionCategory.labor));
      expect(categories, contains(ProjectTransactionCategory.equipment));
      expect(categories, contains(ProjectTransactionCategory.other));
      expect(
        ProjectTransactionCategory.defaultForType(
          ProjectTransactionType.expense,
        ),
        ProjectTransactionCategory.materials,
      );
    },
  );

  test('uses payment categories for project income', () {
    final categories = ProjectTransactionCategory.valuesForType(
      ProjectTransactionType.income,
    );

    expect(categories, contains(ProjectTransactionCategory.advance));
    expect(categories, contains(ProjectTransactionCategory.propertySale));
    expect(categories, contains(ProjectTransactionCategory.other));
    expect(
      ProjectTransactionCategory.defaultForType(ProjectTransactionType.income),
      ProjectTransactionCategory.advance,
    );
  });
}
