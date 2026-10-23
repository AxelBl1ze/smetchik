import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../shared/keyboard_form_sheet.dart';

class ProjectPayerField extends StatelessWidget {
  const ProjectPayerField({
    super.key,
    required this.controller,
    required this.names,
    this.label = 'Кто оплатил',
  });

  final TextEditingController controller;
  final List<String> names;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLength: 120,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Имя плательщика',
        counterText: '',
        prefixIcon: const Icon(Icons.person_outline),
        suffixIcon: names.isEmpty
            ? null
            : IconButton(
                tooltip: 'Выбрать плательщика',
                onPressed: () async {
                  FocusScope.of(context).unfocus();
                  final selected = await showModalBottomSheet<String>(
                    context: context,
                    useSafeArea: true,
                    isScrollControlled: true,
                    backgroundColor: AppColors.card,
                    constraints: const BoxConstraints(maxWidth: 560),
                    builder: (_) => _PayerPicker(names: names),
                  );
                  if (selected != null && context.mounted) {
                    controller.value = TextEditingValue(
                      text: selected,
                      selection: TextSelection.collapsed(
                        offset: selected.length,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
      ),
    );
  }
}

class _PayerPicker extends StatefulWidget {
  const _PayerPicker({required this.names});
  final List<String> names;

  @override
  State<_PayerPicker> createState() => _PayerPickerState();
}

class _PayerPickerState extends State<_PayerPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final names = widget.names
        .where((name) => name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return KeyboardFormSheet(
      header: const Text(
        'Плательщики объекта',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            maxLength: 120,
            decoration: const InputDecoration(
              hintText: 'Найти по имени',
              prefixIcon: Icon(Icons.search),
              counterText: '',
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          const SizedBox(height: 8),
          for (final name in names)
            ListTile(
              leading: const Icon(
                Icons.person_outline,
                color: AppColors.orangeDark,
              ),
              title: Text(name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, name),
            ),
          if (_query.isNotEmpty &&
              !widget.names.any(
                (name) => name.toLowerCase() == _query.toLowerCase(),
              ))
            ListTile(
              leading: const Icon(
                Icons.person_add_alt_outlined,
                color: AppColors.orangeDark,
              ),
              title: Text('Добавить «$_query»'),
              onTap: () => Navigator.pop(context, _query),
            ),
        ],
      ),
    );
  }
}
