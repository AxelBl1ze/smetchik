import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smetchik/src/core/app_theme.dart';
import 'package:smetchik/src/shared/ui.dart';

void main() {
  const options = [
    FilterPickerOption(
      value: 'all',
      label: 'Все сметы',
      icon: Icons.filter_list_rounded,
      color: AppColors.textSecondary,
      background: AppColors.background,
    ),
    FilterPickerOption(
      value: 'in_progress',
      label: 'В работе',
      icon: Icons.handyman_outlined,
      color: AppColors.success,
      background: AppColors.successBg,
    ),
  ];

  testWidgets('opens a styled filter list and returns the selected value', (
    tester,
  ) async {
    var selected = 'all';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: FilterPickerField(
              title: 'Статус сметы',
              options: options,
              selectedValue: selected,
              onChanged: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Все сметы'));
    await tester.pumpAndSettle();
    expect(find.text('Статус сметы'), findsNWidgets(2));
    expect(find.text('В работе'), findsOneWidget);

    await tester.tap(find.text('В работе'));
    await tester.pumpAndSettle();
    expect(selected, 'in_progress');
  });
}
