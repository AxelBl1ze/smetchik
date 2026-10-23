import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'focus_aware_scroll_view.dart';

/// Ограничил форму видимой областью над клавиатурой.
class KeyboardFormSheet extends StatefulWidget {
  const KeyboardFormSheet({
    super.key,
    required this.header,
    required this.child,
    this.maxWidth = 560,
    this.closeEnabled = true,
  });
  final Widget header;
  final Widget child;
  final double maxWidth;
  final bool closeEnabled;

  @override
  State<KeyboardFormSheet> createState() => _KeyboardFormSheetState();
}

class _KeyboardFormSheetState extends State<KeyboardFormSheet> {
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.max(0.0, constraints.maxHeight - keyboard - 24);
        final content = KeyedSubtree(key: _contentKey, child: widget.child);
        final heading = Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(child: widget.header),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: widget.closeEnabled
                    ? () => Navigator.pop(context)
                    : null,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        );
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SafeArea(
            child: Align(
              heightFactor: 1,
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(8),
                constraints: BoxConstraints(
                  maxWidth: widget.maxWidth,
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
                  child: height < 280
                      ? FocusAwareScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              heading,
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  20,
                                ),
                                child: content,
                              ),
                            ],
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            heading,
                            Flexible(
                              child: FocusAwareScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  20,
                                ),
                                child: content,
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
