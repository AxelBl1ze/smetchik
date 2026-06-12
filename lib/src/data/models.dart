import 'package:intl/intl.dart';

final rubFormatter = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 0,
);

double asDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int? asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

DateTime asDate(dynamic value) {
  if (value == null) return DateTime.now();
  return DateTime.tryParse(value.toString()) ?? DateTime.now();
}

String formatMoney(num value) => rubFormatter.format(value);

String formatDate(DateTime date) =>
    DateFormat('dd.MM.yyyy', 'ru_RU').format(date);

String formatQuantity(num value) {
  final asDouble = value.toDouble();
  if (asDouble == asDouble.roundToDouble()) return asDouble.toStringAsFixed(0);
  return asDouble
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

class ProfileModel {
  const ProfileModel({
    required this.id,
    required this.fullName,
    this.phone,
    this.specialization,
    this.logoPath,
    required this.currency,
  });

  final String id;
  final String fullName;
  final String? phone;
  final String? specialization;
  final String? logoPath;
  final String currency;

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty);
    final value = parts
        .take(2)
        .map((e) => e.substring(0, 1).toUpperCase())
        .join();
    return value.isEmpty ? 'СМ' : value;
  }

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    return ProfileModel(
      id: map['id'] as String,
      fullName: (map['full_name'] as String?) ?? '',
      phone: map['phone'] as String?,
      specialization: map['specialization'] as String?,
      logoPath: map['logo_path'] as String?,
      currency: (map['currency'] as String?) ?? 'RUB',
    );
  }
}

class ClientModel {
  const ClientModel({
    required this.id,
    required this.name,
    this.phone,
    this.objectAddress,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? phone;
  final String? objectAddress;
  final String? notes;
  final DateTime createdAt;

  factory ClientModel.fromMap(Map<String, dynamic> map) {
    return ClientModel(
      id: map['id'] as String,
      name: (map['name'] as String?) ?? '',
      phone: map['phone'] as String?,
      objectAddress: map['object_address'] as String?,
      notes: map['notes'] as String?,
      createdAt: asDate(map['created_at']),
    );
  }
}

class CatalogData {
  const CatalogData({required this.items, required this.categories});
  static const empty = CatalogData(items: [], categories: []);

  final List<CatalogItemModel> items;
  final List<String> categories;
}

class CatalogItemModel {
  const CatalogItemModel({
    required this.id,
    this.userId,
    required this.category,
    required this.title,
    required this.unit,
    required this.unitPrice,
    required this.isCustom,
  });

  final String id;
  final String? userId;
  final String category;
  final String title;
  final String unit;
  final double unitPrice;
  final bool isCustom;

  factory CatalogItemModel.fromMap(Map<String, dynamic> map) {
    return CatalogItemModel(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      category: (map['category'] as String?) ?? 'Другое',
      title: (map['title'] as String?) ?? '',
      unit: (map['unit'] as String?) ?? 'шт',
      unitPrice: asDouble(map['unit_price']),
      isCustom: (map['is_custom'] as bool?) ?? true,
    );
  }
}

class EstimateModel {
  const EstimateModel({
    required this.id,
    this.clientId,
    this.client,
    required this.objectTitle,
    required this.estimateDate,
    this.durationDays,
    required this.status,
    required this.totalAmount,
    this.pdfStoragePath,
    required this.createdAt,
  });

  final String id;
  final String? clientId;
  final ClientModel? client;
  final String objectTitle;
  final DateTime estimateDate;
  final int? durationDays;
  final String status;
  final double totalAmount;
  final String? pdfStoragePath;
  final DateTime createdAt;

  factory EstimateModel.fromMap(Map<String, dynamic> map) {
    final clientMap = map['clients'];
    return EstimateModel(
      id: map['id'] as String,
      clientId: map['client_id'] as String?,
      client: clientMap is Map<String, dynamic>
          ? ClientModel.fromMap(clientMap)
          : null,
      objectTitle: (map['object_title'] as String?) ?? '',
      estimateDate: asDate(map['estimate_date']),
      durationDays: asIntOrNull(map['duration_days']),
      status: (map['status'] as String?) ?? 'draft',
      totalAmount: asDouble(map['total_amount']),
      pdfStoragePath: map['pdf_storage_path'] as String?,
      createdAt: asDate(map['created_at']),
    );
  }
}

class EstimateLineModel {
  const EstimateLineModel({
    required this.id,
    this.catalogItemId,
    required this.title,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.sortOrder,
  });

  final String id;
  final String? catalogItemId;
  final String title;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final int sortOrder;

  EstimateLineModel copyWith({
    String? id,
    String? catalogItemId,
    String? title,
    String? unit,
    double? quantity,
    double? unitPrice,
    int? sortOrder,
  }) {
    final nextQuantity = quantity ?? this.quantity;
    final nextUnitPrice = unitPrice ?? this.unitPrice;
    return EstimateLineModel(
      id: id ?? this.id,
      catalogItemId: catalogItemId ?? this.catalogItemId,
      title: title ?? this.title,
      unit: unit ?? this.unit,
      quantity: nextQuantity,
      unitPrice: nextUnitPrice,
      lineTotal: nextQuantity * nextUnitPrice,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  factory EstimateLineModel.fromMap(Map<String, dynamic> map) {
    return EstimateLineModel(
      id: map['id'] as String,
      catalogItemId: map['catalog_item_id'] as String?,
      title: (map['title'] as String?) ?? '',
      unit: (map['unit'] as String?) ?? 'шт',
      quantity: asDouble(map['quantity']),
      unitPrice: asDouble(map['unit_price']),
      lineTotal: asDouble(map['line_total']),
      sortOrder: (map['sort_order'] as int?) ?? 0,
    );
  }

  factory EstimateLineModel.fromCatalog(CatalogItemModel item, int sortOrder) {
    return EstimateLineModel(
      id: 'local-$sortOrder-${DateTime.now().microsecondsSinceEpoch}',
      catalogItemId: item.id,
      title: item.title,
      unit: item.unit,
      quantity: 1,
      unitPrice: item.unitPrice,
      lineTotal: item.unitPrice,
      sortOrder: sortOrder,
    );
  }
}

class EstimateDetail {
  const EstimateDetail({required this.estimate, required this.lines});

  final EstimateModel estimate;
  final List<EstimateLineModel> lines;
}

class EstimateDraft {
  const EstimateDraft({
    required this.objectTitle,
    this.clientId,
    required this.clientName,
    this.clientPhone,
    required this.estimateDate,
    this.durationDays,
    required this.lines,
  });

  final String objectTitle;
  final String? clientId;
  final String clientName;
  final String? clientPhone;
  final DateTime estimateDate;
  final int? durationDays;
  final List<EstimateLineModel> lines;

  double get totalAmount => lines.fold(0, (sum, line) => sum + line.lineTotal);
}
