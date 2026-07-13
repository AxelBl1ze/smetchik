import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/offline_sync_service.dart';
import '../../data/repository.dart';
import '../../shared/address_autocomplete_field.dart';
import '../../shared/russian_phone_input_formatter.dart';
import '../../shared/form_sheet.dart';
import '../../shared/ui.dart';
import '../../shared/upgrade_sheet.dart';

class EstimateFormScreen extends ConsumerStatefulWidget {
  const EstimateFormScreen({
    super.key,
    this.estimateId,
    this.offlineDraftId,
    this.createRevision = false,
  });

  final String? estimateId;
  final String? offlineDraftId;
  final bool createRevision;

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
  int _sourceDocumentVersion = 1;

  bool get _isEdit => widget.estimateId != null;
  bool get _isRevision => widget.createRevision && _isEdit;
  bool get _isOfflineDraft => widget.offlineDraftId != null;
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
    final profile = ref.watch(profileProvider);
    final estimates = ref.watch(estimatesProvider);
    final offlineSync = ref.watch(offlineSyncProvider);
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
    if (_isOfflineDraft && !_hydrated && offlineSync.isReady) {
      final entry = offlineSync.entries
          .where((item) => item.id == widget.offlineDraftId)
          .firstOrNull;
      if (entry != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _hydrateOffline(entry.estimateDraft),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isOfflineDraft
              ? 'Черновик на устройстве'
              : _isRevision
              ? 'Новая версия сметы'
              : _isEdit
              ? 'Редактировать смету'
              : 'Новая смета',
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Сохранить'),
          ),
        ],
      ),
      body:
          detail?.when(
            data: (_) => _form(clients, profile, estimates),
            loading: () => const LoadingPane(),
            error: (error, _) => ErrorPane(error: error),
          ) ??
          _form(clients, profile, estimates),
    );
  }

  Widget _form(
    AsyncValue<List<ClientModel>> clients,
    AsyncValue<ProfileModel?> profile,
    AsyncValue<List<EstimateModel>> estimates,
  ) {
    return Form(
      key: _formKey,
      child: ResponsiveListView(
        maxWidth: 920,
        children: [
          if (!_isEdit || _isRevision)
            profile.when(
              data: (value) => _EstimateLimitBanner(
                profile: value,
                estimates: estimates.asData?.value ?? const [],
                onUpgrade: () => context.go('/settings'),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          if (!_isEdit || _isRevision) const SizedBox(height: 12),
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
            label: Text(
              _isRevision
                  ? 'Создать новую версию'
                  : _isEdit
                  ? 'Сохранить изменения'
                  : 'Сохранить смету',
            ),
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
      _sourceDocumentVersion = detail.estimate.documentVersion;
      _lines
        ..clear()
        ..addAll(detail.lines);
    });
  }

  void _hydrateOffline(EstimateDraft draft) {
    if (!mounted || _hydrated) return;
    setState(() {
      _hydrated = true;
      _object.text = draft.objectTitle;
      _clientId = draft.clientId;
      _clientName.text = draft.clientName;
      _clientPhone.text = RussianPhoneInputFormatter.format(
        draft.clientPhone ?? '',
      );
      _duration.text = draft.durationDays?.toString() ?? '';
      _date = draft.estimateDate;
      _lines
        ..clear()
        ..addAll(draft.lines);
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
    final result = await showModalBottomSheet<_AddWorkResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddWorkSheet(catalog: catalog),
    );
    if (!mounted || result == null) return;
    if (result.custom) {
      await _editLine(null);
      return;
    }

    final item = result.item;
    if (item == null) return;
    setState(() {
      _lines.add(EstimateLineModel.fromCatalog(item, _lines.length));
    });
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

    _disposeLineControllersLater([title, unit, qty, price]);

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

  void _disposeLineControllersLater(List<TextEditingController> controllers) {
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      for (final controller in controllers) {
        controller.dispose();
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
    final draft = EstimateDraft(
      objectTitle: _object.text,
      clientId: _clientId,
      clientName: _clientName.text,
      clientPhone: _clientPhone.text,
      estimateDate: _date,
      durationDays: int.tryParse(_duration.text),
      lines: _lines,
    );
    try {
      if (_isOfflineDraft) {
        await ref
            .read(offlineSyncProvider)
            .queueEstimate(draft, id: widget.offlineDraftId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Черновик сохранён на устройстве и ждёт синхронизации',
            ),
          ),
        );
        context.go('/estimates');
        return;
      }
      final id = await ref
          .read(repositoryProvider)
          .saveEstimateDraft(
            draft,
            estimateId: _isRevision ? null : widget.estimateId,
            revisionOf: _isRevision ? widget.estimateId : null,
            documentVersion: _isRevision ? _sourceDocumentVersion + 1 : null,
          );
      ref.invalidate(estimatesProvider);
      ref.invalidate(clientsProvider);
      ref.invalidate(estimateDetailProvider(id));
      if (!mounted) return;
      context.go('/estimate/$id');
    } catch (error) {
      if (!mounted) return;
      if (_isUpgradeError(error)) {
        _showUpgradeDialog(error.toString());
        return;
      }
      if (!_isEdit && isRecoverableNetworkError(error)) {
        await ref.read(offlineSyncProvider).queueEstimate(draft);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет связи: черновик сохранён на устройстве'),
          ),
        );
        context.go('/estimates');
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _isUpgradeError(Object error) {
    final message = error.toString();
    return message.contains('Лимит базового тарифа') ||
        message.contains('Настройки PDF доступны');
  }

  void _showUpgradeDialog(String message) {
    showUpgradeSheet(
      context: context,
      message: message.replaceFirst('Exception: ', ''),
      onOpenPlans: () => context.go('/settings'),
    );
  }
}

class _AddWorkResult {
  const _AddWorkResult.item(this.item) : custom = false;
  const _AddWorkResult.custom() : item = null, custom = true;

  final CatalogItemModel? item;
  final bool custom;
}

class _AddWorkSheet extends StatefulWidget {
  const _AddWorkSheet({required this.catalog});

  final List<CatalogItemModel> catalog;

  @override
  State<_AddWorkSheet> createState() => _AddWorkSheetState();
}

class _AddWorkSheetState extends State<_AddWorkSheet> {
  final _search = TextEditingController();
  var _query = '';
  var _closing = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? widget.catalog
        : widget.catalog.where((item) {
            final haystack =
                '${item.category} ${item.title} ${item.unit} ${item.unitPrice}'
                    .toLowerCase();
            return haystack.contains(normalizedQuery);
          }).toList();
    final rows = _buildRows(filtered);

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
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _closing ? null : _selectCustom,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Своя'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  controller: _search,
                  autofocus: widget.catalog.length > 18,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Поиск по работам',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Очистить',
                            onPressed: _closing
                                ? null
                                : () {
                                    _search.clear();
                                    setState(() => _query = '');
                                  },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                        children: [
                          EmptyState(
                            icon: Icons.search_off,
                            title: 'Ничего не найдено',
                            body:
                                'Попробуйте другой запрос или добавьте свою работу.',
                            action: FilledButton.icon(
                              onPressed: _closing ? null : _selectCustom,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Своя работа'),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          if (row.category != null) {
                            return Padding(
                              padding: const EdgeInsets.only(
                                top: 10,
                                bottom: 6,
                              ),
                              child: Text(
                                row.category!,
                                style: const TextStyle(
                                  color: AppColors.textHint,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            );
                          }

                          final item = row.item!;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: SmetchikCard(
                              onTap: _closing ? null : () => _selectItem(item),
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
                                      borderRadius: BorderRadius.circular(10),
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
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '${item.unit} · ${formatMoney(item.unitPrice)}',
                                          style: const TextStyle(
                                            color: AppColors.textHint,
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
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_AddWorkRow> _buildRows(List<CatalogItemModel> items) {
    final grouped = <String, List<CatalogItemModel>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    final rows = <_AddWorkRow>[];
    for (final entry in grouped.entries) {
      rows.add(_AddWorkRow.category(entry.key));
      rows.addAll(entry.value.map(_AddWorkRow.item));
    }
    return rows;
  }

  void _selectItem(CatalogItemModel item) {
    if (_closing) return;
    setState(() => _closing = true);
    Navigator.of(context).pop(_AddWorkResult.item(item));
  }

  void _selectCustom() {
    if (_closing) return;
    setState(() => _closing = true);
    Navigator.of(context).pop(const _AddWorkResult.custom());
  }
}

class _AddWorkRow {
  const _AddWorkRow.category(this.category) : item = null;
  const _AddWorkRow.item(this.item) : category = null;

  final String? category;
  final CatalogItemModel? item;
}

class _EstimateLimitBanner extends StatelessWidget {
  const _EstimateLimitBanner({
    required this.profile,
    required this.estimates,
    required this.onUpgrade,
  });

  final ProfileModel? profile;
  final List<EstimateModel> estimates;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final current = profile;
    if (current == null || current.hasActivePro) {
      return const SizedBox.shrink();
    }

    final created = _createdThisMonth(estimates);
    final limit =
        current.monthlyEstimateLimit ?? ProfileModel.basicMonthlyEstimateLimit;
    final remaining = current.remainingMonthlyEstimates(created);
    final displayedCreated = created > limit ? limit : created;
    final progress = (created / limit).clamp(0.0, 1.0);

    return SmetchikCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                remaining == 0
                    ? Icons.lock_outline
                    : Icons.workspace_premium_outlined,
                color: remaining == 0 ? AppColors.danger : AppColors.orangeDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  remaining == 0
                      ? 'Лимит базового тарифа исчерпан'
                      : 'Базовый тариф: $displayedCreated/$limit смет',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              FilledButton(
                onPressed: onUpgrade,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: const Text('Оформить'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              color: remaining == 0 ? AppColors.danger : AppColors.orange,
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            remaining == 0
                ? 'Подключите Профи, чтобы создавать сметы без ограничений.'
                : 'Осталось $remaining смет в этом месяце.',
            style: TextStyle(
              color: remaining == 0 ? AppColors.danger : AppColors.textHint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

int _createdThisMonth(List<EstimateModel> estimates) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month);
  return estimates
      .where((estimate) => !estimate.createdAt.isBefore(start))
      .length;
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
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Действия',
            onPressed: () => _showActions(context),
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final action = await showModalBottomSheet<_LineAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _LineActionSheet(line: line),
    );
    if (action == null) return;
    switch (action) {
      case _LineAction.edit:
        onEdit();
      case _LineAction.delete:
        onDelete();
    }
  }
}

enum _LineAction { edit, delete }

class _LineActionSheet extends StatelessWidget {
  const _LineActionSheet({required this.line});

  final EstimateLineModel line;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.orangeLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.handyman_outlined,
                      color: AppColors.orangeDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${formatQuantity(line.quantity)} ${line.unit} · ${formatMoney(line.lineTotal)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _LineActionTile(
                icon: Icons.edit_outlined,
                title: 'Изменить',
                subtitle: 'Количество, цену или название работы',
                onTap: () => Navigator.of(context).pop(_LineAction.edit),
              ),
              const SizedBox(height: 8),
              _LineActionTile(
                icon: Icons.delete_outline,
                title: 'Удалить из сметы',
                subtitle: 'Позиция пропадёт только из этой сметы',
                destructive: true,
                onTap: () => Navigator.of(context).pop(_LineAction.delete),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineActionTile extends StatelessWidget {
  const _LineActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.graphite;
    final iconColor = destructive ? AppColors.danger : AppColors.orangeDark;
    final bgColor = destructive ? AppColors.dangerBg : AppColors.orangeLight;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: destructive ? color : AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}
