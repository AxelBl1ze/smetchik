import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/address_autocomplete_field.dart';
import '../../shared/russian_phone_input_formatter.dart';
import '../../shared/form_sheet.dart';
import '../../shared/ui.dart';

class EstimateFormScreen extends ConsumerStatefulWidget {
  const EstimateFormScreen({super.key, this.estimateId});

  final String? estimateId;

  @override
  ConsumerState<EstimateFormScreen> createState() => _EstimateFormScreenState();
}

class _EstimateFormScreenState extends ConsumerState<EstimateFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _object = TextEditingController();
  final _clientName = TextEditingController();
  final _clientPhone = TextEditingController();
  final _duration = TextEditingController(text: '14');
  DateTime _date = DateTime.now();
  String? _clientId;
  final List<EstimateLineModel> _lines = [];
  bool _saving = false;
  bool _hydrated = false;

  bool get _isEdit => widget.estimateId != null;
  double get _total => _lines.fold(0, (sum, line) => sum + line.lineTotal);

  @override
  void dispose() {
    _object.dispose();
    _clientName.dispose();
    _clientPhone.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider);
    final detail = widget.estimateId == null
        ? null
        : ref.watch(estimateDetailProvider(widget.estimateId!));

    if (detail != null) {
      detail.whenData((value) {
        if (!_hydrated) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate(value));
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Редактировать смету' : 'Новая смета'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Сохранить'),
          ),
        ],
      ),
      body:
          detail?.when(
            data: (_) => _form(clients),
            loading: () => const LoadingPane(),
            error: (error, _) => ErrorPane(error: error),
          ) ??
          _form(clients),
    );
  }

  Widget _form(AsyncValue<List<ClientModel>> clients) {
    return Form(
      key: _formKey,
      child: ResponsiveListView(
        maxWidth: 920,
        children: [
          AddressAutocompleteField(
            controller: _object,
            labelText: 'Название объекта / адрес',
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.trim().length < 3) {
                return 'Например: Ванная, ул. Садовая 12';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _clientName,
                  decoration: const InputDecoration(labelText: 'Клиент'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _clientPhone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: const [RussianPhoneInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Телефон'),
                ),
              ),
            ],
          ),
          clients.when(
            data: (items) {
              if (items.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final client in items.take(8))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            avatar: const Icon(Icons.person_outline, size: 16),
                            label: Text(client.name),
                            onPressed: () {
                              setState(() {
                                _clientId = client.id;
                                _clientName.text = client.name;
                                _clientPhone.text =
                                    RussianPhoneInputFormatter.format(
                                      client.phone ?? '',
                                    );
                                if (_object.text.trim().isEmpty &&
                                    client.objectAddress?.trim().isNotEmpty ==
                                        true) {
                                  _object.text = client.objectAddress!.trim();
                                }
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(formatDate(_date)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Срок, дней'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SectionHeader(
            title: 'Работы',
            action: TextButton.icon(
              onPressed: _showAddWorkSheet,
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
            ),
          ),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            EmptyState(
              icon: Icons.playlist_add,
              title: 'Добавьте работы',
              body: 'Выберите позиции из каталога или добавьте свою работу.',
              action: FilledButton.icon(
                onPressed: _showAddWorkSheet,
                icon: const Icon(Icons.add),
                label: const Text('Добавить работу'),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < _lines.length; i++) ...[
                  _LineTile(
                    index: i + 1,
                    line: _lines[i],
                    onEdit: () => _editLine(i),
                    onDelete: () => setState(() => _lines.removeAt(i)),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.graphite2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Text(
                  'Итого',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  formatMoney(_total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
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
                : const Icon(Icons.save),
            label: Text(_isEdit ? 'Сохранить изменения' : 'Сохранить смету'),
          ),
        ],
      ),
    );
  }

  void _hydrate(EstimateDetail detail) {
    if (!mounted || _hydrated) return;
    setState(() {
      _hydrated = true;
      _object.text = detail.estimate.objectTitle;
      _clientId = detail.estimate.clientId;
      _clientName.text = detail.estimate.client?.name ?? '';
      _clientPhone.text = RussianPhoneInputFormatter.format(
        detail.estimate.client?.phone ?? '',
      );
      _duration.text = detail.estimate.durationDays?.toString() ?? '';
      _date = detail.estimate.estimateDate;
      _lines
        ..clear()
        ..addAll(detail.lines);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _showAddWorkSheet() async {
    final catalog = await ref.read(catalogItemsProvider.future);
    if (!mounted) return;
    final search = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          var query = '';
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final normalizedQuery = query.trim().toLowerCase();
              final filtered = normalizedQuery.isEmpty
                  ? catalog
                  : catalog.where((item) {
                      final haystack =
                          '${item.category} ${item.title} ${item.unit} ${item.unitPrice}'
                              .toLowerCase();
                      return haystack.contains(normalizedQuery);
                    }).toList();

              final grouped = <String, List<CatalogItemModel>>{};
              for (final item in filtered) {
                grouped.putIfAbsent(item.category, () => []).add(item);
              }

              return DraggableScrollableSheet(
                initialChildSize: 0.82,
                minChildSize: 0.48,
                maxChildSize: 0.95,
                builder: (context, scrollController) => Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Добавить работу',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _editLine(null);
                                },
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: const Text('Своя'),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: TextField(
                            controller: search,
                            autofocus: catalog.length > 18,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Поиск по работам',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Очистить',
                                      onPressed: () {
                                        search.clear();
                                        setSheetState(() => query = '');
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                            ),
                            onChanged: (value) =>
                                setSheetState(() => query = value),
                          ),
                        ),
                        Expanded(
                          child: filtered.isEmpty
                              ? ListView(
                                  controller: scrollController,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    16,
                                    16,
                                    20,
                                  ),
                                  children: [
                                    EmptyState(
                                      icon: Icons.search_off,
                                      title: 'Ничего не найдено',
                                      body:
                                          'Попробуйте другой запрос или добавьте свою работу.',
                                      action: FilledButton.icon(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _editLine(null);
                                        },
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('Своя работа'),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView(
                                  controller: scrollController,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    20,
                                  ),
                                  children: [
                                    for (final entry in grouped.entries) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 10,
                                          bottom: 6,
                                        ),
                                        child: Text(
                                          entry.key,
                                          style: const TextStyle(
                                            color: AppColors.textHint,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      for (final item in entry.value)
                                        SmetchikCard(
                                          onTap: () {
                                            setState(() {
                                              _lines.add(
                                                EstimateLineModel.fromCatalog(
                                                  item,
                                                  _lines.length,
                                                ),
                                              );
                                            });
                                            Navigator.pop(context);
                                          },
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 36,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  color: AppColors.orangeLight,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: const Icon(
                                                  Icons.build,
                                                  color: AppColors.orangeDark,
                                                  size: 18,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.title,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${item.unit} · ${formatMoney(item.unitPrice)}',
                                                      style: const TextStyle(
                                                        color:
                                                            AppColors.textHint,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Icon(
                                                Icons.add_circle,
                                                color: AppColors.orange,
                                              ),
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                    ],
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      search.dispose();
    }
  }

  Future<void> _editLine(int? index) async {
    final existing = index == null ? null : _lines[index];
    final title = TextEditingController(text: existing?.title ?? '');
    final unit = TextEditingController(text: existing?.unit ?? 'шт');
    final qty = TextEditingController(
      text: (existing?.quantity ?? 1).toString(),
    );
    final price = TextEditingController(
      text: (existing?.unitPrice ?? 0).toStringAsFixed(0),
    );

    EstimateLineModel? result;
    final saved = await showFormSheet(
      context: context,
      title: index == null ? 'Своя работа' : 'Изменить работу',
      subtitle: 'Укажите название, количество и цену',
      confirmLabel: 'Готово',
      fields: [
        TextField(
          controller: title,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Название',
            hintText: 'Монтаж радиатора',
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: unit,
                decoration: const InputDecoration(labelText: 'Ед. изм.'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Кол-во'),
              ),
            ),
          ],
        ),
        TextField(
          controller: price,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Цена за единицу',
            suffixText: '₽',
          ),
        ),
      ],
    );

    if (saved == true) {
      final quantity = double.tryParse(qty.text.replaceAll(',', '.')) ?? 1;
      final unitPrice = double.tryParse(price.text.replaceAll(',', '.')) ?? 0;
      result = EstimateLineModel(
        id: existing?.id ?? const Uuid().v4(),
        catalogItemId: existing?.catalogItemId,
        title: title.text.trim(),
        unit: unit.text.trim().isEmpty ? 'шт' : unit.text.trim(),
        quantity: quantity,
        unitPrice: unitPrice,
        lineTotal: quantity * unitPrice,
        sortOrder: index ?? _lines.length,
      );
    }

    title.dispose();
    unit.dispose();
    qty.dispose();
    price.dispose();

    final line = result;
    if (line == null || line.title.isEmpty) return;
    setState(() {
      if (index == null) {
        _lines.add(line);
      } else {
        _lines[index] = line;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы одну работу')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref
          .read(repositoryProvider)
          .saveEstimateDraft(
            EstimateDraft(
              objectTitle: _object.text,
              clientId: _clientId,
              clientName: _clientName.text,
              clientPhone: _clientPhone.text,
              estimateDate: _date,
              durationDays: int.tryParse(_duration.text),
              lines: _lines,
            ),
            estimateId: widget.estimateId,
          );
      ref.invalidate(estimatesProvider);
      ref.invalidate(clientsProvider);
      ref.invalidate(estimateDetailProvider(id));
      if (!mounted) return;
      context.go('/estimate/$id');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.index,
    required this.line,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final EstimateLineModel line;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                color: AppColors.orangeDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${formatQuantity(line.quantity)} ${line.unit} × ${formatMoney(line.unitPrice)}',
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(line.lineTotal),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Изменить')),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ],
      ),
    );
  }
}
