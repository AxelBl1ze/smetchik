import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/address_autocomplete_field.dart';
import '../../shared/smetchik_date_picker.dart';
import '../../shared/ui.dart';
import '../../shared/upgrade_sheet.dart';
import 'project_status_widgets.dart';

class ProjectFormScreen extends ConsumerStatefulWidget {
  const ProjectFormScreen({super.key, this.projectId});

  final String? projectId;

  @override
  ConsumerState<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends ConsumerState<ProjectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _address = TextEditingController();
  final _customer = TextEditingController();
  final _revenue = TextEditingController();
  final _notes = TextEditingController();
  DateTime _startDate = DateTime.now();
  DateTime? _targetDate;
  String _status = ProjectStatus.planning;
  bool _hydrated = false;
  bool _saving = false;

  bool get _isEditing => widget.projectId != null;

  @override
  void dispose() {
    _title.dispose();
    _address.dispose();
    _customer.dispose();
    _revenue.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.projectId == null
        ? null
        : ref.watch(projectDetailProvider(widget.projectId!));
    detail?.whenData((value) {
      if (!_hydrated) _hydrate(value.project);
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Редактировать объект' : 'Новый объект'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Сохранить'),
          ),
        ],
      ),
      body:
          detail?.when(
            data: (_) => _form(),
            loading: () => const LoadingPane(),
            error: (error, _) => ErrorPane(error: error),
          ) ??
          _form(),
    );
  }

  Widget _form() {
    return Form(
      key: _formKey,
      child: ResponsiveListView(
        maxWidth: 720,
        children: [
          ScreenTitle(
            title: _isEditing ? 'Параметры объекта' : 'Новый объект',
            subtitle: 'Внутренний учёт стройки, расходов и поступлений',
            icon: Icons.domain_add_outlined,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Название объекта',
              hintText: 'Дом на Садовой',
            ),
            validator: (value) => value == null || value.trim().length < 2
                ? 'Укажите название объекта'
                : null,
          ),
          const SizedBox(height: 12),
          AddressAutocompleteField(
            controller: _address,
            labelText: 'Адрес объекта',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _customer,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Заказчик или владелец',
              hintText: 'Необязательно',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _revenue,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Плановая выручка / цена продажи',
              suffixText: '₽',
            ),
          ),
          const SizedBox(height: 12),
          ProjectStatusField(
            status: _status,
            onChanged: (value) => setState(() => _status = value),
          ),
          const SizedBox(height: 12),
          _DateField(
            label: 'Начало работ',
            value: _startDate,
            onSelect: (value) => setState(() => _startDate = value),
          ),
          const SizedBox(height: 10),
          _DateField(
            label: 'Плановое завершение',
            value: _targetDate,
            onSelect: (value) => setState(() => _targetDate = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Заметка по объекту',
              hintText: 'Например: фундамент готов, ждём окна',
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Сохраняем...' : 'Сохранить объект'),
          ),
        ],
      ),
    );
  }

  void _hydrate(ProjectModel project) {
    _hydrated = true;
    _title.text = project.title;
    _address.text = project.objectAddress ?? '';
    _customer.text = project.customerName ?? '';
    _revenue.text = project.plannedRevenue == 0
        ? ''
        : project.plannedRevenue.toStringAsFixed(0);
    _notes.text = project.notes ?? '';
    _startDate = project.startDate;
    _targetDate = project.targetDate;
    _status = project.status;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = await ref
          .read(repositoryProvider)
          .saveProject(
            ProjectDraft(
              title: _title.text,
              objectAddress: _address.text,
              customerName: _customer.text,
              plannedRevenue:
                  double.tryParse(_revenue.text.replaceAll(',', '.')) ?? 0,
              startDate: _startDate,
              targetDate: _targetDate,
              status: _status,
              notes: _notes.text,
            ),
            projectId: widget.projectId,
          );
      ref.invalidate(projectsProvider);
      ref.invalidate(projectDetailProvider(id));
      if (!mounted) return;
      context.go('/projects/$id');
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      if (message.contains('Базовом тарифе')) {
        showUpgradeSheet(
          context: context,
          message: message,
          onOpenPlans: () => context.go('/settings'),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onSelect,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final selected = await showSmetchikDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
          title: label,
        );
        if (selected != null) onSelect(selected);
      },
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text(value == null ? label : '$label: ${formatDate(value!)}'),
    );
  }
}
