import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import 'models.dart';
import 'repository.dart';

final offlineSyncProvider = ChangeNotifierProvider<OfflineSyncController>((
  ref,
) {
  final controller = OfflineSyncController(
    repository: ref.read(repositoryProvider),
    onSynced: () {
      ref.invalidate(estimatesProvider);
      ref.invalidate(projectsProvider);
      ref.invalidate(clientsProvider);
    },
  );
  controller.start();
  ref.onDispose(controller.dispose);
  return controller;
});

class OfflineDraftKind {
  const OfflineDraftKind._();

  static const estimate = 'estimate';
  static const project = 'project';
}

class OfflineDraftEntry {
  const OfflineDraftEntry({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
  });

  final String id;
  final String kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastError;

  EstimateDraft get estimateDraft => _estimateDraftFromMap(payload);
  ProjectDraft get projectDraft => _projectDraftFromMap(payload);

  OfflineDraftEntry copyWith({
    Map<String, dynamic>? payload,
    DateTime? updatedAt,
    String? lastError,
    bool clearLastError = false,
  }) {
    return OfflineDraftEntry(
      id: id,
      kind: kind,
      payload: payload ?? this.payload,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'kind': kind,
    'payload': payload,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'last_error': lastError,
  };

  factory OfflineDraftEntry.fromMap(Map<String, dynamic> map) {
    final payload = map['payload'];
    return OfflineDraftEntry(
      id: map['id'] as String,
      kind: map['kind'] as String,
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : const <String, dynamic>{},
      createdAt: _dateFromValue(map['created_at']),
      updatedAt: _dateFromValue(map['updated_at']),
      lastError: map['last_error'] as String?,
    );
  }
}

class OfflineSyncController extends ChangeNotifier with WidgetsBindingObserver {
  OfflineSyncController({required this.repository, required this.onSynced});

  static const _storagePrefix = 'smetchik.offline-queue.v1';
  static const _retryInterval = Duration(seconds: 20);

  final SmetchikRepository repository;
  final VoidCallback onSynced;
  final List<OfflineDraftEntry> _entries = [];

  Timer? _retryTimer;
  String? _loadedUserId;
  bool _ready = false;
  bool _syncing = false;

  bool get isReady => _ready;
  bool get isSyncing => _syncing;
  List<OfflineDraftEntry> get entries => List.unmodifiable(_entries);
  List<OfflineDraftEntry> get estimateEntries => entries
      .where((entry) => entry.kind == OfflineDraftKind.estimate)
      .toList();
  List<OfflineDraftEntry> get projectEntries =>
      entries.where((entry) => entry.kind == OfflineDraftKind.project).toList();
  int get pendingCount => _entries.length;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _retryTimer = Timer.periodic(_retryInterval, (_) => sync());
    unawaited(ensureLoaded().then((_) => sync()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(sync());
    }
  }

  Future<void> ensureLoaded() async {
    final userId = _currentUserId;
    if (userId == _loadedUserId && _ready) return;

    _loadedUserId = userId;
    _entries.clear();
    _ready = false;
    notifyListeners();

    if (userId == null) {
      _ready = true;
      notifyListeners();
      return;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_storageKey(userId));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _entries.addAll(
            decoded
                .whereType<Map>()
                .map(
                  (item) => OfflineDraftEntry.fromMap(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .where(_isSupportedEntry),
          );
        }
      }
    } catch (_) {
      // A malformed local queue must not prevent the app from opening.
    } finally {
      _ready = true;
      notifyListeners();
    }
  }

  Future<OfflineDraftEntry?> estimateById(String id) async {
    await ensureLoaded();
    return _entryById(id, OfflineDraftKind.estimate);
  }

  Future<OfflineDraftEntry?> projectById(String id) async {
    await ensureLoaded();
    return _entryById(id, OfflineDraftKind.project);
  }

  Future<void> queueEstimate(EstimateDraft draft, {String? id}) async {
    await _upsert(
      kind: OfflineDraftKind.estimate,
      id: id,
      payload: _estimateDraftToMap(draft),
    );
  }

  Future<void> queueProject(ProjectDraft draft, {String? id}) async {
    await _upsert(
      kind: OfflineDraftKind.project,
      id: id,
      payload: _projectDraftToMap(draft),
    );
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    final before = _entries.length;
    _entries.removeWhere((entry) => entry.id == id);
    if (_entries.length == before) return;
    await _persist();
    notifyListeners();
  }

  Future<void> retryNow() async {
    for (var index = 0; index < _entries.length; index++) {
      final entry = _entries[index];
      if (entry.lastError != null) {
        _entries[index] = entry.copyWith(clearLastError: true);
      }
    }
    await _persist();
    notifyListeners();
    await sync();
  }

  Future<void> sync() async {
    await ensureLoaded();
    if (_syncing || _entries.isEmpty || _currentUserId == null) return;

    _syncing = true;
    notifyListeners();
    var changed = false;
    var synced = false;
    try {
      for (var index = 0; index < _entries.length;) {
        final entry = _entries[index];
        if (entry.lastError != null) {
          index++;
          continue;
        }
        try {
          if (entry.kind == OfflineDraftKind.estimate) {
            await repository.saveEstimateDraft(entry.estimateDraft);
          } else if (entry.kind == OfflineDraftKind.project) {
            await repository.saveProject(entry.projectDraft);
          }
          _entries.removeAt(index);
          changed = true;
          synced = true;
        } catch (error) {
          if (isRecoverableNetworkError(error)) break;
          _entries[index] = entry.copyWith(
            lastError: _errorMessage(error),
            updatedAt: DateTime.now(),
          );
          changed = true;
          index++;
        }
      }
      if (changed) {
        await _persist();
      }
      if (synced) {
        onSynced();
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _upsert({
    required String kind,
    required Map<String, dynamic> payload,
    String? id,
  }) async {
    await ensureLoaded();
    if (_currentUserId == null) {
      throw const AuthException('Войдите в аккаунт, чтобы сохранить черновик.');
    }
    final now = DateTime.now();
    final existingIndex = id == null
        ? -1
        : _entries.indexWhere((entry) => entry.id == id && entry.kind == kind);
    if (existingIndex >= 0) {
      _entries[existingIndex] = _entries[existingIndex].copyWith(
        payload: payload,
        updatedAt: now,
        clearLastError: true,
      );
    } else {
      _entries.add(
        OfflineDraftEntry(
          id: id ?? const Uuid().v4(),
          kind: kind,
          payload: payload,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await _persist();
    notifyListeners();
    unawaited(sync());
  }

  OfflineDraftEntry? _entryById(String id, String kind) {
    for (final entry in _entries) {
      if (entry.id == id && entry.kind == kind) return entry;
    }
    return null;
  }

  Future<void> _persist() async {
    final userId = _loadedUserId;
    if (userId == null) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _storageKey(userId),
        jsonEncode(_entries.map((entry) => entry.toMap()).toList()),
      );
    } catch (_) {
      // The in-memory draft remains available for the current session.
    }
  }

  String? get _currentUserId {
    if (!AppConfig.hasSupabaseConfig) return null;
    return Supabase.instance.client.auth.currentUser?.id;
  }

  String _storageKey(String userId) => '$_storagePrefix.$userId';

  bool _isSupportedEntry(OfflineDraftEntry entry) {
    return entry.kind == OfflineDraftKind.estimate ||
        entry.kind == OfflineDraftKind.project;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    super.dispose();
  }
}

bool isRecoverableNetworkError(Object error) {
  if (error is TimeoutException) return true;
  final message = error.toString().toLowerCase();
  return message.contains('socketexception') ||
      message.contains('clientexception') ||
      message.contains('authretryablefetchexception') ||
      message.contains('failed host lookup') ||
      message.contains('failed to fetch') ||
      message.contains('network request failed') ||
      message.contains('network is unreachable') ||
      message.contains('connection refused') ||
      message.contains('connection reset') ||
      message.contains('timed out') ||
      message.contains('timeout');
}

Map<String, dynamic> _estimateDraftToMap(EstimateDraft draft) => {
  'object_title': draft.objectTitle,
  'client_id': draft.clientId,
  'client_name': draft.clientName,
  'client_phone': draft.clientPhone,
  'estimate_date': draft.estimateDate.toIso8601String(),
  'duration_days': draft.durationDays,
  'lines': draft.lines
      .map(
        (line) => {
          'id': line.id,
          'catalog_item_id': line.catalogItemId,
          'title': line.title,
          'unit': line.unit,
          'quantity': line.quantity,
          'unit_price': line.unitPrice,
          'line_total': line.lineTotal,
          'sort_order': line.sortOrder,
        },
      )
      .toList(),
};

EstimateDraft _estimateDraftFromMap(Map<String, dynamic> map) {
  final rawLines = map['lines'];
  final lines = rawLines is List
      ? rawLines.whereType<Map>().map((item) {
          final line = Map<String, dynamic>.from(item);
          final quantity = _doubleFromValue(line['quantity']);
          final unitPrice = _doubleFromValue(line['unit_price']);
          return EstimateLineModel(
            id: (line['id'] as String?) ?? const Uuid().v4(),
            catalogItemId: line['catalog_item_id'] as String?,
            title: (line['title'] as String?) ?? '',
            unit: (line['unit'] as String?) ?? 'шт',
            quantity: quantity,
            unitPrice: unitPrice,
            lineTotal: _doubleFromValue(line['line_total']) == 0
                ? quantity * unitPrice
                : _doubleFromValue(line['line_total']),
            sortOrder: _intFromValue(line['sort_order']),
          );
        }).toList()
      : const <EstimateLineModel>[];
  return EstimateDraft(
    objectTitle: (map['object_title'] as String?) ?? '',
    clientId: map['client_id'] as String?,
    clientName: (map['client_name'] as String?) ?? '',
    clientPhone: map['client_phone'] as String?,
    estimateDate: _dateFromValue(map['estimate_date']),
    durationDays: map['duration_days'] == null
        ? null
        : _intFromValue(map['duration_days']),
    lines: lines,
  );
}

Map<String, dynamic> _projectDraftToMap(ProjectDraft draft) => {
  'title': draft.title,
  'object_address': draft.objectAddress,
  'customer_name': draft.customerName,
  'planned_revenue': draft.plannedRevenue,
  'start_date': draft.startDate.toIso8601String(),
  'target_date': draft.targetDate?.toIso8601String(),
  'status': draft.status,
  'notes': draft.notes,
};

ProjectDraft _projectDraftFromMap(Map<String, dynamic> map) => ProjectDraft(
  title: (map['title'] as String?) ?? '',
  objectAddress: map['object_address'] as String?,
  customerName: map['customer_name'] as String?,
  plannedRevenue: _doubleFromValue(map['planned_revenue']),
  startDate: _dateFromValue(map['start_date']),
  targetDate: map['target_date'] == null
      ? null
      : _dateFromValue(map['target_date']),
  status: (map['status'] as String?) ?? ProjectStatus.planning,
  notes: map['notes'] as String?,
);

DateTime _dateFromValue(Object? value) {
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

double _doubleFromValue(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.')) ?? 0;
  return 0;
}

int _intFromValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String _errorMessage(Object error) => error
    .toString()
    .replaceFirst('Exception: ', '')
    .replaceFirst('AuthException(message: ', '')
    .replaceFirst(', statusCode: null)', '');
