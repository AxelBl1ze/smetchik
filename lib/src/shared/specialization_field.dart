import 'package:flutter/material.dart';

import '../core/app_theme.dart';

const masterSpecializations = [
  'Сантехник',
  'Электрик',
  'Отделочник',
  'Плиточник',
  'Маляр',
  'Штукатур',
  'Монтажник',
  'Ремонт квартир',
  'Мастер на час',
  'Сборщик мебели',
  'Установщик дверей',
  'Оконный мастер',
  'Кондиционеры',
  'Сварщик',
  'Кровельщик',
  'Разнорабочий',
];

String normalizeSpecialization(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return '';

  final lower = trimmed.toLowerCase();
  return '${lower.substring(0, 1).toUpperCase()}${lower.substring(1)}';
}

class SpecializationField extends StatefulWidget {
  const SpecializationField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<SpecializationField> createState() => _SpecializationFieldState();
}

class _SpecializationFieldState extends State<SpecializationField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return masterSpecializations;
        return masterSpecializations.where(
          (item) => item.toLowerCase().contains(query),
        );
      },
      onSelected: (value) {
        widget.controller.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Специализация',
            prefixIcon: Icon(Icons.handyman_outlined),
          ),
          onEditingComplete: () {
            final normalized = normalizeSpecialization(controller.text);
            controller.value = TextEditingValue(
              text: normalized,
              selection: TextSelection.collapsed(offset: normalized.length),
            );
            onFieldSubmitted();
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final values = options.toList(growable: false);
        if (values.isEmpty) return const SizedBox.shrink();

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 10,
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 420),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: values.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final value = values[index];
                  return InkWell(
                    onTap: () => onSelected(value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.handyman_outlined,
                            color: AppColors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              value,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
