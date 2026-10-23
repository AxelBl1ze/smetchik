import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_error.dart';
import '../../core/app_theme.dart';
import '../../data/room_calculator.dart';
import '../../shared/form_sheet.dart';
import '../../shared/keyboard_form_sheet.dart';
import '../../shared/ui.dart';
import 'room_finish_sheet.dart';
import 'room_plan_view.dart';

enum _PlanTool { wall, door, window }

class RoomEditorScreen extends StatefulWidget {
  const RoomEditorScreen({
    super.key,
    required this.initial,
    required this.onSave,
  });
  final ProjectRoom initial;
  final Future<ProjectRoom> Function(ProjectRoom) onSave;
  @override
  State<RoomEditorScreen> createState() => _RoomEditorScreenState();
}

class _RoomEditorScreenState extends State<RoomEditorScreen> {
  late ProjectRoom _room;
  late final TextEditingController _name;
  late bool _confirmed;
  bool _busy = false, _canLeave = false;
  PlanPoint? _pending;
  _PlanTool _tool = _PlanTool.wall;
  String? _error;
  @override
  void initState() {
    super.initState();
    _room = widget.initial;
    _name = TextEditingController(text: _room.name);
    _confirmed = _room.revision > 0;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ProjectRoom get _draft => _room.copyWith(name: _name.text.trim());
  bool get _dirty =>
      jsonEncode(_draft.toMap()) != jsonEncode(widget.initial.toMap());
  void _change(ProjectRoom room) => setState(() {
    _room = room;
    _error = null;
  });
  void _message(String message) {
    setState(() => _error = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final geometry = RoomGeometry(_room);
    String? geometryError;
    try {
      RoomGeometry(
        _room.copyWith(
          name: _name.text.trim().isEmpty ? 'Помещение' : _name.text,
        ),
      ).validate();
    } on FormatException catch (e) {
      geometryError = e.message;
    }
    return PopScope(
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Назад к помещениям',
            onPressed: _busy ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            widget.initial.revision == 0
                ? 'Новое помещение'
                : widget.initial.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: ResponsiveListView(
            maxWidth: 760,
            children: [
              TextField(
                controller: _name,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Название помещения',
                  hintText: 'Кухня, коридор, гараж…',
                  counterText: '',
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 20),
              SectionHeader(
                title: 'План помещения',
                action: _confirmed
                    ? TextButton.icon(
                        onPressed: () => setState(() => _confirmed = false),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Изменить'),
                      )
                    : PopupMenuButton<String>(
                        tooltip: 'Форма помещения',
                        color: AppColors.card,
                        surfaceTintColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        icon: const Icon(Icons.grid_view_outlined),
                        onSelected: _preset,
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rectangle',
                            child: Text('Прямоугольник'),
                          ),
                          PopupMenuItem(value: 'l', child: Text('Г-образное')),
                          PopupMenuItem(
                            value: 'diagonal',
                            child: Text('Скошенный угол'),
                          ),
                          PopupMenuItem(
                            value: 'empty',
                            child: Text('Нарисовать заново'),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              if (!_confirmed) ...[
                RoomChoice(
                  values: _PlanTool.values,
                  value: _tool,
                  label: (v) => switch (v) {
                    _PlanTool.wall => 'Стена',
                    _PlanTool.door => 'Дверь',
                    _PlanTool.window => 'Окно',
                  },
                  onChanged: (v) => setState(() {
                    _tool = v;
                    _pending = null;
                  }),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: RoomPlanView(
                      room: _room,
                      editing: !_confirmed,
                      pending: _pending,
                      onTap: _confirmed ? _tapCorner : _tapPlan,
                      onDimension: _dimension,
                    ),
                  ),
                ),
              ),
              if (!_confirmed) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _pending == null
                            ? 'Контур и проёмы'
                            : 'Конец новой стены',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (_pending != null)
                      IconButton(
                        tooltip: 'Отменить стену',
                        onPressed: () => setState(() => _pending = null),
                        icon: const Icon(Icons.undo),
                      ),
                    const Tooltip(
                      message:
                          'Стена: выберите две точки сетки. Нажмите на середину стены, чтобы удалить её. '
                          'Для двери или окна выберите инструмент и нажмите на стену.',
                      triggerMode: TooltipTriggerMode.tap,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.help_outline, size: 20),
                      ),
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    if (geometryError != null) {
                      _message(geometryError);
                      return;
                    }
                    setState(() {
                      _confirmed = true;
                      _pending = null;
                      _error = null;
                    });
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Подтвердить план'),
                ),
              ],
              const SizedBox(height: 12),
              if (geometryError == null)
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    _Measure(
                      'Пол и потолок',
                      '${roomNumber(geometry.floorArea)} м²',
                    ),
                    _Measure(
                      'Стены без проёмов',
                      '${roomNumber(geometry.wallArea())} м²',
                    ),
                    _Measure('Периметр', '${roomNumber(geometry.perimeter)} м'),
                  ],
                )
              else
                Text(
                  geometryError,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              if (_confirmed &&
                  geometryError == null &&
                  _interiorCorners.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: const Text(
                    'Размеры выступов',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    for (final p in _interiorCorners)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Угол ${geometry.outline.indexWhere((v) => v.key == p.key) + 1}',
                        ),
                        subtitle: Text(
                          '${roomNumber(geometry.metric(p).x)} × ${roomNumber(geometry.metric(p).y)} м',
                        ),
                        trailing: const Icon(Icons.edit_outlined, size: 20),
                        onTap: () => _corner(p),
                      ),
                  ],
                ),
              const SizedBox(height: 24),
              SectionHeader(
                title: 'Двери и окна',
                action: IconButton(
                  tooltip: 'Добавить проём',
                  onPressed: geometryError == null ? () => _opening() : null,
                  icon: const Icon(Icons.add),
                ),
              ),
              if (_room.openings.isEmpty)
                const Text(
                  'Проёмов нет',
                  style: TextStyle(color: AppColors.textHint),
                ),
              for (final o in _room.openings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    o.kind == OpeningKind.door
                        ? Icons.door_front_door_outlined
                        : Icons.window_outlined,
                    color: o.kind == OpeningKind.door
                        ? AppColors.orangeDark
                        : AppColors.info,
                  ),
                  title: Text(
                    '${o.kind == OpeningKind.door ? 'Дверь' : 'Окно'} · стена ${_room.walls.indexWhere((w) => w.key == o.wallKey) + 1}',
                  ),
                  subtitle: Text(
                    '${roomNumber(o.width)} × ${roomNumber(o.height)} м',
                  ),
                  onTap: () => _opening(initial: o),
                  trailing: IconButton(
                    tooltip: 'Удалить проём',
                    onPressed: () => _deleteOpening(o),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ),
              const SizedBox(height: 24),
              SectionHeader(
                title: 'Отделка',
                action: IconButton(
                  tooltip: 'Рассчитать материал',
                  onPressed: _confirmed && geometryError == null
                      ? () => _finish()
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ),
              if (_room.finishes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: OutlinedButton.icon(
                    onPressed: _confirmed && geometryError == null
                        ? () => _finish()
                        : null,
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('Рассчитать материал'),
                  ),
                ),
              for (final f in _room.finishes) ...[
                _FinishRow(
                  room: _draft,
                  finish: f,
                  onEdit: () => _finish(f),
                  onDelete: () => _deleteFinish(f),
                ),
                const SizedBox(height: 10),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 728),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_busy ? 'Сохраняем…' : 'Сохранить помещение'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_dirty &&
        !await showConfirmSheet(
          context: context,
          title: 'Выйти без сохранения?',
          message: 'Изменения этого помещения ещё не сохранены.',
          confirmLabel: 'Выйти',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _canLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_confirmed) {
      _message('Сначала подтвердите план помещения.');
      return;
    }
    try {
      RoomGeometry(_draft).validate();
      for (final f in _room.finishes) {
        RoomCalculator.calculate(_draft, f);
      }
      setState(() {
        _busy = true;
        _error = null;
      });
      await widget.onSave(_draft);
      if (!mounted) return;
      setState(() => _canLeave = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      if (mounted) {
        final info = describeAppError(e);
        _message(
          e is FormatException
              ? e.message
              : info.title == 'Нет подключения к интернету'
              ? 'Для сохранения помещения нужен интернет. Изменения остались на экране; '
                    'не закрывайте его до успешного сохранения.'
              : appErrorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preset(String shape) async {
    if ((_room.openings.isNotEmpty || _room.finishes.isNotEmpty) &&
        !await showConfirmSheet(
          context: context,
          title: 'Заменить план?',
          message:
              'Проёмы и расчёты отделки этого помещения будут удалены. Размеры и название останутся.',
          confirmLabel: 'Заменить',
        )) {
      return;
    }
    if (!mounted) return;
    _pending = null;
    _change(
      _room.copyWith(
        walls: shape == 'empty' ? [] : ProjectRoom.shape(shape),
        openings: [],
        finishes: [],
      ),
    );
  }

  List<PlanPoint> get _interiorCorners {
    final g = RoomGeometry(_room);
    return g.outline.where((p) {
      final m = g.metric(p);
      return (m.x > 1e-7 && m.x < _room.width - 1e-7) ||
          (m.y > 1e-7 && m.y < _room.depth - 1e-7);
    }).toList();
  }

  void _tapCorner(Offset position) {
    final matching = _interiorCorners.where(
      (p) => (Offset(p.x, p.y) - position).distance < .8,
    );
    if (matching.isNotEmpty) _corner(matching.first);
  }

  Future<void> _corner(PlanPoint point) async {
    final result = await showModalBottomSheet<ProjectRoom>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CornerSheet(
        room: _room.copyWith(
          name: _name.text.isEmpty ? 'Помещение' : _name.text,
        ),
        point: point,
      ),
    );
    if (mounted && result != null) _change(result);
  }

  void _tapPlan(Offset position) {
    final endpoints = _room.walls
        .expand((w) => [w.a, w.b])
        .where((p) => (Offset(p.x, p.y) - position).distance < .45);
    final point =
        endpoints.firstOrNull ??
        PlanPoint(position.dx.roundToDouble(), position.dy.roundToDouble());
    final candidates = _room.walls.map((w) {
      final a = Offset(w.a.x, w.a.y), d = Offset(w.b.x - w.a.x, w.b.y - w.a.y);
      final t = d.distanceSquared == 0
          ? 0.0
          : ((position - a).dx * d.dx + (position - a).dy * d.dy) /
                d.distanceSquared;
      final dist = (position - (a + d * t.clamp(0, 1))).distance;
      return (wall: w, distance: dist, t: t.clamp(0.0, 1.0));
    }).toList()..sort((a, b) => a.distance.compareTo(b.distance));
    final hit = candidates.isNotEmpty && candidates.first.distance < .65
        ? candidates.first
        : null;
    if (_tool != _PlanTool.wall) {
      if (hit == null) {
        _message('Выберите стену для проёма.');
        return;
      }
      try {
        RoomGeometry(_room.copyWith(name: 'Помещение')).validate();
      } on FormatException catch (e) {
        _message(e.message);
        return;
      }
      final length = RoomGeometry(_room).wallLength(hit.wall);
      final matching = _room.openings.where(
        (o) =>
            o.wallKey == hit.wall.key &&
            hit.t * length >= o.offset &&
            hit.t * length <= o.offset + o.width,
      );
      _opening(
        wall: hit.wall,
        position: hit.t,
        initial: matching.firstOrNull,
        kind: _tool == _PlanTool.door ? OpeningKind.door : OpeningKind.window,
      );
      return;
    }
    if (_pending == null) {
      if (hit != null && hit.t > .08 && hit.t < .92) {
        _removeWall(hit.wall);
        return;
      }
      setState(() {
        _pending = point;
        _error = null;
      });
      return;
    }
    final start = _pending!;
    setState(() => _pending = null);
    if (start.key == point.key) return;
    final wall = RoomWall(start, point);
    final existing = _room.walls.where((w) => w.key == wall.key).firstOrNull;
    if (existing != null) {
      _removeWall(existing);
      return;
    }
    if (_room.walls.length >= 64) {
      _message('В одном помещении может быть до 64 стен.');
      return;
    }
    _change(_room.copyWith(walls: [..._room.walls, wall]));
  }

  void _removeWall(RoomWall wall) {
    if (_room.openings.any((o) => o.wallKey == wall.key) ||
        _room.finishes.any((f) => f.wallKeys.contains(wall.key))) {
      _message('Сначала удалите проёмы и расчёты, привязанные к этой стене.');
      return;
    }
    _change(
      _room.copyWith(
        walls: _room.walls.where((w) => w.key != wall.key).toList(),
      ),
    );
  }

  Future<void> _dimension(String key) async {
    final initial = switch (key) {
      'width' => _room.width,
      'depth' => _room.depth,
      _ => _room.height,
    };
    final label = switch (key) {
      'width' => 'Ширина',
      'depth' => 'Длина',
      _ => 'Высота',
    };
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DimensionSheet(label: label, initial: initial),
    );
    if (!mounted || result == null) return;
    final next = switch (key) {
      'width' => _room.copyWith(width: result),
      'depth' => _room.copyWith(depth: result),
      _ => _room.copyWith(height: result),
    };
    try {
      RoomGeometry(
        next.copyWith(name: _name.text.isEmpty ? 'Помещение' : _name.text),
      ).validate();
      for (final f in next.finishes) {
        RoomCalculator.calculate(next.copyWith(name: 'Помещение'), f);
      }
      _change(next);
    } on FormatException catch (e) {
      _message(e.message);
    }
  }

  Future<void> _opening({
    RoomWall? wall,
    RoomOpening? initial,
    OpeningKind kind = OpeningKind.door,
    double position = .5,
  }) async {
    if (_room.openings.length >= 64 && initial == null) {
      _message('В помещении уже 64 проёма.');
      return;
    }
    final opening = await showModalBottomSheet<RoomOpening>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OpeningSheet(
        room: _draft.copyWith(
          name: _name.text.isEmpty ? 'Помещение' : _name.text,
        ),
        wall:
            wall ??
            _room.walls.firstWhere(
              (w) => w.key == initial?.wallKey,
              orElse: () => _room.walls.first,
            ),
        kind: kind,
        position: position,
        initial: initial,
      ),
    );
    if (!mounted || opening == null) return;
    _change(
      _room.copyWith(
        openings: [..._room.openings.where((o) => o.id != opening.id), opening],
      ),
    );
  }

  Future<void> _deleteOpening(RoomOpening o) async {
    if (await showConfirmSheet(
      context: context,
      title: 'Удалить проём?',
      message: 'Площадь отделки будет пересчитана.',
      confirmLabel: 'Удалить',
    )) {
      if (mounted) {
        _change(
          _room.copyWith(
            openings: _room.openings.where((v) => v.id != o.id).toList(),
          ),
        );
      }
    }
  }

  Future<void> _finish([RoomFinish? initial]) async {
    if (_room.finishes.length >= 60 && initial == null) {
      _message('В помещении уже 60 расчётов.');
      return;
    }
    final f = await showRoomFinishSheet(
      context,
      _draft.copyWith(name: _name.text.isEmpty ? 'Помещение' : _name.text),
      initial: initial,
    );
    if (!mounted || f == null) return;
    _change(
      _room.copyWith(
        finishes: [..._room.finishes.where((v) => v.id != f.id), f],
      ),
    );
  }

  Future<void> _deleteFinish(RoomFinish f) async {
    if (await showConfirmSheet(
      context: context,
      title: 'Удалить расчёт?',
      message: f.name,
    )) {
      if (mounted) {
        _change(
          _room.copyWith(
            finishes: _room.finishes.where((v) => v.id != f.id).toList(),
          ),
        );
      }
    }
  }
}

class _CornerSheet extends StatefulWidget {
  const _CornerSheet({required this.room, required this.point});
  final ProjectRoom room;
  final PlanPoint point;
  @override
  State<_CornerSheet> createState() => _CornerSheetState();
}

class _CornerSheetState extends State<_CornerSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _x, _y;
  late final bool _editX, _editY;
  String? _error;
  @override
  void initState() {
    super.initState();
    final p = RoomGeometry(widget.room).metric(widget.point);
    _x = TextEditingController(text: roomNumber(p.x));
    _y = TextEditingController(text: roomNumber(p.y));
    _editX = p.x > 1e-7 && p.x < widget.room.width - 1e-7;
    _editY = p.y > 1e-7 && p.y < widget.room.depth - 1e-7;
  }

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyboardFormSheet(
    header: Text(
      'Положение угла',
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoomNumberField(
            controller: _x,
            label: 'От левой границы',
            unit: 'м',
            zeroAllowed: true,
            max: widget.room.width,
            readOnly: !_editX,
          ),
          const SizedBox(height: 16),
          RoomNumberField(
            controller: _y,
            label: 'От верхней границы',
            unit: 'м',
            zeroAllowed: true,
            max: widget.room.depth,
            readOnly: !_editY,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              try {
                final result = RoomGeometry(widget.room).positionCorner(
                  widget.point,
                  RoomNumberField.parse(_x.text)!,
                  RoomNumberField.parse(_y.text)!,
                );
                Navigator.pop(context, result);
              } on FormatException catch (e) {
                setState(() => _error = e.message);
              }
            },
            child: const Text('Применить'),
          ),
        ],
      ),
    ),
  );
}

class _DimensionSheet extends StatefulWidget {
  const _DimensionSheet({required this.label, required this.initial});
  final String label;
  final double initial;
  @override
  State<_DimensionSheet> createState() => _DimensionSheetState();
}

class _DimensionSheetState extends State<_DimensionSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: roomNumber(widget.initial));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyboardFormSheet(
    header: Text(
      '${widget.label} помещения',
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoomNumberField(
            controller: _controller,
            label: widget.label,
            unit: 'м',
            max: 200,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, RoomNumberField.parse(_controller.text));
              }
            },
            child: const Text('Применить'),
          ),
        ],
      ),
    ),
  );
}

class _Measure extends StatelessWidget {
  const _Measure(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}

class _FinishRow extends StatelessWidget {
  const _FinishRow({
    required this.room,
    required this.finish,
    required this.onEdit,
    required this.onDelete,
  });
  final ProjectRoom room;
  final RoomFinish finish;
  final VoidCallback onEdit, onDelete;
  @override
  Widget build(BuildContext context) {
    FinishRequirement? result;
    try {
      result = RoomCalculator.calculate(
        room.copyWith(name: room.name.isEmpty ? 'Помещение' : room.name),
        finish,
      );
    } on FormatException {
      /* Invalid dimensions are reported by the save action. */
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onEdit,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    finish.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${finish.surface.label} · ${result == null ? 'проверьте параметры' : '${roomNumber(result.area)} м²'}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (result != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${result.packages} ${finish.kind.unit} · запас ${roomNumber(finish.waste)}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.orangeDark,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Изменить расчёт',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Удалить расчёт',
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }
}

class _OpeningSheet extends StatefulWidget {
  const _OpeningSheet({
    required this.room,
    required this.wall,
    required this.kind,
    required this.position,
    this.initial,
  });
  final ProjectRoom room;
  final RoomWall wall;
  final OpeningKind kind;
  final double position;
  final RoomOpening? initial;
  @override
  State<_OpeningSheet> createState() => _OpeningSheetState();
}

class _OpeningSheetState extends State<_OpeningSheet> {
  final _form = GlobalKey<FormState>();
  late OpeningKind _kind;
  late RoomWall _wall;
  late final TextEditingController _width, _height, _sill, _offset;
  String? _error;
  @override
  void initState() {
    super.initState();
    _wall = widget.wall;
    _kind = widget.initial?.kind ?? widget.kind;
    final length = RoomGeometry(widget.room).wallLength(_wall);
    final width = math.min(_kind == OpeningKind.door ? .9 : 1.4, length);
    _width = TextEditingController(
      text: roomNumber(widget.initial?.width ?? width),
    );
    _height = TextEditingController(
      text: roomNumber(
        widget.initial?.height ??
            math.min(_kind == OpeningKind.door ? 2.1 : 1.3, widget.room.height),
      ),
    );
    _sill = TextEditingController(
      text: roomNumber(
        widget.initial?.sill ??
            (_kind == OpeningKind.door
                ? 0
                : math.min(.8, math.max(0, widget.room.height - 1.3))),
      ),
    );
    _offset = TextEditingController(
      text: roomNumber(
        widget.initial?.offset ??
            (widget.position * length - width / 2).clamp(0, length - width),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [_width, _height, _sill, _offset]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyboardFormSheet(
    header: Text(
      widget.initial == null ? 'Новый проём' : 'Изменить проём',
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoomChoice(
            values: OpeningKind.values,
            value: _kind,
            label: (v) => v == OpeningKind.door ? 'Дверь' : 'Окно',
            onChanged: (v) => setState(() {
              _kind = v;
              if (v == OpeningKind.door) _sill.text = '0';
            }),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _wall.key,
            isExpanded: true,
            dropdownColor: AppColors.card,
            decoration: const InputDecoration(labelText: 'Стена'),
            items: [
              for (var i = 0; i < widget.room.walls.length; i++)
                DropdownMenuItem(
                  value: widget.room.walls[i].key,
                  child: Text(
                    'Стена ${i + 1} · ${roomNumber(RoomGeometry(widget.room).wallLength(widget.room.walls[i]))} м',
                  ),
                ),
            ],
            onChanged: (key) => setState(() {
              _wall = widget.room.walls.firstWhere((w) => w.key == key);
            }),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RoomNumberField(
                  controller: _width,
                  label: 'Ширина',
                  unit: 'м',
                  max: 200,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RoomNumberField(
                  controller: _height,
                  label: 'Высота',
                  unit: 'м',
                  max: 200,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RoomNumberField(
            controller: _offset,
            label: 'Отступ от начала стены',
            unit: 'м',
            zeroAllowed: true,
            max: 200,
          ),
          const SizedBox(height: 16),
          RoomNumberField(
            controller: _sill,
            label: 'От пола до проёма',
            unit: 'м',
            zeroAllowed: true,
            max: 200,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              final o = RoomOpening(
                id: widget.initial?.id ?? const Uuid().v4(),
                wallKey: _wall.key,
                kind: _kind,
                width: RoomNumberField.parse(_width.text)!,
                height: RoomNumberField.parse(_height.text)!,
                offset: RoomNumberField.parse(_offset.text)!,
                sill: RoomNumberField.parse(_sill.text)!,
              );
              try {
                RoomGeometry(
                  widget.room.copyWith(
                    openings: [
                      ...widget.room.openings.where((v) => v.id != o.id),
                      o,
                    ],
                  ),
                ).validate();
                Navigator.pop(context, o);
              } on FormatException catch (e) {
                setState(() => _error = e.message);
              }
            },
            child: const Text('Сохранить проём'),
          ),
        ],
      ),
    ),
  );
}
