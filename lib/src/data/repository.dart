import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import 'local_data_cache.dart';
import 'models.dart';
import 'signing.dart';

final repositoryProvider = Provider<SmetchikRepository>((ref) {
  if (!AppConfig.hasSupabaseConfig) {
    throw StateError('Supabase is not configured.');
  }
  return SmetchikRepository(Supabase.instance.client);
});

final profileProvider = FutureProvider<ProfileModel?>((ref) {
  return ref.watch(repositoryProvider).fetchProfile();
});

final clientsProvider = FutureProvider<List<ClientModel>>((ref) {
  return ref.watch(repositoryProvider).fetchClients();
});

final catalogDataProvider = FutureProvider<CatalogData>((ref) {
  ref.keepAlive();
  return ref.watch(repositoryProvider).fetchCatalogData();
});

final catalogItemsProvider = FutureProvider<List<CatalogItemModel>>((
  ref,
) async {
  return (await ref.watch(catalogDataProvider.future)).items;
});

final catalogCategoriesProvider = FutureProvider<List<String>>((ref) async {
  return (await ref.watch(catalogDataProvider.future)).categories;
});

final estimatesProvider = FutureProvider<List<EstimateModel>>((ref) {
  return ref.watch(repositoryProvider).fetchEstimates();
});

final projectsProvider = FutureProvider<List<ProjectModel>>((ref) {
  return ref.watch(repositoryProvider).fetchProjects();
});

final projectDetailProvider = FutureProvider.family<ProjectDetail, String>(
  (ref, id) => ref.watch(repositoryProvider).fetchProjectDetail(id),
);

final teamWorkspaceProvider = FutureProvider<TeamWorkspaceModel?>((ref) {
  return ref.watch(repositoryProvider).fetchTeamWorkspace();
});

final teamMembersProvider = FutureProvider<List<TeamMemberModel>>((ref) {
  return ref.watch(repositoryProvider).fetchTeamMembers();
});

final teamInvitesProvider = FutureProvider<List<TeamInviteModel>>((ref) {
  return ref.watch(repositoryProvider).fetchTeamInvites();
});

final incomingTeamInvitesProvider =
    FutureProvider<List<IncomingTeamInviteModel>>((ref) {
      return ref.watch(repositoryProvider).fetchIncomingTeamInvites();
    });

final estimateDetailProvider = FutureProvider.family<EstimateDetail, String>((
  ref,
  id,
) {
  return ref.watch(repositoryProvider).fetchEstimateDetail(id);
});

class SmetchikRepository {
  const SmetchikRepository(this._client);

  final SupabaseClient _client;
  static const _localCache = LocalDataCache();

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Пользователь не авторизован');
    return id;
  }

  Future<ProfileModel?> fetchProfile() async {
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', _userId)
          .maybeSingle();
      if (data == null) return null;
      final map = Map<String, dynamic>.from(data);
      await _localCache.write(_cacheKey('profile'), map);
      return _profileFromMap(map);
    } catch (_) {
      final cached = await _localCache.readMap(_cacheKey('profile'));
      if (cached == null) rethrow;
      return _profileFromMap(cached);
    }
  }

  ProfileModel _profileFromMap(Map<String, dynamic> data) {
    final profile = ProfileModel.fromMap(data);
    return profile.copyWith(
      logoUrl: logoPublicUrl(profile.logoPath),
      signatureUrl: signaturePublicUrl(profile.signaturePath),
      paymentQrUrl: qrPublicUrl(profile.paymentQrPath),
      contactQrUrl: qrPublicUrl(profile.contactQrPath),
    );
  }

  String _cacheKey(String name) => 'smetchik.cache.v1.$_userId.$name';

  Future<void> saveProfile({
    required String fullName,
    String? phone,
    String? specialization,
    String? paymentQrLabel,
    String? contactQrLabel,
    String currency = 'RUB',
  }) async {
    await _client.from('profiles').upsert({
      'id': _userId,
      'full_name': fullName.trim(),
      'phone': _blankToNull(phone),
      'specialization': _blankToNull(specialization),
      'payment_qr_label': _blankToNull(paymentQrLabel),
      'contact_qr_label': _blankToNull(contactQrLabel),
      'currency': currency,
    });
  }

  Future<void> savePdfSettings({
    required bool showBrandHeader,
    required bool showSignatures,
    required bool showServiceMark,
    required String template,
    required String accentColor,
    String? paymentTerms,
    String? footerNote,
  }) async {
    final profile = await fetchProfile();
    if (profile?.hasActivePro != true) {
      throw Exception(
        'Настройки PDF доступны на тарифе Профи. Подключите Профи, чтобы менять оформление смет.',
      );
    }

    await _client
        .from('profiles')
        .update({
          'pdf_show_brand_header': showBrandHeader,
          'pdf_show_signatures': showSignatures,
          'pdf_show_service_mark': showServiceMark,
          'pdf_template': PdfTemplate.normalize(template),
          'pdf_accent_color': PdfAccentColor.normalize(accentColor),
          'pdf_payment_terms': _blankToNull(paymentTerms),
          'pdf_footer_note': _blankToNull(footerNote),
        })
        .eq('id', _userId);
  }

  Future<PromoRedemptionResult> redeemPromo({required String code}) async {
    final response = await _client.functions.invoke(
      'redeem-promo',
      body: {'code': code.trim()},
    );
    final data = _functionData(response.data);
    return PromoRedemptionResult(
      title: data['title'] as String?,
      plan: SubscriptionPlan.normalize(data['plan'] as String?),
      renewsAt: asDateOrNull(data['renewsAt']),
    );
  }

  String? logoPublicUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    return _client.storage.from('logos').getPublicUrl(path);
  }

  String? signaturePublicUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return _client.storage.from('signatures').getPublicUrl(path);
  }

  String? qrPublicUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return _client.storage.from('qr-codes').getPublicUrl(path);
  }

  String? clientSignaturePublicUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return _client.storage.from('client-signatures').getPublicUrl(path);
  }

  Future<String> uploadProfileAvatar({
    required Uint8List bytes,
    required String contentType,
  }) async {
    final extension = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final version = DateTime.now().millisecondsSinceEpoch;
    final path = '$_userId/avatar-$version.$extension';
    return _replaceProfileStorageAsset(
      bucket: 'logos',
      column: 'logo_path',
      path: path,
      bytes: bytes,
      contentType: contentType,
    );
  }

  Future<String> uploadProfileSignature({required Uint8List bytes}) async {
    final version = DateTime.now().millisecondsSinceEpoch;
    final path = '$_userId/signature-$version.png';
    return _replaceProfileStorageAsset(
      bucket: 'signatures',
      column: 'signature_path',
      path: path,
      bytes: bytes,
      contentType: 'image/png',
    );
  }

  Future<String> uploadProfileQr({
    required String kind,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final normalizedKind = kind == 'contact' ? 'contact' : 'payment';
    final extension = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final version = DateTime.now().millisecondsSinceEpoch;
    final path = '$_userId/$normalizedKind-qr-$version.$extension';
    final column = normalizedKind == 'contact'
        ? 'contact_qr_path'
        : 'payment_qr_path';
    return _replaceProfileStorageAsset(
      bucket: 'qr-codes',
      column: column,
      path: path,
      bytes: bytes,
      contentType: contentType,
    );
  }

  /// Replaces a mutable profile asset and frees its previous object only after
  /// the profile points at the new file. Final client signatures and PDFs use
  /// separate immutable storage paths and are deliberately never handled here.
  Future<String> _replaceProfileStorageAsset({
    required String bucket,
    required String column,
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final current = await _client
        .from('profiles')
        .select(column)
        .eq('id', _userId)
        .maybeSingle();
    final previousPath = current?[column] as String?;

    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: contentType,
            cacheControl: '31536000',
          ),
        );
    try {
      await _client.from('profiles').update({column: path}).eq('id', _userId);
    } catch (_) {
      await _removeStorageObject(bucket, path);
      rethrow;
    }

    if (previousPath != null &&
        previousPath != path &&
        !previousPath.startsWith('http://') &&
        !previousPath.startsWith('https://')) {
      await _removeStorageObject(bucket, previousPath);
    }
    return path;
  }

  Future<void> _removeStorageObject(String bucket, String path) async {
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (_) {
      // A replacement is already persisted. A failed cleanup must not make a
      // profile update look unsuccessful to the user.
    }
  }

  Future<List<ClientModel>> fetchClients() async {
    try {
      final rows = await _client
          .from('clients')
          .select()
          .eq('user_id', _userId)
          .order('created_at', ascending: false);
      final maps = _asMaps(rows);
      await _localCache.write(_cacheKey('clients'), maps);
      return maps.map(ClientModel.fromMap).toList();
    } catch (_) {
      final cached = await _localCache.readList(_cacheKey('clients'));
      if (cached == null) rethrow;
      return cached.map(ClientModel.fromMap).toList();
    }
  }

  Future<ClientModel> saveClient({
    String? id,
    required String name,
    String? phone,
    String? objectAddress,
    String? notes,
  }) async {
    if (id == null) {
      await _ensureCanCreateClient();
    }

    final payload = {
      'user_id': _userId,
      'name': name.trim(),
      'phone': _blankToNull(phone),
      'object_address': _blankToNull(objectAddress),
      'notes': _blankToNull(notes),
    };

    final Map<String, dynamic> row;
    if (id == null) {
      row = await _client.from('clients').insert(payload).select().single();
    } else {
      row = await _client
          .from('clients')
          .update(payload)
          .eq('id', id)
          .eq('user_id', _userId)
          .select()
          .single();
    }
    return ClientModel.fromMap(row);
  }

  Future<void> _ensureCanCreateClient() async {
    final profile = await fetchProfile();
    if (profile?.hasActivePro == true) return;

    final limit = profile?.clientLimit ?? ProfileModel.basicClientLimit;
    final count = await countClients();
    if (count >= limit) {
      throw Exception(
        'Лимит базового тарифа: $limit клиентов. Подключите Профи, чтобы вести клиентскую базу без ограничений.',
      );
    }
  }

  Future<int> countClients() async {
    final rows = await _client
        .from('clients')
        .select('id')
        .eq('user_id', _userId);
    return rows.length;
  }

  Future<CatalogData> fetchCatalogData() async {
    try {
      final data = await _fetchCatalogDataRemote();
      await _localCache.write(_cacheKey('catalog'), {
        'items': [for (final item in data.items) _catalogItemToMap(item)],
        'categories': data.categories,
        'category_icons': data.categoryIcons,
      });
      return data;
    } catch (_) {
      final cached = await _localCache.readMap(_cacheKey('catalog'));
      if (cached == null) rethrow;
      return _catalogDataFromCache(cached);
    }
  }

  Future<CatalogData> _fetchCatalogDataRemote() async {
    final results = await Future.wait<dynamic>([
      _fetchHiddenCatalogCategories(),
      _fetchHiddenCatalogItemKeys(),
      _client
          .from('catalog_items')
          .select()
          .or('user_id.is.null,user_id.eq.$_userId')
          .order('is_custom', ascending: true)
          .order('category')
          .order('title'),
      _fetchUserCatalogCategoryRows(),
    ]);

    final hiddenCategories = results[0] as Set<String>;
    final hiddenItems = results[1] as Set<String>;
    final itemRows = results[2] as List;
    final customRows = results[3] as List;

    final merged = <String, CatalogItemModel>{};
    final categories = <String>{};
    final categoryIcons = <String, String>{};

    for (final row in itemRows) {
      final item = CatalogItemModel.fromMap(row);
      final categoryKey = item.category.trim().toLowerCase();
      final itemKey = _catalogKey(item.category, item.title, item.unit);
      if (hiddenCategories.contains(categoryKey) ||
          hiddenItems.contains(itemKey)) {
        continue;
      }
      final existing = merged[itemKey];
      if (existing == null ||
          (item.userId != null && existing.userId == null)) {
        merged[itemKey] = item;
      }
      categories.add(item.category);
    }

    for (final row in customRows) {
      final category = (row['title'] as String?)?.trim();
      final hidden = (row['is_hidden'] as bool?) ?? false;
      if (category == null || category.isEmpty) continue;
      if (hidden) {
        categories.removeWhere(
          (value) => value.toLowerCase() == category.toLowerCase(),
        );
      } else {
        categories.add(category);
        final iconKey = (row['icon_key'] as String?)?.trim();
        if (iconKey != null && iconKey.isNotEmpty) {
          categoryIcons[category] = iconKey;
        }
      }
    }

    final items = merged.values.toList()
      ..sort((a, b) {
        final category = a.category.compareTo(b.category);
        if (category != 0) return category;
        return a.title.compareTo(b.title);
      });

    final sortedCategories = categories.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return CatalogData(
      items: items,
      categories: sortedCategories,
      categoryIcons: categoryIcons,
    );
  }

  CatalogData _catalogDataFromCache(Map<String, dynamic> cached) {
    final itemRows = cached['items'];
    final categoryRows = cached['categories'];
    final iconRows = cached['category_icons'];
    return CatalogData(
      items: itemRows is List
          ? itemRows
                .whereType<Map>()
                .map(
                  (row) =>
                      CatalogItemModel.fromMap(Map<String, dynamic>.from(row)),
                )
                .toList()
          : const [],
      categories: categoryRows is List
          ? categoryRows.whereType<String>().toList()
          : const [],
      categoryIcons: iconRows is Map
          ? iconRows.map((key, value) => MapEntry('$key', '$value'))
          : const {},
    );
  }

  Map<String, dynamic> _catalogItemToMap(CatalogItemModel item) => {
    'id': item.id,
    'user_id': item.userId,
    'category': item.category,
    'title': item.title,
    'unit': item.unit,
    'unit_price': item.unitPrice,
    'is_custom': item.isCustom,
  };

  Future<List<CatalogItemModel>> fetchCatalogItems() async {
    return (await fetchCatalogData()).items;
  }

  Future<List<String>> fetchCatalogCategories() async {
    return (await fetchCatalogData()).categories;
  }

  Future<void> saveCatalogCategory(String title, {String? iconKey}) async {
    final normalized = _normalizeCatalogCategory(title);
    if (normalized.isEmpty) return;
    final normalizedIcon = _blankToNull(iconKey) ?? 'handyman';

    final existing = await _client
        .from('catalog_categories')
        .select('id')
        .eq('user_id', _userId)
        .eq('title', normalized)
        .maybeSingle();
    if (existing == null) {
      await _writeCatalogCategoryWithIcon({
        'user_id': _userId,
        'title': normalized,
        'is_hidden': false,
      }, iconKey: normalizedIcon);
    } else {
      await _updateCatalogCategoryWithIcon(existing['id'] as String, {
        'is_hidden': false,
      }, iconKey: normalizedIcon);
    }
  }

  Future<List<dynamic>> _fetchUserCatalogCategoryRows() async {
    try {
      return await _client
          .from('catalog_categories')
          .select('title,is_hidden,icon_key')
          .eq('user_id', _userId)
          .order('sort_order')
          .order('title');
    } on PostgrestException catch (error) {
      if (!_isMissingColumnError(error, 'icon_key')) rethrow;
      return _client
          .from('catalog_categories')
          .select('title,is_hidden')
          .eq('user_id', _userId)
          .order('sort_order')
          .order('title');
    }
  }

  Future<void> _writeCatalogCategoryWithIcon(
    Map<String, dynamic> payload, {
    required String iconKey,
  }) async {
    try {
      await _client.from('catalog_categories').insert({
        ...payload,
        'icon_key': iconKey,
      });
    } on PostgrestException catch (error) {
      if (!_isMissingColumnError(error, 'icon_key')) rethrow;
      await _client.from('catalog_categories').insert(payload);
    }
  }

  Future<void> _updateCatalogCategoryWithIcon(
    String id,
    Map<String, dynamic> payload, {
    required String iconKey,
  }) async {
    try {
      await _client
          .from('catalog_categories')
          .update({...payload, 'icon_key': iconKey})
          .eq('id', id)
          .eq('user_id', _userId);
    } on PostgrestException catch (error) {
      if (!_isMissingColumnError(error, 'icon_key')) rethrow;
      await _client
          .from('catalog_categories')
          .update(payload)
          .eq('id', id)
          .eq('user_id', _userId);
    }
  }

  bool _isMissingColumnError(PostgrestException error, String column) {
    return error.code == '42703' && error.message.contains(column);
  }

  Future<void> deleteCatalogCategory(String category) async {
    final normalized = _normalizeCatalogCategory(category);
    if (normalized.isEmpty) return;

    await _client
        .from('catalog_items')
        .delete()
        .eq('user_id', _userId)
        .eq('category', normalized);

    final existing = await _client
        .from('catalog_categories')
        .select('id')
        .eq('user_id', _userId)
        .eq('title', normalized)
        .maybeSingle();
    if (existing == null) {
      await _client.from('catalog_categories').insert({
        'user_id': _userId,
        'title': normalized,
        'is_hidden': true,
      });
    } else {
      await _client
          .from('catalog_categories')
          .update({'is_hidden': true})
          .eq('id', existing['id'])
          .eq('user_id', _userId);
    }
  }

  Future<CatalogItemModel> saveCatalogItem({
    String? id,
    required String category,
    required String title,
    required String unit,
    required double unitPrice,
  }) async {
    final payload = {
      'user_id': _userId,
      'category': _normalizeCatalogCategory(category),
      'title': title.trim(),
      'unit': unit.trim(),
      'unit_price': unitPrice,
      'is_custom': true,
    };

    final Map<String, dynamic> row;
    if (id != null) {
      row = await _client
          .from('catalog_items')
          .update(payload)
          .eq('id', id)
          .eq('user_id', _userId)
          .select()
          .single();
    } else {
      final existing = await _client
          .from('catalog_items')
          .select()
          .eq('user_id', _userId)
          .eq('category', _normalizeCatalogCategory(category))
          .eq('title', title.trim())
          .eq('unit', unit.trim())
          .maybeSingle();
      if (existing == null) {
        row = await _client
            .from('catalog_items')
            .insert(payload)
            .select()
            .single();
      } else {
        row = await _client
            .from('catalog_items')
            .update(payload)
            .eq('id', existing['id'])
            .eq('user_id', _userId)
            .select()
            .single();
      }
    }
    await _client
        .from('catalog_hidden_items')
        .delete()
        .eq('user_id', _userId)
        .eq('category', payload['category'] as String)
        .eq('title', payload['title'] as String)
        .eq('unit', payload['unit'] as String);
    return CatalogItemModel.fromMap(row);
  }

  Future<CatalogItemModel> saveCatalogItemFromExisting({
    required CatalogItemModel item,
    required String category,
    required String title,
    required String unit,
    required double unitPrice,
  }) {
    return saveCatalogItem(
      id: item.userId == _userId ? item.id : null,
      category: category,
      title: title,
      unit: unit,
      unitPrice: unitPrice,
    );
  }

  Future<void> deleteCatalogItem(CatalogItemModel item) async {
    if (item.userId == _userId) {
      await _client
          .from('catalog_items')
          .delete()
          .eq('id', item.id)
          .eq('user_id', _userId);
    }

    await _client.from('catalog_hidden_items').upsert({
      'user_id': _userId,
      'category': item.category,
      'title': item.title,
      'unit': item.unit,
    });
  }

  Future<List<ProjectModel>> fetchProjects() async {
    try {
      final rows = await _client
          .from('projects')
          .select()
          .eq('user_id', _userId)
          .order('updated_at', ascending: false);
      final transactionRows = await _client
          .from('project_transactions')
          .select('project_id, transaction_type, amount')
          .eq('user_id', _userId);
      final incomeByProject = <String, double>{};
      final expenseByProject = <String, double>{};
      for (final row in transactionRows) {
        final projectId = row['project_id'] as String?;
        if (projectId == null) continue;
        final amount = asDouble(row['amount']);
        if (ProjectTransactionType.normalize(
              row['transaction_type'] as String?,
            ) ==
            ProjectTransactionType.income) {
          incomeByProject[projectId] =
              (incomeByProject[projectId] ?? 0) + amount;
        } else {
          expenseByProject[projectId] =
              (expenseByProject[projectId] ?? 0) + amount;
        }
      }
      final cached = rows.map((row) {
        final map = Map<String, dynamic>.from(row);
        final id = map['id'] as String?;
        map['income_amount'] = id == null ? 0 : incomeByProject[id] ?? 0;
        map['expense_amount'] = id == null ? 0 : expenseByProject[id] ?? 0;
        return map;
      }).toList();
      await _localCache.write(_cacheKey('projects'), cached);
      return cached.map(ProjectModel.fromMap).toList();
    } catch (_) {
      final cached = await _localCache.readList(_cacheKey('projects'));
      if (cached == null) rethrow;
      return cached.map(ProjectModel.fromMap).toList();
    }
  }

  Future<ProjectDetail> fetchProjectDetail(String projectId) async {
    try {
      final projectRow = await _client
          .from('projects')
          .select()
          .eq('id', projectId)
          .eq('user_id', _userId)
          .single();
      final transactionRows = await _client
          .from('project_transactions')
          .select()
          .eq('project_id', projectId)
          .eq('user_id', _userId)
          .order('transaction_date', ascending: false)
          .order('created_at', ascending: false);
      final materialRows = await _client
          .from('project_materials')
          .select()
          .eq('project_id', projectId)
          .eq('user_id', _userId)
          .order('created_at', ascending: false);
      final data = {
        'project': Map<String, dynamic>.from(projectRow),
        'transactions': _asMaps(transactionRows),
        'materials': _asMaps(materialRows),
      };
      await _localCache.write(_cacheKey('project.$projectId'), data);
      return _projectDetailFromCache(data);
    } catch (_) {
      final cached = await _localCache.readMap(_cacheKey('project.$projectId'));
      if (cached == null) rethrow;
      return _projectDetailFromCache(cached);
    }
  }

  ProjectDetail _projectDetailFromCache(Map<String, dynamic> data) {
    final transactionRows = data['transactions'] is List
        ? (data['transactions'] as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const <Map<String, dynamic>>[];
    final transactions = transactionRows
        .map(ProjectTransactionModel.fromMap)
        .toList();
    final materialRows = data['materials'] is List
        ? (data['materials'] as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const <Map<String, dynamic>>[];
    final incomeAmount = transactions
        .where((item) => item.type == ProjectTransactionType.income)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final expenseAmount = transactions
        .where((item) => item.type == ProjectTransactionType.expense)
        .fold<double>(0, (sum, item) => sum + item.amount);
    return ProjectDetail(
      project: ProjectModel.fromMap(
        Map<String, dynamic>.from(data['project'] as Map),
      ).copyWith(incomeAmount: incomeAmount, expenseAmount: expenseAmount),
      transactions: transactions,
      materials: materialRows.map(ProjectMaterialModel.fromMap).toList(),
    );
  }

  Future<String> saveProject(ProjectDraft draft, {String? projectId}) async {
    final status = ProjectStatus.normalize(draft.status);
    if (ProjectStatus.countsTowardsBasicLimit(status)) {
      if (projectId == null) {
        await _ensureCanCreateProject();
      } else {
        final current = await _client
            .from('projects')
            .select('status')
            .eq('id', projectId)
            .eq('user_id', _userId)
            .maybeSingle();
        final wasClosed =
            current == null ||
            !ProjectStatus.countsTowardsBasicLimit(
              ProjectStatus.normalize(current['status'] as String?),
            );
        if (wasClosed) {
          await _ensureCanCreateProject(excludingProjectId: projectId);
        }
      }
    }
    final payload = {
      'user_id': _userId,
      'title': draft.title.trim(),
      'object_address': _blankToNull(draft.objectAddress),
      'customer_name': _blankToNull(draft.customerName),
      'planned_revenue': draft.plannedRevenue,
      'start_date': draft.startDate.toIso8601String().split('T').first,
      'target_date': draft.targetDate?.toIso8601String().split('T').first,
      'status': status,
      'notes': _blankToNull(draft.notes),
    };
    if (projectId == null) {
      final row = await _client
          .from('projects')
          .insert(payload)
          .select('id')
          .single();
      return row['id'] as String;
    }
    await _client
        .from('projects')
        .update(payload)
        .eq('id', projectId)
        .eq('user_id', _userId);
    return projectId;
  }

  Future<void> updateProjectStatus(String projectId, String status) async {
    final normalizedStatus = ProjectStatus.normalize(status);
    if (ProjectStatus.countsTowardsBasicLimit(normalizedStatus)) {
      final current = await _client
          .from('projects')
          .select('status')
          .eq('id', projectId)
          .eq('user_id', _userId)
          .maybeSingle();
      final wasClosed =
          current == null ||
          !ProjectStatus.countsTowardsBasicLimit(
            ProjectStatus.normalize(current['status'] as String?),
          );
      if (wasClosed) {
        await _ensureCanCreateProject(excludingProjectId: projectId);
      }
    }
    await _client
        .from('projects')
        .update({'status': normalizedStatus})
        .eq('id', projectId)
        .eq('user_id', _userId);
  }

  Future<void> deleteProject(String projectId) {
    return _client
        .from('projects')
        .delete()
        .eq('id', projectId)
        .eq('user_id', _userId);
  }

  Future<void> saveProjectTransaction({
    required String projectId,
    required ProjectTransactionDraft draft,
    String? transactionId,
  }) async {
    final payload = {
      'user_id': _userId,
      'project_id': projectId,
      'transaction_type': ProjectTransactionType.normalize(draft.type),
      'category': draft.category.trim(),
      'title': draft.title.trim(),
      'amount': draft.amount,
      'quantity': draft.quantity,
      'unit': _blankToNull(draft.unit),
      'transaction_date': draft.transactionDate
          .toIso8601String()
          .split('T')
          .first,
      'counterparty': _blankToNull(draft.counterparty),
      'notes': _blankToNull(draft.notes),
    };
    if (transactionId == null) {
      final row = await _client
          .from('project_transactions')
          .insert(payload)
          .select('id')
          .single();
      await _linkMatchingMaterialExpense(
        projectId: projectId,
        draft: draft,
        transactionId: row['id'] as String,
      );
      return;
    }
    await _client
        .from('project_transactions')
        .update(payload)
        .eq('id', transactionId)
        .eq('project_id', projectId)
        .eq('user_id', _userId);
    await _linkMatchingMaterialExpense(
      projectId: projectId,
      draft: draft,
      transactionId: transactionId,
    );
  }

  Future<void> _linkMatchingMaterialExpense({
    required String projectId,
    required ProjectTransactionDraft draft,
    required String transactionId,
  }) async {
    if (ProjectTransactionType.normalize(draft.type) !=
            ProjectTransactionType.expense ||
        draft.category != ProjectTransactionCategory.materials ||
        draft.title.trim().isEmpty) {
      return;
    }
    final material = await _client
        .from('project_materials')
        .select('id')
        .eq('project_id', projectId)
        .eq('user_id', _userId)
        .eq('title', draft.title.trim())
        .limit(1)
        .maybeSingle();
    if (material == null) return;
    await _client
        .from('project_materials')
        .update({
          'actual_quantity': draft.quantity,
          'actual_amount': draft.amount,
          'purchased_at': draft.transactionDate
              .toIso8601String()
              .split('T')
              .first,
          'purchase_transaction_id': transactionId,
        })
        .eq('id', material['id'] as String)
        .eq('user_id', _userId);
  }

  Future<void> deleteProjectTransaction(String transactionId) {
    return _client
        .from('project_transactions')
        .delete()
        .eq('id', transactionId)
        .eq('user_id', _userId);
  }

  Future<void> saveProjectMaterial({
    required String projectId,
    required ProjectMaterialDraft draft,
    String? materialId,
  }) async {
    final payload = {
      'user_id': _userId,
      'project_id': projectId,
      'title': draft.title.trim(),
      'planned_quantity': draft.plannedQuantity,
      'unit': draft.unit.trim().isEmpty ? 'шт' : draft.unit.trim(),
      'planned_unit_price': draft.plannedUnitPrice,
      'notes': _blankToNull(draft.notes),
    };
    if (materialId == null) {
      await _client.from('project_materials').insert(payload);
      return;
    }
    await _client
        .from('project_materials')
        .update(payload)
        .eq('id', materialId)
        .eq('project_id', projectId)
        .eq('user_id', _userId);
  }

  Future<void> purchaseProjectMaterial({
    required String projectId,
    required ProjectMaterialModel material,
    required double amount,
    required double quantity,
    required DateTime purchasedAt,
    String? counterparty,
  }) async {
    final transaction = ProjectTransactionDraft(
      type: ProjectTransactionType.expense,
      category: ProjectTransactionCategory.materials,
      title: material.title,
      amount: amount,
      quantity: quantity,
      unit: material.unit,
      transactionDate: purchasedAt,
      counterparty: counterparty,
      notes: material.notes,
    );
    String transactionId = material.purchaseTransactionId ?? '';
    if (transactionId.isEmpty) {
      final row = await _client
          .from('project_transactions')
          .insert({
            'user_id': _userId,
            'project_id': projectId,
            'transaction_type': transaction.type,
            'category': transaction.category,
            'title': transaction.title,
            'amount': transaction.amount,
            'quantity': transaction.quantity,
            'unit': transaction.unit,
            'transaction_date': transaction.transactionDate
                .toIso8601String()
                .split('T')
                .first,
            'counterparty': _blankToNull(transaction.counterparty),
            'notes': _blankToNull(transaction.notes),
          })
          .select('id')
          .single();
      transactionId = row['id'] as String;
    } else {
      await saveProjectTransaction(
        projectId: projectId,
        draft: transaction,
        transactionId: transactionId,
      );
    }
    await _client
        .from('project_materials')
        .update({
          'actual_quantity': quantity,
          'actual_amount': amount,
          'purchased_at': purchasedAt.toIso8601String().split('T').first,
          'purchase_transaction_id': transactionId,
        })
        .eq('id', material.id)
        .eq('user_id', _userId);
  }

  Future<void> deleteProjectMaterial(String materialId) {
    return _client
        .from('project_materials')
        .delete()
        .eq('id', materialId)
        .eq('user_id', _userId);
  }

  Future<TeamWorkspaceModel?> fetchTeamWorkspace() async {
    final rows = await _client.rpc('team_workspace');
    final maps = _asMaps(rows);
    return maps.isEmpty ? null : TeamWorkspaceModel.fromMap(maps.first);
  }

  Future<List<TeamMemberModel>> fetchTeamMembers() async {
    return _asMaps(
      await _client.rpc('team_members_list'),
    ).map(TeamMemberModel.fromMap).toList();
  }

  Future<List<TeamInviteModel>> fetchTeamInvites() async {
    return _asMaps(
      await _client.rpc('team_invites_list'),
    ).map(TeamInviteModel.fromMap).toList();
  }

  Future<List<IncomingTeamInviteModel>> fetchIncomingTeamInvites() async {
    return _asMaps(
      await _client.rpc('incoming_team_invites'),
    ).map(IncomingTeamInviteModel.fromMap).toList();
  }

  Future<void> createTeam(String name) async {
    await _client.rpc('create_team', params: {'p_name': name});
  }

  Future<void> inviteTeamMember(String email) async {
    await _client.rpc('invite_team_member', params: {'p_email': email});
  }

  Future<void> removeTeamMember(String memberId) async {
    await _client.rpc('remove_team_member', params: {'p_member_id': memberId});
  }

  Future<void> acceptTeamInvite(String inviteId) async {
    await _client.rpc('accept_team_invite', params: {'p_invite_id': inviteId});
  }

  Future<void> _ensureCanCreateProject({String? excludingProjectId}) async {
    final profile = await fetchProfile();
    if (profile?.hasActivePro == true) return;
    var query = _client
        .from('projects')
        .select('id')
        .eq('user_id', _userId)
        .inFilter('status', [ProjectStatus.planning, ProjectStatus.active]);
    if (excludingProjectId != null) {
      query = query.neq('id', excludingProjectId);
    }
    final rows = await query;
    if (rows.isNotEmpty) {
      throw Exception(
        'На Базовом тарифе доступен один активный объект. Подключите Профи, чтобы вести объекты без ограничений.',
      );
    }
  }

  Future<List<EstimateModel>> fetchEstimates() async {
    try {
      final rows = await _client
          .from('estimates')
          .select('*, clients(*)')
          .eq('user_id', _userId)
          .order('created_at', ascending: false);
      final maps = _asMaps(rows);
      await _localCache.write(_cacheKey('estimates'), maps);
      return _estimateModelsFromMaps(maps);
    } catch (_) {
      final cached = await _localCache.readList(_cacheKey('estimates'));
      if (cached == null) rethrow;
      return _estimateModelsFromMaps(cached);
    }
  }

  List<EstimateModel> _estimateModelsFromMaps(List<Map<String, dynamic>> rows) {
    return rows.map((row) {
      final estimate = EstimateModel.fromMap(row);
      return estimate.copyWith(
        clientSignatureUrl: clientSignaturePublicUrl(
          estimate.clientSignaturePath,
        ),
      );
    }).toList();
  }

  Future<EstimateDetail> fetchEstimateDetail(String id) async {
    try {
      final estimateRow = await _client
          .from('estimates')
          .select('*, clients(*)')
          .eq('id', id)
          .eq('user_id', _userId)
          .single();
      final lineRows = await _client
          .from('estimate_lines')
          .select()
          .eq('estimate_id', id)
          .eq('user_id', _userId)
          .order('sort_order');
      final data = {
        'estimate': Map<String, dynamic>.from(estimateRow),
        'lines': _asMaps(lineRows),
      };
      await _localCache.write(_cacheKey('estimate.$id'), data);
      return _estimateDetailFromCache(data);
    } catch (_) {
      final cached = await _localCache.readMap(_cacheKey('estimate.$id'));
      if (cached == null) rethrow;
      return _estimateDetailFromCache(cached);
    }
  }

  EstimateDetail _estimateDetailFromCache(Map<String, dynamic> data) {
    final estimateRow = Map<String, dynamic>.from(data['estimate'] as Map);
    final lineRows = data['lines'] is List
        ? (data['lines'] as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const <Map<String, dynamic>>[];
    final estimate = EstimateModel.fromMap(estimateRow);
    return EstimateDetail(
      estimate: estimate.copyWith(
        clientSignatureUrl: clientSignaturePublicUrl(
          estimate.clientSignaturePath,
        ),
      ),
      lines: lineRows.map((row) => EstimateLineModel.fromMap(row)).toList(),
    );
  }

  Future<String> saveEstimateDraft(
    EstimateDraft draft, {
    String? estimateId,
    String? revisionOf,
    int? documentVersion,
  }) async {
    if (estimateId == null) {
      await _ensureCanCreateEstimate();
    } else {
      await _ensureEstimateEditable(estimateId);
    }

    String? clientId = draft.clientId;
    if (clientId == null && draft.clientName.trim().isNotEmpty) {
      final client = await saveClient(
        name: draft.clientName,
        phone: draft.clientPhone,
        objectAddress: draft.objectTitle,
      );
      clientId = client.id;
    } else if (clientId != null && draft.clientName.trim().isNotEmpty) {
      await saveClient(
        id: clientId,
        name: draft.clientName,
        phone: draft.clientPhone,
        objectAddress: draft.objectTitle,
      );
    }

    final estimatePayload = {
      'user_id': _userId,
      'client_id': clientId,
      'object_title': draft.objectTitle.trim(),
      'estimate_date': draft.estimateDate.toIso8601String().split('T').first,
      'duration_days': draft.durationDays,
      'total_amount': draft.totalAmount,
    };

    final String savedId;
    if (estimateId == null) {
      final row = await _client
          .from('estimates')
          .insert({
            ...estimatePayload,
            'revision_of': revisionOf,
            'document_version': documentVersion ?? 1,
          })
          .select('id')
          .single();
      savedId = row['id'] as String;
    } else {
      await _client
          .from('estimates')
          .update(estimatePayload)
          .eq('id', estimateId)
          .eq('user_id', _userId);
      await _client
          .from('estimate_lines')
          .delete()
          .eq('estimate_id', estimateId)
          .eq('user_id', _userId);
      savedId = estimateId;
    }

    if (draft.lines.isNotEmpty) {
      await _client.from('estimate_lines').insert([
        for (var i = 0; i < draft.lines.length; i++)
          {
            'user_id': _userId,
            'estimate_id': savedId,
            'catalog_item_id': draft.lines[i].catalogItemId,
            'title': draft.lines[i].title.trim(),
            'unit': draft.lines[i].unit.trim(),
            'quantity': draft.lines[i].quantity,
            'unit_price': draft.lines[i].unitPrice,
            'line_total': draft.lines[i].lineTotal,
            'sort_order': i,
          },
      ]);
    }

    return savedId;
  }

  Future<void> _ensureEstimateEditable(String estimateId) async {
    final row = await _client
        .from('estimates')
        .select('client_signed_at')
        .eq('id', estimateId)
        .eq('user_id', _userId)
        .maybeSingle();
    if (row?['client_signed_at'] != null) {
      throw Exception(
        'Смета уже подписана клиентом и не может быть изменена. Создайте новую версию.',
      );
    }
  }

  Future<void> _ensureCanCreateEstimate() async {
    final profile = await fetchProfile();
    final limit =
        profile?.monthlyEstimateLimit ?? ProfileModel.basicMonthlyEstimateLimit;
    if (profile?.hasActivePro == true) return;

    final createdThisMonth = await countEstimatesCreatedSince(
      _startOfCurrentMonth(),
    );
    if (createdThisMonth >= limit) {
      throw Exception(
        'Лимит базового тарифа: $limit смет в месяц. Подключите Профи, чтобы создавать сметы без ограничений.',
      );
    }
  }

  Future<int> countEstimatesCreatedSince(DateTime since) async {
    final rows = await _client
        .from('estimates')
        .select('id')
        .eq('user_id', _userId)
        .gte('created_at', since.toUtc().toIso8601String());
    return rows.length;
  }

  Future<void> updateEstimateStatus(String estimateId, String status) async {
    await _client
        .from('estimates')
        .update({'status': EstimateStatus.normalize(status)})
        .eq('id', estimateId)
        .eq('user_id', _userId);
  }

  Future<void> acceptEstimateWithClientSignature({
    required String estimateId,
    required Uint8List signatureBytes,
    required Uint8List signedPdfBytes,
    required Map<String, dynamic> signedSnapshot,
    required DateTime signedAt,
    required String clientName,
    String? clientPhone,
    required int documentVersion,
    required String signatureChallengeId,
  }) async {
    final normalizedClientPhone = _normalizeRussianPhone(clientPhone);
    final version = DateTime.now().millisecondsSinceEpoch;
    final signaturePath =
        '$_userId/$estimateId/v$documentVersion-$version-signature.png';
    await _client.storage
        .from('client-signatures')
        .uploadBinary(
          signaturePath,
          signatureBytes,
          fileOptions: const FileOptions(contentType: 'image/png'),
        );
    final signedPdfPath =
        '$_userId/$estimateId/v$documentVersion-$version-signed.pdf';
    await _client.storage
        .from('signed-estimate-pdfs')
        .uploadBinary(
          signedPdfPath,
          signedPdfBytes,
          fileOptions: const FileOptions(contentType: 'application/pdf'),
        );

    final updated = await _client
        .from('estimates')
        .update({
          'status': EstimateStatus.accepted,
          'client_signature_path': signaturePath,
          'client_signed_at': signedAt.toUtc().toIso8601String(),
          'client_signed_name': clientName.trim(),
          'client_signed_phone': normalizedClientPhone,
          'client_signature_otp_challenge_id': signatureChallengeId,
          'client_signature_method': 'telegram_otp',
          'client_signature_statement_version': clientSignatureStatementVersion,
          'client_signature_statement': clientSignatureStatement,
          'signed_document_snapshot': signedSnapshot,
          'signed_pdf_storage_path': signedPdfPath,
        })
        .eq('id', estimateId)
        .eq('user_id', _userId)
        .eq('status', EstimateStatus.sent)
        .isFilter('client_signed_at', null)
        .select('id')
        .maybeSingle();
    if (updated == null) {
      throw Exception(
        'Смета уже была подписана или её статус изменился. Обновите страницу и повторите попытку.',
      );
    }
  }

  Future<Uint8List> downloadSignedEstimatePdf(String path) {
    return _client.storage.from('signed-estimate-pdfs').download(path);
  }

  Future<EstimateApprovalLink> createEstimateApprovalLink({
    required String estimateId,
  }) async {
    final response = await _client.functions.invoke(
      'estimate-approval',
      body: {'action': 'create', 'estimateId': estimateId},
    );
    final data = _functionData(response.data);
    final token = data['token'] as String?;
    final expiresAt = asDateOrNull(data['expiresAt']);
    if (token == null || token.isEmpty || expiresAt == null) {
      throw const AuthException(
        'Сервис не смог подготовить ссылку для клиента.',
      );
    }
    return EstimateApprovalLink(token: token, expiresAt: expiresAt);
  }

  Future<String> storeSignedEstimatePdf({
    required String estimateId,
    required int documentVersion,
    required Uint8List bytes,
  }) async {
    final version = DateTime.now().millisecondsSinceEpoch;
    final path = '$_userId/$estimateId/v$documentVersion-$version-signed.pdf';
    await _client.storage
        .from('signed-estimate-pdfs')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'application/pdf'),
        );
    final updated = await _client
        .from('estimates')
        .update({'signed_pdf_storage_path': path})
        .eq('id', estimateId)
        .eq('user_id', _userId)
        .isFilter('signed_pdf_storage_path', null)
        .select('id')
        .maybeSingle();
    if (updated == null) {
      return path;
    }
    return path;
  }

  Future<EstimateSignatureOtpChallenge> requestEstimateSignatureCode({
    required String estimateId,
  }) async {
    final response = await _client.functions.invoke(
      'estimate-signature-otp',
      body: {'action': 'send', 'estimateId': estimateId},
    );
    final data = _functionData(response.data);
    final id = data['challengeId'] as String?;
    if (id == null || id.isEmpty) {
      throw const AuthException('Сервис не вернул номер запроса кода.');
    }
    final seconds = asIntOrNull(data['expiresIn']);
    return EstimateSignatureOtpChallenge(
      id: id,
      maskedPhone: (data['maskedPhone'] as String?) ?? 'номер клиента',
      expiresAt: seconds == null
          ? null
          : DateTime.now().add(Duration(seconds: seconds)),
    );
  }

  Future<EstimateSignatureOtpChallenge> verifyEstimateSignatureCode({
    required String challengeId,
    required String code,
  }) async {
    final response = await _client.functions.invoke(
      'estimate-signature-otp',
      body: {
        'action': 'verify',
        'challengeId': challengeId,
        'code': code.trim(),
      },
    );
    final data = _functionData(response.data);
    final id = data['challengeId'] as String?;
    if (id == null || id.isEmpty) {
      throw const AuthException('Сервис не подтвердил код клиента.');
    }
    return EstimateSignatureOtpChallenge(
      id: id,
      maskedPhone: '',
      verifiedAt: asDateOrNull(data['verifiedAt']),
    );
  }

  Future<String> uploadEstimatePdf({
    required String estimateId,
    required Uint8List bytes,
  }) async {
    final path = '$_userId/$estimateId.pdf';
    await _client.storage
        .from('estimate-pdfs')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'application/pdf',
          ),
        );
    final publicUrl = _client.storage.from('estimate-pdfs').getPublicUrl(path);
    await _client
        .from('estimates')
        .update({'pdf_storage_path': path, 'status': EstimateStatus.sent})
        .eq('id', estimateId)
        .eq('user_id', _userId);
    return publicUrl;
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static List<Map<String, dynamic>> _asMaps(Iterable<dynamic> rows) {
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  static String _normalizeRussianPhone(String? value) {
    var digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) digits = '7$digits';
    if (digits.startsWith('8')) digits = '7${digits.substring(1)}';
    if (digits.length != 11 || !digits.startsWith('7')) {
      throw const AuthException('Для подписи нужен российский номер клиента.');
    }
    return '+$digits';
  }

  static Map<String, dynamic> _functionData(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const AuthException('Сервер вернул неожиданный ответ.');
  }

  static String _catalogKey(String category, String title, String unit) {
    return '${category.trim().toLowerCase()}|${title.trim().toLowerCase()}|${unit.trim().toLowerCase()}';
  }

  Future<Set<String>> _fetchHiddenCatalogCategories() async {
    final rows = await _client
        .from('catalog_categories')
        .select('title')
        .eq('user_id', _userId)
        .eq('is_hidden', true);
    return rows
        .map((row) => ((row['title'] as String?) ?? '').trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Future<Set<String>> _fetchHiddenCatalogItemKeys() async {
    final rows = await _client
        .from('catalog_hidden_items')
        .select('category,title,unit')
        .eq('user_id', _userId);
    return rows
        .map(
          (row) => _catalogKey(
            (row['category'] as String?) ?? '',
            (row['title'] as String?) ?? '',
            (row['unit'] as String?) ?? '',
          ),
        )
        .toSet();
  }

  static String _normalizeCatalogCategory(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    return '${lower.substring(0, 1).toUpperCase()}${lower.substring(1)}';
  }

  static DateTime _startOfCurrentMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }
}
