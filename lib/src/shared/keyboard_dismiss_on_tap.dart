import 'package:flutter/material.dart';

/// Removes text focus when the user taps an inactive area of the interface.
class KeyboardDismissOnTap extends StatelessWidget {
  const KeyboardDismissOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final focus = FocusManager.instance.primaryFocus;
        final renderObject = focus?.context?.findRenderObject();
        if (renderObject is RenderBox && renderObject.hasSize) {
          final origin = renderObject.localToGlobal(Offset.zero);
          if ((origin & renderObject.size).contains(event.position)) return;
        }
        focus?.unfocus();
      },
      child: child,
    );
  }
}
