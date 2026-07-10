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

DateTime? asDateOrNull(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
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

class EstimateStatus {
  const EstimateStatus._();

  static const draft = 'draft';
  static const sent = 'sent';
  static const accepted = 'accepted';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const declined = 'declined';

  static const values = [
    draft,
    sent,
    accepted,
    inProgress,
    completed,
    declined,
  ];

  static String normalize(String? value) {
    return switch ((value ?? '').trim()) {
      sent => sent,
      accepted => accepted,
      'approved' => inProgress,
      inProgress => inProgress,
      completed => completed,
      declined => declined,
      _ => draft,
    };
  }

  static bool isActiveWork(String value) => normalize(value) == inProgress;

  static bool isCompleted(String value) => normalize(value) == completed;
}

class SubscriptionPlan {
  const SubscriptionPlan._();

  static const basic = 'basic';
  static const pro = 'pro';

  static const values = [basic, pro];

  static String normalize(String? value) {
    return switch ((value ?? '').trim()) {
      pro => pro,
      'team' => pro,
      _ => basic,
    };
  }

  static String label(String value) {
    return switch (normalize(value)) {
      pro => 'Профи',
      _ => 'Базовый',
    };
  }

  static String price(String value) {
    return switch (normalize(value)) {
      pro => '399 ₽/мес',
      _ => '0 ₽',
    };
  }

  static String caption(String value) {
    return switch (normalize(value)) {
      pro => 'для активной работы каждый день',
      _ => 'для старта и первых клиентов',
    };
  }

  static List<String> features(String value) {
    return switch (normalize(value)) {
      pro => const [
        'Безлимитные новые сметы',
        'Безлимитная база клиентов',
        'Дублирование смет',
        'Настройки PDF',
        'Расширенная статистика',
      ],
      _ => const [
        'До 10 новых смет в месяц',
        'До 20 клиентов',
        'Стандартный PDF с отметкой Сметчика',
      ],
    };
  }
}

class SubscriptionStatus {
  const SubscriptionStatus._();

  static const active = 'active';
  static const trialing = 'trialing';
  static const pastDue = 'past_due';
  static const canceled = 'canceled';

  static String normalize(String? value) {
    return switch ((value ?? '').trim()) {
      trialing => trialing,
      pastDue => pastDue,
      canceled => canceled,
      _ => active,
    };
  }
}

class SubscriptionSource {
  const SubscriptionSource._();

  static const manual = 'manual';
  static const mock = 'mock';
  static const web = 'web';
  static const googlePlay = 'google_play';
  static const apple = 'apple';

  static String normalize(String? value) {
    return switch ((value ?? '').trim()) {
      mock => mock,
      web => web,
      googlePlay => googlePlay,
      apple => apple,
      _ => manual,
    };
  }

  static String label(String value) {
    return switch (normalize(value)) {
      mock => 'тестовая оплата',
      web => 'сайт',
      googlePlay => 'Google Play',
      apple => 'App Store',
      _ => 'вручную',
    };
  }
}

class PdfTemplate {
  const PdfTemplate._();

  static const classic = 'classic';
  static const accent = 'accent';
  static const compact = 'compact';

  static const values = [classic, accent, compact];

  static String normalize(String? value) {
    return switch ((value ?? '').trim()) {
      classic => classic,
      compact => compact,
      _ => accent,
    };
  }

  static String label(String value) {
    return switch (normalize(value)) {
      classic => 'Классика',
      compact => 'Компактный',
      _ => 'Акцентный',
    };
  }

  static String caption(String value) {
    return switch (normalize(value)) {
      classic => 'строгий КП-вид',
      compact => 'больше строк на странице',
      _ => 'современная шапка',
    };
  }
}

class PdfAccentColor {
  const PdfAccentColor._();

  static const orange = '#F5820D';
  static const graphite = '#1A1A1A';
  static const green = '#3B6D11';
  static const blue = '#185FA5';

  static const values = [orange, graphite, green, blue];

  static String normalize(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return values.contains(normalized) ? normalized : orange;
  }

  static String label(String value) {
    return switch (normalize(value)) {
      graphite => 'Графит',
      green => 'Зелёный',
      blue => 'Синий',
      _ => 'Оранжевый',
    };
  }
}

class ProfileModel {
  const ProfileModel({
    required this.id,
    required this.fullName,
    this.phone,
    this.specialization,
    this.logoPath,
    required this.currency,
    this.subscriptionPlan = SubscriptionPlan.basic,
    this.subscriptionStatus = 'active',
    this.subscriptionSource = SubscriptionSource.manual,
    this.subscriptionRenewsAt,
    this.pdfShowBrandHeader = true,
    this.pdfShowSignatures = true,
    this.pdfShowServiceMark = true,
    this.pdfTemplate = PdfTemplate.accent,
    this.pdfAccentColor = PdfAccentColor.orange,
    this.pdfPaymentTerms,
    this.pdfFooterNote,
  });

  static const basicMonthlyEstimateLimit = 10;
  static const basicClientLimit = 20;

  final String id;
  final String fullName;
  final String? phone;
  final String? specialization;
  final String? logoPath;
  final String currency;
  final String subscriptionPlan;
  final String subscriptionStatus;
  final String subscriptionSource;
  final DateTime? subscriptionRenewsAt;
  final bool pdfShowBrandHeader;
  final bool pdfShowSignatures;
  final bool pdfShowServiceMark;
  final String pdfTemplate;
  final String pdfAccentColor;
  final String? pdfPaymentTerms;
  final String? pdfFooterNote;

  bool get isSubscriptionExpired {
    final renewsAt = subscriptionRenewsAt;
    if (renewsAt == null) return false;
    return !renewsAt.isAfter(DateTime.now());
  }

  bool get hasActivePro {
    final status = SubscriptionStatus.normalize(subscriptionStatus);
    return SubscriptionPlan.normalize(subscriptionPlan) ==
            SubscriptionPlan.pro &&
        (status == SubscriptionStatus.active ||
            status == SubscriptionStatus.trialing) &&
        !isSubscriptionExpired;
  }

  String get effectiveSubscriptionPlan =>
      hasActivePro ? SubscriptionPlan.pro : SubscriptionPlan.basic;

  int? get monthlyEstimateLimit =>
      hasActivePro ? null : basicMonthlyEstimateLimit;

  int? get clientLimit => hasActivePro ? null : basicClientLimit;

  int remainingMonthlyEstimates(int createdThisMonth) {
    final limit = monthlyEstimateLimit;
    if (limit == null) return 999999;
    final remaining = limit - createdThisMonth;
    return remaining < 0 ? 0 : remaining;
  }

  int remainingClients(int clientsCount) {
    final limit = clientLimit;
    if (limit == null) return 999999;
    final remaining = limit - clientsCount;
    return remaining < 0 ? 0 : remaining;
  }

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
      subscriptionPlan: SubscriptionPlan.normalize(
        map['subscription_plan'] as String?,
      ),
      subscriptionStatus: SubscriptionStatus.normalize(
        map['subscription_status'] as String?,
      ),
      subscriptionSource: SubscriptionSource.normalize(
        map['subscription_source'] as String?,
      ),
      subscriptionRenewsAt: asDateOrNull(map['subscription_renews_at']),
      pdfShowBrandHeader: (map['pdf_show_brand_header'] as bool?) ?? true,
      pdfShowSignatures: (map['pdf_show_signatures'] as bool?) ?? true,
      pdfShowServiceMark: (map['pdf_show_service_mark'] as bool?) ?? true,
      pdfTemplate: PdfTemplate.normalize(map['pdf_template'] as String?),
      pdfAccentColor: PdfAccentColor.normalize(
        map['pdf_accent_color'] as String?,
      ),
      pdfPaymentTerms: map['pdf_payment_terms'] as String?,
      pdfFooterNote: map['pdf_footer_note'] as String?,
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
  const CatalogData({
    required this.items,
    required this.categories,
    this.categoryIcons = const {},
  });

  static const empty = CatalogData(
    items: [],
    categories: [],
    categoryIcons: {},
  );

  final List<CatalogItemModel> items;
  final List<String> categories;
  final Map<String, String> categoryIcons;
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
      status: EstimateStatus.normalize(map['status'] as String?),
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
