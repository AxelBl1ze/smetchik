import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smetchik/src/shared/keyboard_dismiss_on_tap.dart';

void main() {
  testWidgets('dismisses text focus when tapping free space', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KeyboardDismissOnTap(
            child: Column(
              children: [
                TextField(focusNode: focusNode),
                const Expanded(child: SizedBox.expand()),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tapAt(const Offset(250, 500));
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
  });
}
