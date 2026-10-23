import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_error.dart';
import '../../core/app_theme.dart';
import '../../data/repository.dart';
import '../../data/room_calculator.dart';
import '../../data/room_export_service.dart';
import '../../data/room_repository.dart';
import '../../shared/form_sheet.dart';
import '../../shared/ui.dart';
import '../../shared/upgrade_sheet.dart';
import 'room_editor_screen.dart';
import 'room_plan_view.dart';

class ProjectRoomsScreen extends ConsumerStatefulWidget {
  const ProjectRoomsScreen({super.key, required this.projectId});
  final String projectId;
  @override
  ConsumerState<ProjectRoomsScreen> createState() => _ProjectRoomsScreenState();
}

class _ProjectRoomsScreenState extends ConsumerState<ProjectRoomsScreen> {
  bool _summary = false, _busy = false;
  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(projectRoomsProvider(widget.projectId));
    final project = ref
        .watch(projectDetailProvider(widget.projectId))
        .asData
        ?.value
        .project;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Помещения и расчёты',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          tooltip: 'Назад к объекту',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/projects/${widget.projectId}');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить помещения',
            onPressed: _busy
                ? null
                : () => ref.invalidate(projectRoomsProvider(widget.projectId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: rooms.when(
        loading: () => const LoadingPane(),
        error: (e, _) => ErrorPane(error: e),
        data: (items) {
          final requirements = RoomCalculator.summarize(items);
          final area = items.fold<double>(
            0,
            (s, r) => s + RoomGeometry(r).floorArea,
          );
          return ResponsiveListView(
            maxWidth: 900,
            children: [
              if (project != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    project.title,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${items.length} помещ. · ${roomNumber(area)} м²',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Площадь пола по всем помещениям',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Добавить помещение',
                    onPressed: _busy ? null : () => _edit(),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.graphite,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ViewSwitch(
                value: _summary,
                onChanged: (v) => setState(() => _summary = v),
              ),
              const SizedBox(height: 20),
              if (!_summary && items.isEmpty)
                EmptyState(
                  icon: Icons.meeting_room_outlined,
                  title: 'Начните с одного помещения',
                  body:
                      'Комната, коридор, гараж или любое другое пространство.',
                  action: FilledButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить помещение'),
                  ),
                ),
              if (!_summary)
                for (final room in items) ...[
                  _RoomCard(
                    room: room,
                    onOpen: () => _edit(room),
                    onDelete: _busy ? null : () => _delete(room),
                  ),
                  const SizedBox(height: 12),
                ],
              if (_summary && requirements.isEmpty)
                const EmptyState(
                  icon: Icons.calculate_outlined,
                  title: 'Ведомость пока пуста',
                  body: 'Добавьте расчёт отделки в помещение.',
                ),
              if (_summary && requirements.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'К закупке',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Скопировать ведомость',
                      onPressed: () => _copy(requirements),
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    IconButton(
                      tooltip: 'Экспортировать в Excel',
                      onPressed: _busy
                          ? null
                          : () => _export(items, project?.title ?? 'Объект'),
                      icon: const Icon(Icons.ios_share_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final requirement in requirements) ...[
                  _RequirementRow(requirement: requirement),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Одинаковые названия и параметры объединены; упаковки округлены после суммирования. '
                  'Разные цвета и артикулы указывайте отдельными материалами.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Предварительный расчёт. Перед закупкой сверьте расход с этикеткой и раскладкой. '
                  'Для обоев проёмы не уменьшают число полос; смещённый рисунок может потребовать дополнительный запас.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit([ProjectRoom? initial]) async {
    final room =
        initial ??
        ProjectRoom(
          id: const Uuid().v4(),
          name: '',
          walls: ProjectRoom.shape('rectangle'),
        );
    final repository = ref.read(roomRepositoryProvider);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RoomEditorScreen(
          initial: room,
          onSave: (room) => repository.save(widget.projectId, room),
        ),
      ),
    );
    if (mounted && saved == true) {
      ref.invalidate(projectRoomsProvider(widget.projectId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Помещение и расчёты сохранены')),
      );
    }
  }

  Future<void> _delete(ProjectRoom room) async {
    if (!await showConfirmSheet(
      context: context,
      title: 'Удалить помещение?',
      message:
          '${room.name}: план, проёмы и расчёты отделки будут удалены. Операции и покупки объекта останутся.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(roomRepositoryProvider).delete(widget.projectId, room);
      ref.invalidate(projectRoomsProvider(widget.projectId));
    } catch (e) {
      if (mounted) showAppErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(List<MaterialRequirement> requirements) async {
    final text = requirements
        .map(
          (r) =>
              '${r.finish.name}: ${r.packages} ${r.finish.kind.unit}\n'
              '${RoomExportService.specification(r.finish)}\n'
              '${r.items.map((i) => '${i.roomName} / ${i.finish.surface.label}: ${roomNumber(i.area)} м², '
                  'запас ${roomNumber(i.finish.waste)}%').join('\n')}',
        )
        .join('\n\n');
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ведомость скопирована')),
        );
      }
    } catch (e) {
      if (mounted) showAppErrorSnackBar(context, e);
    }
  }

  Future<void> _export(List<ProjectRoom> rooms, String title) async {
    setState(() => _busy = true);
    try {
      final profile = await ref.read(profileProvider.future);
      if (!mounted) return;
      if (profile?.hasActivePro != true) {
        await showUpgradeSheet(
          context: context,
          message: 'Экспорт объектов в Excel доступен в Профи и Бригаде.',
          onOpenPlans: () => context.go('/settings?plans=1'),
        );
        return;
      }
      final bytes = RoomExportService.workbook(title, rooms);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              name: 'materialy.xlsx',
            ),
          ],
          fileNameOverrides: ['materialy.xlsx'],
          downloadFallbackEnabled: true,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      if (mounted) showAppErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        for (final v in [false, true])
          Expanded(
            child: Semantics(
              selected: value == v,
              button: true,
              child: InkWell(
                onTap: () => onChanged(v),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: value == v ? AppColors.graphite : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    v ? 'Ведомость' : 'Помещения',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: value == v
                          ? Colors.white
                          : AppColors.textSecondary,
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

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onOpen, this.onDelete});
  final ProjectRoom room;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: RoomPlanView(room: room, compact: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${roomNumber(RoomGeometry(room).floorArea)} м² · ${room.finishes.length} расч.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Удалить помещение',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textHint),
          ],
        ),
      ),
    ),
  );
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.requirement});
  final MaterialRequirement requirement;
  @override
  Widget build(BuildContext context) {
    final f = requirement.finish;
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Text(
          f.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${requirement.packages} ${f.kind.unit} · ${roomNumber(requirement.area)} м²',
            style: const TextStyle(
              color: AppColors.orangeDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              RoomExportService.specification(f),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in requirement.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${item.roomName} · ${item.finish.surface.label}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${roomNumber(item.amount)} ${item.amountUnit}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
