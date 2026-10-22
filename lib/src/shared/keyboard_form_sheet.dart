import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Ограничил форму видимой областью и сохраняю поле в зоне прокрутки.
class KeyboardFormSheet extends StatefulWidget {
  const KeyboardFormSheet({
    super.key,
    required this.header,
    required this.child,
  });
  final Widget header;
  final Widget child;

  @override
  State<KeyboardFormSheet> createState() => _KeyboardFormSheetState();
}

class _KeyboardFormSheetState extends State<KeyboardFormSheet>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_revealField);
  }

  void _revealField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = FocusManager.instance.primaryFocus?.context;
      if (target == null || !target.mounted) return;
      final scrollable = Scrollable.maybeOf(target);
      if (scrollable?.widget.controller != _scroll) return;
      Scrollable.ensureVisible(target, alignment: .25);
    });
  }

  @override
  void didChangeMetrics() => _revealField();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_revealField);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.max(0.0, constraints.maxHeight - keyboard - 24);
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SafeArea(
            child: Align(
              heightFactor: 1,
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(8),
                constraints: BoxConstraints(
                  maxWidth: 560,
                  maxHeight: math.min(760, height),
                ),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border),
                ),
                child: Material(
                  color: AppColors.card,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        child: Row(
                          children: [
                            Expanded(child: widget.header),
                            IconButton(
                              tooltip: 'Закрыть',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          controller: _scroll,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          child: widget.child,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
