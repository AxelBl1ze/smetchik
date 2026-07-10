import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import 'models.dart';

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

final estimateDetailProvider = FutureProvider.family<EstimateDetail, String>((
  ref,
  id,
) {
  return ref.watch(repositoryProvider).fetchEstimateDetail(id);
});

class SmetchikRepository {
  const SmetchikRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Пользователь не авторизован');
    return id;
  }

  Future<ProfileModel?> fetchProfile() async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', _userId)
        .maybeSingle();
    if (data == null) return null;
    return ProfileModel.fromMap(data);
  }

  Future<void> saveProfile({
    required String fullName,
    String? phone,
    String? specialization,
    String currency = 'RUB',
  }) async {
    await _client.from('profiles').upsert({
      'id': _userId,
      'full_name': fullName.trim(),
      'phone': _blankToNull(phone),
      'specialization': _blankToNull(specialization),
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

  Future<void> updateSubscriptionPlan(String plan) async {
    if (SubscriptionPlan.normalize(plan) == SubscriptionPlan.pro) {
      return activateMockPro();
    }
    return switchToBasicPlan();
  }

  Future<void> activateMockPro({int days = 30}) async {
    final renewsAt = DateTime.now().toUtc().add(Duration(days: days));
    await _client
        .from('profiles')
        .update({
          'subscription_plan': SubscriptionPlan.pro,
          'subscription_status': SubscriptionStatus.active,
          'subscription_source': SubscriptionSource.mock,
          'subscription_renews_at': renewsAt.toIso8601String(),
        })
        .eq('id', _userId);
  }

  Future<void> switchToBasicPlan() async {
    await _client
        .from('profiles')
        .update({
          'subscription_plan': SubscriptionPlan.basic,
          'subscription_status': SubscriptionStatus.active,
          'subscription_source': SubscriptionSource.mock,
          'subscription_renews_at': null,
        })
        .eq('id', _userId);
  }

  Future<void> expireMockSubscription() async {
    final expiredAt = DateTime.now().toUtc().subtract(const Duration(days: 1));
    await _client
        .from('profiles')
        .update({
          'subscription_plan': SubscriptionPlan.pro,
          'subscription_status': SubscriptionStatus.pastDue,
          'subscription_source': SubscriptionSource.mock,
          'subscription_renews_at': expiredAt.toIso8601String(),
        })
        .eq('id', _userId);
  }

  String? logoPublicUrl(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    return _client.storage.from('logos').getPublicUrl(path);
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
    await _client.storage
        .from('logos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    await _client
        .from('profiles')
        .update({'logo_path': path})
        .eq('id', _userId);
    return path;
  }

  Future<List<ClientModel>> fetchClients() async {
    final rows = await _client
        .from('clients')
        .select()
        .eq('user_id', _userId)
        .order('created_at', ascending: false);
    return rows.map((row) => ClientModel.fromMap(row)).toList();
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
      _client
          .from('catalog_categories')
          .select('title,is_hidden,icon_key')
          .eq('user_id', _userId)
          .order('sort_order')
          .order('title'),
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
      await _client.from('catalog_categories').insert({
        'user_id': _userId,
        'title': normalized,
        'is_hidden': false,
        'icon_key': normalizedIcon,
      });
    } else {
      await _client
          .from('catalog_categories')
          .update({'is_hidden': false, 'icon_key': normalizedIcon})
          .eq('id', existing['id'])
          .eq('user_id', _userId);
    }
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

  Future<List<EstimateModel>> fetchEstimates() async {
    final rows = await _client
        .from('estimates')
        .select('*, clients(*)')
        .eq('user_id', _userId)
        .order('created_at', ascending: false);
    return rows.map((row) => EstimateModel.fromMap(row)).toList();
  }

  Future<EstimateDetail> fetchEstimateDetail(String id) async {
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
    return EstimateDetail(
      estimate: EstimateModel.fromMap(estimateRow),
      lines: lineRows.map((row) => EstimateLineModel.fromMap(row)).toList(),
    );
  }

  Future<String> saveEstimateDraft(
    EstimateDraft draft, {
    String? estimateId,
  }) async {
    if (estimateId == null) {
      await _ensureCanCreateEstimate();
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
          .insert(estimatePayload)
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
