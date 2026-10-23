import 'package:flutter/material.dart';

/// Сохранил активное поле в видимой области после появления клавиатуры.
class FocusAwareScrollView extends StatelessWidget {
  const FocusAwareScrollView({
    super.key,
    required this.child,
    this.padding,
    this.physics,
    this.controller,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => FocusAwareViewport(
    child: SingleChildScrollView(
      controller: controller,
      padding: padding,
      physics: physics,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: child,
    ),
  );
}

class FocusAwareViewport extends StatefulWidget {
  const FocusAwareViewport({super.key, required this.child});
  final Widget child;

  @override
  State<FocusAwareViewport> createState() => _FocusAwareViewportState();
}

class _FocusAwareViewportState extends State<FocusAwareViewport>
    with WidgetsBindingObserver {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_reveal);
  }

  void _reveal() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final target = FocusManager.instance.primaryFocus?.context;
      if (target == null || !target.mounted) return;
      // Вложенная форма сама обработала фокус; внешний экран не сдвинул.
      if (target.findAncestorStateOfType<_FocusAwareViewportState>() != this) {
        return;
      }
      final scrollable = Scrollable.maybeOf(target, axis: Axis.vertical);
      final field = target.findRenderObject();
      final viewport = scrollable?.context.findRenderObject();
      if (field == null || !field.attached || scrollable == null) return;
      if (field is RenderBox &&
          viewport is RenderBox &&
          field.hasSize &&
          viewport.hasSize) {
        final top = field.localToGlobal(Offset.zero, ancestor: viewport).dy;
        final bottom = top + field.size.height;
        if (top >= 24 && bottom <= viewport.size.height - 24) return;
      }
      Scrollable.ensureVisible(target, alignment: .35);
    });
  }

  @override
  void didChangeMetrics() => _reveal();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.viewInsetsOf(context);
    _reveal();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_reveal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
