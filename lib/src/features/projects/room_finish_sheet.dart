import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_theme.dart';
import '../../data/room_calculator.dart';
import '../../shared/keyboard_form_sheet.dart';
import 'room_plan_view.dart';

class RoomChoice<T> extends StatelessWidget {
  const RoomChoice({
    super.key,
    required this.values,
    required this.value,
    required this.label,
    required this.onChanged,
  });
  final List<T> values;
  final T value;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        for (final item in values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Semantics(
                selected: item == value,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onChanged(item),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: item == value
                          ? AppColors.graphite
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      label(item),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: item == value
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class RoomNumberField extends StatelessWidget {
  const RoomNumberField({
    super.key,
    required this.controller,
    required this.label,
    this.unit,
    this.zeroAllowed = false,
    this.max = 100000,
    this.integer = false,
    this.readOnly = false,
  });
  final TextEditingController controller;
  final String label;
  final String? unit;
  final bool zeroAllowed, integer;
  final bool readOnly;
  final double max;
  static double? parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    readOnly: readOnly,
    keyboardType: TextInputType.numberWithOptions(decimal: !integer),
    textInputAction: TextInputAction.next,
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    decoration: InputDecoration(
      labelText: label,
      suffixText: unit,
      floatingLabelStyle: const TextStyle(
        fontSize: 12,
        color: AppColors.textSecondary,
      ),
    ),
    validator: (text) {
      final n = parse(text ?? '');
      if (n == null ||
          !n.isFinite ||
          n < (zeroAllowed ? 0 : .0001) ||
          n > max ||
          integer && n != n.roundToDouble()) {
        return integer
            ? 'Целое от ${zeroAllowed ? 0 : 1} до ${max.toInt()}'
            : 'От ${zeroAllowed ? 0 : 0.0001} до ${roomNumber(max)}';
      }
      return null;
    },
  );
}

Future<RoomFinish?> showRoomFinishSheet(
  BuildContext context,
  ProjectRoom room, {
  RoomFinish? initial,
}) => showModalBottomSheet<RoomFinish>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  useRootNavigator: true,
  backgroundColor: Colors.transparent,
  builder: (context) => _FinishSheet(room: room, initial: initial),
);

class _FinishSheet extends StatefulWidget {
  const _FinishSheet({required this.room, this.initial});
  final ProjectRoom room;
  final RoomFinish? initial;
  @override
  State<_FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends State<_FinishSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _numbers = <String, TextEditingController>{};
  late FinishKind _kind;
  late RoomSurface _surface;
  late Set<String> _walls;
  String? _error;
  @override
  void initState() {
    super.initState();
    final f =
        widget.initial ??
        RoomFinish(
          id: const Uuid().v4(),
          name: '',
          kind: FinishKind.tile,
          surface: RoomSurface.floor,
        );
    _name = TextEditingController(text: f.name);
    _kind = f.kind;
    _surface = f.surface;
    _walls = f.wallKeys.toSet();
    final values = {
      'waste': f.waste,
      'tileWidth': f.tileWidth,
      'tileHeight': f.tileHeight,
      'tilesPerPack': f.tilesPerPack.toDouble(),
      'coverage': f.coverage,
      'coats': f.coats.toDouble(),
      'canLitres': f.canLitres,
      'rollWidth': f.rollWidth,
      'rollLength': f.rollLength,
      'repeat': f.repeat * 100,
      'trim': f.trim * 100,
      'finishHeight': f.finishHeight,
    };
    for (final e in values.entries) {
      _numbers[e.key] = TextEditingController(text: roomNumber(e.value));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _numbers.values) {
      c.dispose();
    }
    super.dispose();
  }

  double n(String key) =>
      RoomNumberField.parse(_numbers[key]!.text) ?? double.nan;
  Widget field(
    String key,
    String label, {
    String? unit,
    bool zero = false,
    bool integer = false,
    double max = 100000,
  }) => RoomNumberField(
    controller: _numbers[key]!,
    label: label,
    unit: unit,
    zeroAllowed: zero,
    integer: integer,
    max: max,
  );
  Widget pair(Widget a, Widget b) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: a),
      const SizedBox(width: 12),
      Expanded(child: b),
    ],
  );

  @override
  Widget build(BuildContext context) => KeyboardFormSheet(
    header: Text(
      widget.initial == null ? 'Материал для отделки' : 'Изменить расчёт',
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
            values: FinishKind.values,
            value: _kind,
            label: (v) => v.label,
            onChanged: (v) => setState(() {
              _kind = v;
              if (v == FinishKind.wallpaper) _surface = RoomSurface.walls;
              _error = null;
            }),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Название материала',
              hintText: 'Марка, цвет или артикул',
              counterText: '',
            ),
            validator: (s) =>
                s == null || s.trim().isEmpty ? 'Укажите материал' : null,
          ),
          const SizedBox(height: 16),
          if (_kind != FinishKind.wallpaper) ...[
            RoomChoice(
              values: RoomSurface.values,
              value: _surface,
              label: (v) => v.label,
              onChanged: (v) => setState(() => _surface = v),
            ),
            const SizedBox(height: 16),
          ],
          if (_kind == FinishKind.tile) ...[
            pair(
              field('tileWidth', 'Ширина плитки', unit: 'см', max: 1000),
              field('tileHeight', 'Длина плитки', unit: 'см', max: 1000),
            ),
            const SizedBox(height: 16),
            field(
              'tilesPerPack',
              'Плиток в упаковке',
              unit: 'шт',
              integer: true,
              max: 10000,
            ),
          ],
          if (_kind == FinishKind.paint) ...[
            field(
              'coverage',
              'Укрывистость за 1 слой',
              unit: 'м²/л',
              max: 1000,
            ),
            const SizedBox(height: 16),
            pair(
              field('coats', 'Слоёв', integer: true, max: 20),
              field('canLitres', 'Объём банки', unit: 'л', max: 1000),
            ),
          ],
          if (_kind == FinishKind.wallpaper) ...[
            pair(
              field('rollWidth', 'Ширина рулона', unit: 'м', max: 5),
              field('rollLength', 'Длина рулона', unit: 'м', max: 1000),
            ),
            const SizedBox(height: 16),
            pair(
              field('repeat', 'Раппорт', unit: 'см', zero: true, max: 500),
              field(
                'trim',
                'Подрезка полосы',
                unit: 'см',
                zero: true,
                max: 100,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Раппорт — прямое совмещение рисунка. Для смещённого рисунка добавьте запас по этикетке. '
              'Проёмы не уменьшают число полноразмерных полос.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 16),
          field('waste', 'Запас', unit: '%', zero: true, max: 100),
          if (_surface == RoomSurface.walls) ...[
            const SizedBox(height: 16),
            field(
              'finishHeight',
              'Высота отделки (0 — вся стена)',
              unit: 'м',
              zero: true,
              max: widget.room.height,
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                _walls.isEmpty ? 'Все стены' : 'Стены: ${_walls.length}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              shape: const Border(),
              collapsedShape: const Border(),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Только выбранные стены'),
                  value: _walls.isNotEmpty,
                  onChanged: (selected) => setState(
                    () => _walls = selected
                        ? widget.room.walls.map((w) => w.key).toSet()
                        : {},
                  ),
                ),
                if (_walls.isNotEmpty)
                  for (var i = 0; i < widget.room.walls.length; i++)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Стена ${i + 1} · ${roomNumber(RoomGeometry(widget.room).wallLength(widget.room.walls[i]))} м',
                      ),
                      value:
                          _walls.isEmpty ||
                          _walls.contains(widget.room.walls[i].key),
                      onChanged:
                          _walls.length == 1 &&
                              _walls.contains(widget.room.walls[i].key)
                          ? null
                          : (selected) => setState(() {
                              if (_walls.isEmpty) {
                                _walls = widget.room.walls
                                    .map((w) => w.key)
                                    .toSet();
                              }
                              final key = widget.room.walls[i].key;
                              if (selected == true) {
                                _walls.add(key);
                              } else if (_walls.length > 1) {
                                _walls.remove(key);
                              }
                            }),
                    ),
              ],
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Рассчитать'),
          ),
        ],
      ),
    ),
  );
  void _submit() {
    if (!_form.currentState!.validate()) return;
    final f = RoomFinish(
      id: widget.initial?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      kind: _kind,
      surface: _surface,
      wallKeys: _walls.toList()..sort(),
      finishHeight: _surface == RoomSurface.walls ? n('finishHeight') : 0,
      waste: n('waste'),
      tileWidth: _kind == FinishKind.tile ? n('tileWidth') : 30,
      tileHeight: _kind == FinishKind.tile ? n('tileHeight') : 60,
      tilesPerPack: _kind == FinishKind.tile ? n('tilesPerPack').toInt() : 8,
      coverage: _kind == FinishKind.paint ? n('coverage') : 10,
      coats: _kind == FinishKind.paint ? n('coats').toInt() : 2,
      canLitres: _kind == FinishKind.paint ? n('canLitres') : 2.5,
      rollWidth: _kind == FinishKind.wallpaper ? n('rollWidth') : .53,
      rollLength: _kind == FinishKind.wallpaper ? n('rollLength') : 10.05,
      repeat: _kind == FinishKind.wallpaper ? n('repeat') / 100 : 0,
      trim: _kind == FinishKind.wallpaper ? n('trim') / 100 : .1,
    );
    try {
      RoomCalculator.calculate(widget.room, f);
      Navigator.pop(context, f);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }
}
