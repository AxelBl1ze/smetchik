import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smetchik/src/core/feature_tour_controller.dart';
import 'package:smetchik/src/shared/app_shell.dart';

void main() {
  testWidgets('moves the mobile navigation capsule between tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          featureTourControllerProvider.overrideWith(
            (ref) => FeatureTourController(),
          ),
        ],
        child: const MaterialApp(
          home: AppShell(selectedIndex: 0, child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final capsule = find.byKey(const Key('floating-nav-capsule'));
    final start = tester.getTopLeft(capsule).dx;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          featureTourControllerProvider.overrideWith(
            (ref) => FeatureTourController(),
          ),
        ],
        child: const MaterialApp(
          home: AppShell(selectedIndex: 4, child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    final middle = tester.getTopLeft(capsule).dx;

    await tester.pumpAndSettle();
    final end = tester.getTopLeft(capsule).dx;

    expect(middle, greaterThan(start));
    expect(middle, lessThan(end));
  });
}
