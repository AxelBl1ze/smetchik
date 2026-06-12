import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/pdf_service.dart';
import '../../data/repository.dart';
import '../../shared/app_shell.dart';
import '../../shared/form_sheet.dart';
import '../../shared/ui.dart';

const _allCategory = 'Все';

IconData _catalogCategoryIcon(String category) {
  final normalized = category.trim().toLowerCase();
  if (normalized == _allCategory.toLowerCase()) return Icons.apps_outlined;
  if (normalized.contains('сантех')) return Icons.plumbing_outlined;
  if (normalized.contains('электр')) return Icons.electrical_services_outlined;
  if (normalized.contains('отдел') || normalized.contains('маляр')) {
    return Icons.format_paint_outlined;
  }
  if (normalized.contains('демонтаж')) return Icons.delete_sweep_outlined;
  if (normalized.contains('монтаж')) return Icons.construction_outlined;
  if (normalized.contains('плит')) return Icons.grid_view_outlined;
  if (normalized.contains('пол')) return Icons.square_foot_outlined;
  if (normalized.contains('потол')) return Icons.view_stream_outlined;
  if (normalized.contains('двер')) return Icons.door_front_door_outlined;
  if (normalized.contains('окн')) return Icons.window_outlined;
  if (normalized.contains('кондиц') || normalized.contains('вент')) {
    return Icons.ac_unit_outlined;
  }
  if (normalized.contains('слаботоч') || normalized.contains('интернет')) {
    return Icons.settings_input_antenna_outlined;
  }
  return Icons.handyman_outlined;
}

/// Обёртка маршрута: на десктопе — вкладка в shell, на телефоне — отдельный экран.
class CatalogRoute extends StatelessWidget {
  const CatalogRoute({super.key});

  @override
  Widget build(BuildContext context) {
    const screen = CatalogScreen();
    return const AppShell(selectedIndex: 2, child: screen);
  }
}

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String _query = '';
  String _category = _allCategory;
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final catalogData = ref.watch(catalogDataProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;
    final canPop = context.canPop();

    return Scaffold(
      appBar: isDesktop && !canPop
          ? null
          : AppBar(
              leading: canPop && !isDesktop
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.pop(),
                    )
                  : null,
              actions: [
                IconButton(
                  tooltip: 'Поделиться',
                  onPressed: _sharing ? null : () => _shareCatalog(catalogData),
                  icon: _sharing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share),
                ),
                IconButton(
                  tooltip: 'Добавить',
                  onPressed: _showAddMenuSheet,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
      floatingActionButton: null,
      body: RefreshIndicator(
        onRefresh: _refreshCatalog,
        child: _buildCatalogBody(catalogData, isDesktop),
      ),
    );
  }

  Widget _buildCatalogBody(
    AsyncValue<CatalogData> catalogData,
    bool isDesktop,
  ) {
    final padding = EdgeInsets.fromLTRB(
      isDesktop ? 20 : 16,
      isDesktop ? 20 : 12,
      isDesktop ? 20 : 16,
      96,
    );

    Widget bounded(Widget child) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: SizedBox(width: double.infinity, child: child),
        ),
      );
    }

    return catalogData.when(
      skipLoadingOnReload: true,
      data: (data) {
        final categories = data.categories;
        if (_category != _allCategory && !categories.contains(_category)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _category = _allCategory);
          });
        }

        final filtered = data.items.where((item) {
          final haystack = '${item.title} ${item.category}'.toLowerCase();
          final matchesQuery = haystack.contains(_query);
          final matchesCategory =
              _category == _allCategory || item.category == _category;
          return matchesQuery && matchesCategory;
        }).toList();
        final entries = _catalogEntries(filtered, isDesktop);
        final isEmpty = filtered.isEmpty;

        return ListView.builder(
          padding: padding,
          itemCount: isEmpty ? 2 : entries.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return bounded(
                _CatalogHeader(
                  isDesktop: isDesktop,
                  sharing: _sharing,
                  categories: categories,
                  selectedCategory: _category,
                  onSearchChanged: (value) {
                    setState(() => _query = value.trim().toLowerCase());
                  },
                  onShare: () => _shareCatalog(catalogData),
                  onAddCategory: _showCategorySheet,
                  onAddWork: () => _showWorkSheet(null),
                  onCategorySelected: (value) =>
                      setState(() => _category = value),
                ),
              );
            }

            if (isEmpty) {
              return bounded(
                SizedBox(
                  height: 280,
                  child: EmptyState(
                    icon: Icons.build_outlined,
                    title: 'Работы не найдены',
                    body: data.items.isEmpty
                        ? 'Добавьте услугу или подождите загрузку каталога.'
                        : 'Измените поиск или фильтр раздела.',
                    action: FilledButton.icon(
                      onPressed: () => _showWorkSheet(null),
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить услугу'),
                    ),
                  ),
                ),
              );
            }

            return bounded(_buildCatalogEntry(entries[index - 1]));
          },
        );
      },
      loading: () => ListView(
        padding: padding,
        children: [
          bounded(
            _CatalogHeader(
              isDesktop: isDesktop,
              sharing: _sharing,
              categories: const [],
              selectedCategory: _category,
              onSearchChanged: (value) {
                setState(() => _query = value.trim().toLowerCase());
              },
              onShare: () => _shareCatalog(catalogData),
              onAddCategory: _showCategorySheet,
              onAddWork: () => _showWorkSheet(null),
              onCategorySelected: (value) => setState(() => _category = value),
            ),
          ),
          const SizedBox(height: 12),
          bounded(const _CatalogSkeleton()),
        ],
      ),
      error: (error, _) => ListView(
        padding: padding,
        children: [
          bounded(
            _CatalogHeader(
              isDesktop: isDesktop,
              sharing: _sharing,
              categories: const [],
              selectedCategory: _category,
              onSearchChanged: (value) {
                setState(() => _query = value.trim().toLowerCase());
              },
              onShare: () => _shareCatalog(catalogData),
              onAddCategory: _showCategorySheet,
              onAddWork: () => _showWorkSheet(null),
              onCategorySelected: (value) => setState(() => _category = value),
            ),
          ),
          const SizedBox(height: 12),
          bounded(ErrorPane(error: error)),
        ],
      ),
    );
  }

  List<_CatalogListEntry> _catalogEntries(
    List<CatalogItemModel> items,
    bool isDesktop,
  ) {
    final grouped = _groupByCategory(items);
    final entries = <_CatalogListEntry>[];
    for (final group in grouped.entries) {
      entries.add(_CatalogHeaderEntry(group.key));
      if (isDesktop) {
        for (var i = 0; i < group.value.length; i += 2) {
          entries.add(
            _CatalogPairEntry(
              first: group.value[i],
              second: i + 1 < group.value.length ? group.value[i + 1] : null,
            ),
          );
        }
      } else {
        for (final item in group.value) {
          entries.add(_CatalogItemEntry(item));
        }
      }
    }
    return entries;
  }

  Widget _buildCatalogEntry(_CatalogListEntry entry) {
    return switch (entry) {
      _CatalogHeaderEntry() => _CatalogSectionHeader(
        title: entry.title,
        icon: _catalogCategoryIcon(entry.title),
        onAdd: () => _showWorkSheet(null, entry.title),
        onDelete: () => _deleteCategory(entry.title),
      ),
      _CatalogItemEntry() => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _CatalogCard(
          item: entry.item,
          onEdit: () => _showWorkSheet(entry.item),
          onDelete: () => _deleteWork(entry.item),
        ),
      ),
      _CatalogPairEntry() => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _CatalogCard(
                item: entry.first,
                onEdit: () => _showWorkSheet(entry.first),
                onDelete: () => _deleteWork(entry.first),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: entry.second == null
                  ? const SizedBox.shrink()
                  : _CatalogCard(
                      item: entry.second!,
                      onEdit: () => _showWorkSheet(entry.second!),
                      onDelete: () => _deleteWork(entry.second!),
                    ),
            ),
          ],
        ),
      ),
    };
  }

  Map<String, List<CatalogItemModel>> _groupByCategory(
    List<CatalogItemModel> items,
  ) {
    final result = <String, List<CatalogItemModel>>{};
    for (final item in items) {
      result.putIfAbsent(item.category, () => []).add(item);
    }
    return result;
  }

  Future<void> _showAddMenuSheet() async {
    final action = await showModalBottomSheet<_CatalogAddAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      builder: (context) => const _CatalogAddSheet(),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _CatalogAddAction.work:
        await _showWorkSheet(null);
      case _CatalogAddAction.category:
        await _showCategorySheet();
    }
  }

  Future<void> _showCategorySheet() async {
    final controller = TextEditingController();
    final saved = await showFormSheet(
      context: context,
      title: 'Новый раздел',
      subtitle: 'Например: Кондиционеры, Электрика, Отделка',
      confirmLabel: 'Создать',
      fields: [
        TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Название раздела',
            hintText: 'Кондиционеры',
          ),
          onSubmitted: (_) => Navigator.pop(context, true),
        ),
      ],
    );

    final title = controller.text.trim();
    controller.dispose();
    if (saved != true || title.isEmpty) return;

    await ref.read(repositoryProvider).saveCatalogCategory(title);
    await _refreshCatalog();
    if (!mounted) return;
    setState(() => _category = _normalizeCategoryTitle(title));
  }

  Future<void> _showWorkSheet(
    CatalogItemModel? item, [
    String? initialCategory,
  ]) async {
    final categories = (await ref.read(catalogDataProvider.future)).categories;
    if (!mounted) return;

    final title = TextEditingController(text: item?.title ?? '');
    final unit = TextEditingController(text: item?.unit ?? 'шт');
    final price = TextEditingController(
      text: item == null ? '' : item.unitPrice.toStringAsFixed(0),
    );
    var category =
        item?.category ??
        initialCategory ??
        (_category == _allCategory ? null : _category) ??
        (categories.isEmpty ? 'Сантехника' : categories.first);

    if (!categories.contains(category)) {
      await ref.read(repositoryProvider).saveCatalogCategory(category);
      await _refreshCatalog();
      if (!mounted) return;
    }

    final allCategories = {...categories, category}.toList()..sort();

    final saved = await showFormSheet(
      context: context,
      title: item == null ? 'Новая услуга' : 'Редактировать услугу',
      subtitle: item == null
          ? 'Добавьте работу с ценой в прайс-лист'
          : 'Измените название, раздел или цену',
      fields: [
        StatefulBuilder(
          builder: (context, setSheetState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: title,
                autofocus: item == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  hintText: 'Монтаж радиатора',
                ),
              ),
              const SizedBox(height: 12),
              CategoryPicker(
                categories: allCategories,
                selected: category,
                onSelected: (value) => setSheetState(() => category = value),
              ),
              const SizedBox(height: 12),
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
                    flex: 2,
                    child: TextField(
                      controller: price,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Цена',
                        suffixText: '₽',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final parsedPrice = double.tryParse(price.text.replaceAll(',', '.')) ?? 0;
    if (saved == true && title.text.trim().isNotEmpty) {
      final repository = ref.read(repositoryProvider);
      if (item == null) {
        await repository.saveCatalogItem(
          category: category,
          title: title.text,
          unit: unit.text.trim().isEmpty ? 'шт' : unit.text,
          unitPrice: parsedPrice,
        );
      } else {
        await repository.saveCatalogItemFromExisting(
          item: item,
          category: category,
          title: title.text,
          unit: unit.text.trim().isEmpty ? 'шт' : unit.text,
          unitPrice: parsedPrice,
        );
      }
      await _refreshCatalog();
      if (mounted) setState(() => _category = category);
    }

    title.dispose();
    unit.dispose();
    price.dispose();
  }

  Future<void> _deleteCategory(String category) async {
    final confirmed = await showConfirmSheet(
      context: context,
      title: 'Удалить раздел?',
      message:
          'Раздел «$category» и пользовательские услуги внутри него будут скрыты из каталога.',
    );
    if (!confirmed) return;

    await ref.read(repositoryProvider).deleteCatalogCategory(category);
    await _refreshCatalog();
    if (mounted) setState(() => _category = _allCategory);
  }

  Future<void> _deleteWork(CatalogItemModel item) async {
    final confirmed = await showConfirmSheet(
      context: context,
      title: 'Удалить услугу?',
      message: '«${item.title}» больше не будет показываться в каталоге.',
    );
    if (!confirmed) return;

    await ref.read(repositoryProvider).deleteCatalogItem(item);
    await _refreshCatalog();
  }

  Future<void> _shareCatalog(AsyncValue<CatalogData> catalog) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final CatalogData data =
          catalog.asData?.value ?? await ref.read(catalogDataProvider.future);
      final items = data.items;
      if (items.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Прайс-лист пуст — добавьте услуги')),
        );
        return;
      }

      final profile = await ref.read(profileProvider.future);
      final bytes = await PdfService.buildCatalogPdf(
        items: _category == _allCategory
            ? items
            : items.where((i) => i.category == _category).toList(),
        profile: profile,
      );
      final filename = 'prajs-list.pdf';
      await SharePlus.instance.share(
        ShareParams(
          title: 'Прайс-лист',
          text: _shareText(profile),
          files: [
            XFile.fromData(bytes, mimeType: 'application/pdf', name: filename),
          ],
          fileNameOverrides: [filename],
          downloadFallbackEnabled: true,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _shareText(ProfileModel? profile) {
    final name = profile?.fullName.trim();
    final greeting = name?.isNotEmpty == true ? 'От $name.' : '';
    return '$greeting Направляю прайс-лист на работы. PDF во вложении.';
  }

  Future<void> _refreshCatalog() async {
    ref.invalidate(catalogDataProvider);
  }

  String _normalizeCategoryTitle(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    return '${lower.substring(0, 1).toUpperCase()}${lower.substring(1)}';
  }
}

sealed class _CatalogListEntry {
  const _CatalogListEntry();
}

class _CatalogHeaderEntry extends _CatalogListEntry {
  const _CatalogHeaderEntry(this.title);

  final String title;
}

class _CatalogItemEntry extends _CatalogListEntry {
  const _CatalogItemEntry(this.item);

  final CatalogItemModel item;
}

class _CatalogPairEntry extends _CatalogListEntry {
  const _CatalogPairEntry({required this.first, this.second});

  final CatalogItemModel first;
  final CatalogItemModel? second;
}

enum _CatalogAddAction { work, category }

class _CatalogAddSheet extends StatelessWidget {
  const _CatalogAddSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.graphite,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Добавить в прайс',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _CatalogAddTile(
                  title: 'Новая услуга',
                  subtitle: 'Работа, единица измерения и цена',
                  icon: Icons.handyman_outlined,
                  iconColor: AppColors.orange,
                  backgroundColor: AppColors.orangeLight,
                  onTap: () => Navigator.pop(context, _CatalogAddAction.work),
                ),
                const SizedBox(height: 8),
                _CatalogAddTile(
                  title: 'Новый раздел',
                  subtitle: 'Группа для услуг: сантехника, отделка и т.д.',
                  icon: Icons.create_new_folder_outlined,
                  iconColor: Colors.white,
                  backgroundColor: AppColors.graphite,
                  onTap: () =>
                      Navigator.pop(context, _CatalogAddAction.category),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogAddTile extends StatelessWidget {
  const _CatalogAddTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  const _CatalogHeader({
    required this.isDesktop,
    required this.sharing,
    required this.categories,
    required this.selectedCategory,
    required this.onSearchChanged,
    required this.onShare,
    required this.onAddCategory,
    required this.onAddWork,
    required this.onCategorySelected,
  });

  final bool isDesktop;
  final bool sharing;
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onShare;
  final VoidCallback onAddCategory;
  final VoidCallback onAddWork;
  final ValueChanged<String> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenTitle(
          title: 'Прайс-лист',
          subtitle: 'Услуги, разделы и цены для быстрых смет',
          icon: Icons.construction_outlined,
          actions: isDesktop
              ? [
                  SizedBox(
                    width: 174,
                    child: OutlinedButton.icon(
                      onPressed: sharing ? null : onShare,
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text(
                        'Поделиться',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 128,
                    child: FilledButton.icon(
                      onPressed: onAddCategory,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      label: const Text('Раздел'),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: FilledButton.icon(
                      onPressed: onAddWork,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Услуга'),
                    ),
                  ),
                ]
              : const [],
        ),
        const SizedBox(height: 14),
        _CatalogToolbar(onSearchChanged: onSearchChanged),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CategoryChips(
            categories: categories,
            selected: selectedCategory,
            onSelected: onCategorySelected,
            onAddCategory: onAddCategory,
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < 5; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 72 + i * 12.0,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < 4; i++) ...[
          Container(
            height: 18,
            width: 120,
            margin: const EdgeInsets.only(bottom: 8, top: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          for (var j = 0; j < 2; j++)
            Container(
              height: 72,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
            ),
        ],
      ],
    );
  }
}

class _CatalogToolbar extends StatelessWidget {
  const _CatalogToolbar({required this.onSearchChanged});

  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: const InputDecoration(
        hintText: 'Поиск услуги',
        prefixIcon: Icon(Icons.search),
      ),
      onChanged: onSearchChanged,
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
    required this.onAddCategory,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onAddCategory;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return SmetchikCard(
        onTap: onAddCategory,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.create_new_folder_outlined,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Создайте первый раздел',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Разделы помогают сгруппировать услуги',
                    style: TextStyle(color: AppColors.textHint, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textHint),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final category in [_allCategory, ...categories])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                selected: selected == category,
                avatar: Icon(
                  _catalogCategoryIcon(category),
                  size: 18,
                  color: selected == category
                      ? AppColors.orange
                      : AppColors.textSecondary,
                ),
                label: Text(category),
                onSelected: (_) => onSelected(category),
              ),
            ),
        ],
      ),
    );
  }
}

class _CatalogSectionHeader extends StatelessWidget {
  const _CatalogSectionHeader({
    required this.title,
    required this.icon,
    required this.onAdd,
    required this.onDelete,
  });

  final String title;
  final IconData icon;
  final VoidCallback onAdd;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppColors.orangeDark, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            tooltip: 'Добавить услугу в раздел',
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 22),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.orangeLight,
              foregroundColor: AppColors.orangeDark,
            ),
          ),
          IconButton(
            tooltip: 'Удалить раздел',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final CatalogItemModel item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      onTap: onEdit,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _catalogCategoryIcon(item.category),
              color: AppColors.orangeDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.unit} · ${item.isCustom ? 'ваша цена' : 'базовая'}',
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(item.unitPrice),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          IconButton(
            tooltip: 'Удалить',
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 18),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.textHint,
              minimumSize: const Size(32, 32),
            ),
          ),
        ],
      ),
    );
  }
}
