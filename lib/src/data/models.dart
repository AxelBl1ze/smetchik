import 'package:intl/intl.dart';

import 'pdf_templates.dart';

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

String formatDateTime(DateTime date) =>
    DateFormat('dd.MM.yyyy HH:mm', 'ru_RU').format(date.toLocal());

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

class ProjectStatus {
  const ProjectStatus._();

  static const planning = 'planning';
  static const active = 'active';
  static const completed = 'completed';
  static const sold = 'sold';

  static const values = [planning, active, completed, sold];

  static String normalize(String? value) {
    return switch ((value ?? '').trim()) {
      active => active,
      completed => completed,
      sold => sold,
      _ => planning,
    };
  }

  static String label(String value) {
    return switch (normalize(value)) {
      active => 'Строится',
      completed => 'Завершён',
      sold => 'Продан',
      _ => 'Планируется',
    };
  }

  static bool countsTowardsBasicLimit(String value) {
    final normalized = normalize(value);
    return normalized == planning || normalized == active;
  }
}

class ProjectTransactionType {
  const ProjectTransactionType._();

  static const income = 'income';
  static const expense = 'expense';

  static String normalize(String? value) => value == income ? income : expense;

  static String label(String value) =>
      normalize(value) == income ? 'Поступление' : 'Расход';
}

/// Группы операций для внутреннего учёта строительства.
///
/// Наименование операции остаётся свободным, а категория помогает быстро
/// собрать расходы в аналитике и выгрузках без разрастания списка значений.
class ProjectTransactionCategory {
  const ProjectTransactionCategory._();

  static const materials = 'Материалы';
  static const labor = 'Работы и бригада';
  static const contractors = 'Подрядчики';
  static const equipment = 'Техника и аренда';
  static const delivery = 'Доставка и логистика';
  static const tools = 'Инструмент и расходники';
  static const sitePreparation = 'Участок и подготовка';
  static const designAndDocuments = 'Проектирование и документы';
  static const utilitiesAndSecurity = 'Коммунальные и охрана';
  static const taxesAndPermits = 'Налоги и разрешения';
  static const salesAndMarketing = 'Продажи и реклама';
  static const advance = 'Аванс от заказчика';
  static const stagePayment = 'Оплата этапа';
  static const finalPayment = 'Финальный расчёт';
  static const propertySale = 'Продажа объекта';
  static const refund = 'Возврат средств';
  static const other = 'Другое';

  static const expenseValues = [
    materials,
    labor,
    contractors,
    equipment,
    delivery,
    tools,
    sitePreparation,
    designAndDocuments,
    utilitiesAndSecurity,
    taxesAndPermits,
    salesAndMarketing,
    other,
  ];

  static const incomeValues = [
    advance,
    stagePayment,
    finalPayment,
    propertySale,
    refund,
    other,
  ];

  static List<String> valuesForType(String type) =>
      ProjectTransactionType.normalize(type) == ProjectTransactionType.income
      ? incomeValues
      : expenseValues;

  static String defaultForType(String type) =>
      ProjectTransactionType.normalize(type) == ProjectTransactionType.income
      ? advance
      : materials;
}

class SubscriptionPlan {
  const SubscriptionPlan._();

  static const basic = 'basic';
  static const pro = 'pro';
  static const team = 'team';

  static const values = [basic, pro, team];

  static String normalize(String? value) {
    return switch ((value ?? '').trim()) {
      pro => pro,
      team => team,
      _ => basic,
    };
  }

  static String label(String value) {
    return switch (normalize(value)) {
      pro => 'Профи',
      team => 'Бригада',
      _ => 'Базовый',
    };
  }

  static String price(String value) {
    return switch (normalize(value)) {
      pro => '399 ₽/мес',
      team => '1 490 ₽/мес',
      _ => '0 ₽',
    };
  }

  static String caption(String value) {
    return switch (normalize(value)) {
      pro => 'для активной работы каждый день',
      team => 'для команды до 6 мастеров',
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
        'Безлимитные объекты и учёт затрат',
        'Аналитика прибыли по объектам',
        'Экспорт объектов в Excel и PDF',
      ],
      team => const [
        'Всё из тарифа Профи',
        'До 6 мастеров на одном тарифе',
        'Приглашения в бригаду по email',
        'Личные клиенты и сметы каждого мастера',
        'Безлимитные объекты и учёт материалов',
      ],
      _ => const [
        'До 10 новых смет в месяц',
        'До 20 клиентов',
        'Стандартный PDF с отметкой Сметчика',
        '1 активный объект с базовым учётом',
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
  static const promo = 'promo';
  static const admin = 'admin';

  static String normalize(String? value) {
    return switch ((value ?? '').trim()) {
      mock => mock,
      web => web,
      googlePlay => googlePlay,
      apple => apple,
      promo => promo,
      admin => admin,
      _ => manual,
    };
  }

  static String label(String value) {
    return switch (normalize(value)) {
      mock => 'тестовая оплата',
      web => 'сайт',
      googlePlay => 'Google Play',
      apple => 'App Store',
      promo => 'промокод',
      admin => 'выдано поддержкой',
      _ => 'вручную',
    };
  }
}

class PromoRedemptionResult {
  const PromoRedemptionResult({
    required this.title,
    required this.plan,
    required this.renewsAt,
  });

  final String? title;
  final String plan;
  final DateTime? renewsAt;
}

class PdfTemplate {
  const PdfTemplate._();

  static const standardFree = 'standard_free';
  static const goldNoir = 'premium_gold_noir';
  static const whiteSpace = 'premium_white_space';
  static const brightAccent = 'premium_bright_accent';
  static const corporateClassic = 'premium_corporate_classic';
  static const invoiceFirst = 'premium_invoice_first';
  static const craftPaper = 'premium_craft_paper';
  static const techGrid = 'premium_tech_grid';
  static const coverDeluxe = 'premium_cover_deluxe';
  static const storyFormat = 'premium_story_format';
  static const bilingual = 'premium_bilingual';
  static const signedSealed = 'premium_signed_sealed';

  static const classic = 'classic';
  static const accent = 'accent';
  static const compact = 'compact';

  static final values = SmetaTemplates.ids;

  static String normalize(String? value) {
    return SmetaTemplates.normalizeId(value);
  }

  static String label(String value) {
    return SmetaTemplates.byId(value).shortName;
  }

  static String caption(String value) {
    return SmetaTemplates.byId(value).description;
  }
}

class PdfAccentColor {
  const PdfAccentColor._();

  static const orange = '#F5820D';
  static const graphite = '#1A1A1A';
  static const green = '#3B6D11';
  static const blue = '#185FA5';

  static const values = [
    orange,
    graphite,
    green,
    blue,
    '#2F6FE0',
    '#C9A24A',
    '#3C3A35',
    '#378ADD',
    '#639922',
    '#D85A30',
    '#D4537E',
    '#B0512E',
    '#0F6E56',
    '#3C3489',
    '#085041',
    '#5F5E5A',
  ];

  static String normalize(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    final validHex = RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized);
    return validHex ? normalized : orange;
  }

  static String label(String value) {
    return switch (normalize(value)) {
      graphite => 'Графит',
      green => 'Зелёный',
      blue => 'Синий',
      '#2F6FE0' => 'Синий',
      '#C9A24A' => 'Золото',
      '#3C3A35' => 'Тёплый графит',
      '#378ADD' => 'Ярко-синий',
      '#639922' => 'Травяной',
      '#D85A30' => 'Коралл',
      '#D4537E' => 'Розовый',
      '#B0512E' => 'Терракота',
      '#0F6E56' => 'Бирюзовый',
      '#3C3489' => 'Фиолетовый',
      '#085041' => 'Тёмно-зелёный',
      '#5F5E5A' => 'Нейтральный',
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
    this.logoUrl,
    this.signaturePath,
    this.signatureUrl,
    this.paymentQrPath,
    this.paymentQrUrl,
    this.paymentQrLabel,
    this.contactQrPath,
    this.contactQrUrl,
    this.contactQrLabel,
    required this.currency,
    this.subscriptionPlan = SubscriptionPlan.basic,
    this.subscriptionStatus = 'active',
    this.subscriptionSource = SubscriptionSource.manual,
    this.subscriptionRenewsAt,
    this.pdfShowBrandHeader = true,
    this.pdfShowSignatures = true,
    this.pdfShowServiceMark = true,
    this.pdfTemplate = PdfTemplate.brightAccent,
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
  final String? logoUrl;
  final String? signaturePath;
  final String? signatureUrl;
  final String? paymentQrPath;
  final String? paymentQrUrl;
  final String? paymentQrLabel;
  final String? contactQrPath;
  final String? contactQrUrl;
  final String? contactQrLabel;
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
    return (SubscriptionPlan.normalize(subscriptionPlan) ==
                SubscriptionPlan.pro ||
            SubscriptionPlan.normalize(subscriptionPlan) ==
                SubscriptionPlan.team) &&
        (status == SubscriptionStatus.active ||
            status == SubscriptionStatus.trialing) &&
        !isSubscriptionExpired;
  }

  String get effectiveSubscriptionPlan => hasActivePro
      ? SubscriptionPlan.normalize(subscriptionPlan)
      : SubscriptionPlan.basic;

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
      logoUrl: map['logo_url'] as String?,
      signaturePath: map['signature_path'] as String?,
      signatureUrl: map['signature_url'] as String?,
      paymentQrPath: map['payment_qr_path'] as String?,
      paymentQrUrl: map['payment_qr_url'] as String?,
      paymentQrLabel: map['payment_qr_label'] as String?,
      contactQrPath: map['contact_qr_path'] as String?,
      contactQrUrl: map['contact_qr_url'] as String?,
      contactQrLabel: map['contact_qr_label'] as String?,
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

  ProfileModel copyWith({
    String? id,
    String? fullName,
    String? phone,
    String? specialization,
    String? logoPath,
    String? logoUrl,
    String? signaturePath,
    String? signatureUrl,
    String? paymentQrPath,
    String? paymentQrUrl,
    String? paymentQrLabel,
    String? contactQrPath,
    String? contactQrUrl,
    String? contactQrLabel,
    String? currency,
    String? subscriptionPlan,
    String? subscriptionStatus,
    String? subscriptionSource,
    DateTime? subscriptionRenewsAt,
    bool? pdfShowBrandHeader,
    bool? pdfShowSignatures,
    bool? pdfShowServiceMark,
    String? pdfTemplate,
    String? pdfAccentColor,
    String? pdfPaymentTerms,
    String? pdfFooterNote,
  }) {
    return ProfileModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      specialization: specialization ?? this.specialization,
      logoPath: logoPath ?? this.logoPath,
      logoUrl: logoUrl ?? this.logoUrl,
      signaturePath: signaturePath ?? this.signaturePath,
      signatureUrl: signatureUrl ?? this.signatureUrl,
      paymentQrPath: paymentQrPath ?? this.paymentQrPath,
      paymentQrUrl: paymentQrUrl ?? this.paymentQrUrl,
      paymentQrLabel: paymentQrLabel ?? this.paymentQrLabel,
      contactQrPath: contactQrPath ?? this.contactQrPath,
      contactQrUrl: contactQrUrl ?? this.contactQrUrl,
      contactQrLabel: contactQrLabel ?? this.contactQrLabel,
      currency: currency ?? this.currency,
      subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      subscriptionSource: subscriptionSource ?? this.subscriptionSource,
      subscriptionRenewsAt: subscriptionRenewsAt ?? this.subscriptionRenewsAt,
      pdfShowBrandHeader: pdfShowBrandHeader ?? this.pdfShowBrandHeader,
      pdfShowSignatures: pdfShowSignatures ?? this.pdfShowSignatures,
      pdfShowServiceMark: pdfShowServiceMark ?? this.pdfShowServiceMark,
      pdfTemplate: pdfTemplate ?? this.pdfTemplate,
      pdfAccentColor: pdfAccentColor ?? this.pdfAccentColor,
      pdfPaymentTerms: pdfPaymentTerms ?? this.pdfPaymentTerms,
      pdfFooterNote: pdfFooterNote ?? this.pdfFooterNote,
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

class ProjectModel {
  const ProjectModel({
    required this.id,
    required this.title,
    this.objectAddress,
    this.customerName,
    required this.plannedRevenue,
    required this.startDate,
    this.targetDate,
    required this.status,
    this.notes,
    required this.createdAt,
    this.incomeAmount = 0,
    this.expenseAmount = 0,
  });

  final String id;
  final String title;
  final String? objectAddress;
  final String? customerName;
  final double plannedRevenue;
  final DateTime startDate;
  final DateTime? targetDate;
  final String status;
  final String? notes;
  final DateTime createdAt;
  final double incomeAmount;
  final double expenseAmount;

  double get actualProfit => incomeAmount - expenseAmount;
  double get expectedProfit => plannedRevenue - expenseAmount;

  factory ProjectModel.fromMap(Map<String, dynamic> map) {
    return ProjectModel(
      id: map['id'] as String,
      title: (map['title'] as String?) ?? '',
      objectAddress: map['object_address'] as String?,
      customerName: map['customer_name'] as String?,
      plannedRevenue: asDouble(map['planned_revenue']),
      startDate: asDate(map['start_date']),
      targetDate: asDateOrNull(map['target_date']),
      status: ProjectStatus.normalize(map['status'] as String?),
      notes: map['notes'] as String?,
      createdAt: asDate(map['created_at']),
      incomeAmount: asDouble(map['income_amount']),
      expenseAmount: asDouble(map['expense_amount']),
    );
  }

  ProjectModel copyWith({
    String? title,
    String? objectAddress,
    String? customerName,
    double? plannedRevenue,
    DateTime? startDate,
    DateTime? targetDate,
    String? status,
    String? notes,
    double? incomeAmount,
    double? expenseAmount,
  }) {
    return ProjectModel(
      id: id,
      title: title ?? this.title,
      objectAddress: objectAddress ?? this.objectAddress,
      customerName: customerName ?? this.customerName,
      plannedRevenue: plannedRevenue ?? this.plannedRevenue,
      startDate: startDate ?? this.startDate,
      targetDate: targetDate ?? this.targetDate,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      incomeAmount: incomeAmount ?? this.incomeAmount,
      expenseAmount: expenseAmount ?? this.expenseAmount,
    );
  }
}

class ProjectTransactionModel {
  const ProjectTransactionModel({
    required this.id,
    required this.projectId,
    required this.type,
    required this.category,
    required this.title,
    required this.amount,
    this.quantity,
    this.unit,
    required this.transactionDate,
    this.counterparty,
    this.notes,
  });

  final String id;
  final String projectId;
  final String type;
  final String category;
  final String title;
  final double amount;
  final double? quantity;
  final String? unit;
  final DateTime transactionDate;
  final String? counterparty;
  final String? notes;

  factory ProjectTransactionModel.fromMap(Map<String, dynamic> map) {
    return ProjectTransactionModel(
      id: map['id'] as String,
      projectId: map['project_id'] as String,
      type: ProjectTransactionType.normalize(
        map['transaction_type'] as String?,
      ),
      category: (map['category'] as String?) ?? 'Другое',
      title: (map['title'] as String?) ?? '',
      amount: asDouble(map['amount']),
      quantity: map['quantity'] == null ? null : asDouble(map['quantity']),
      unit: map['unit'] as String?,
      transactionDate: asDate(map['transaction_date']),
      counterparty: map['counterparty'] as String?,
      notes: map['notes'] as String?,
    );
  }
}

class ProjectMaterialModel {
  const ProjectMaterialModel({
    required this.id,
    required this.projectId,
    required this.title,
    required this.plannedQuantity,
    required this.unit,
    required this.plannedUnitPrice,
    this.actualQuantity,
    this.actualAmount,
    this.purchasedAt,
    this.purchaseTransactionId,
    this.notes,
  });

  final String id;
  final String projectId;
  final String title;
  final double plannedQuantity;
  final String unit;
  final double plannedUnitPrice;
  final double? actualQuantity;
  final double? actualAmount;
  final DateTime? purchasedAt;
  final String? purchaseTransactionId;
  final String? notes;

  double get plannedAmount => plannedQuantity * plannedUnitPrice;
  bool get isPurchased => actualAmount != null;

  factory ProjectMaterialModel.fromMap(Map<String, dynamic> map) {
    return ProjectMaterialModel(
      id: map['id'] as String,
      projectId: map['project_id'] as String,
      title: (map['title'] as String?) ?? '',
      plannedQuantity: asDouble(map['planned_quantity']),
      unit: (map['unit'] as String?) ?? 'шт',
      plannedUnitPrice: asDouble(map['planned_unit_price']),
      actualQuantity: map['actual_quantity'] == null
          ? null
          : asDouble(map['actual_quantity']),
      actualAmount: map['actual_amount'] == null
          ? null
          : asDouble(map['actual_amount']),
      purchasedAt: map['purchased_at'] == null
          ? null
          : asDate(map['purchased_at']),
      purchaseTransactionId: map['purchase_transaction_id'] as String?,
      notes: map['notes'] as String?,
    );
  }
}

class ProjectDetail {
  const ProjectDetail({
    required this.project,
    required this.transactions,
    this.materials = const [],
  });

  final ProjectModel project;
  final List<ProjectTransactionModel> transactions;
  final List<ProjectMaterialModel> materials;
}

class ProjectDraft {
  const ProjectDraft({
    required this.title,
    this.objectAddress,
    this.customerName,
    required this.plannedRevenue,
    required this.startDate,
    this.targetDate,
    required this.status,
    this.notes,
  });

  final String title;
  final String? objectAddress;
  final String? customerName;
  final double plannedRevenue;
  final DateTime startDate;
  final DateTime? targetDate;
  final String status;
  final String? notes;
}

class ProjectTransactionDraft {
  const ProjectTransactionDraft({
    required this.type,
    required this.category,
    required this.title,
    required this.amount,
    this.quantity,
    this.unit,
    required this.transactionDate,
    this.counterparty,
    this.notes,
  });

  final String type;
  final String category;
  final String title;
  final double amount;
  final double? quantity;
  final String? unit;
  final DateTime transactionDate;
  final String? counterparty;
  final String? notes;
}

class ProjectMaterialDraft {
  const ProjectMaterialDraft({
    required this.title,
    required this.plannedQuantity,
    required this.unit,
    required this.plannedUnitPrice,
    this.notes,
  });

  final String title;
  final double plannedQuantity;
  final String unit;
  final double plannedUnitPrice;
  final String? notes;
}

class TeamWorkspaceModel {
  const TeamWorkspaceModel({
    required this.id,
    required this.name,
    required this.ownerUserId,
    required this.role,
    required this.maxMembers,
    required this.seatsUsed,
    required this.isActive,
    this.renewsAt,
  });

  final String id;
  final String name;
  final String ownerUserId;
  final String role;
  final int maxMembers;
  final int seatsUsed;
  final bool isActive;
  final DateTime? renewsAt;
  bool get isOwner => role == 'owner';

  factory TeamWorkspaceModel.fromMap(Map<String, dynamic> map) =>
      TeamWorkspaceModel(
        id: map['team_id'] as String,
        name: (map['team_name'] as String?) ?? 'Моя бригада',
        ownerUserId: map['owner_user_id'] as String,
        role: (map['member_role'] as String?) ?? 'member',
        maxMembers: (map['max_members'] as num?)?.toInt() ?? 6,
        seatsUsed: (map['seats_used'] as num?)?.toInt() ?? 1,
        isActive: map['is_active'] == true,
        renewsAt: map['subscription_renews_at'] == null
            ? null
            : asDate(map['subscription_renews_at']),
      );
}

class TeamMemberModel {
  const TeamMemberModel({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
  });
  final String userId;
  final String name;
  final String email;
  final String role;
  bool get isOwner => role == 'owner';
  factory TeamMemberModel.fromMap(Map<String, dynamic> map) => TeamMemberModel(
    userId: map['user_id'] as String,
    name: (map['member_name'] as String?) ?? '',
    email: (map['member_email'] as String?) ?? '',
    role: (map['member_role'] as String?) ?? 'member',
  );
}

class TeamInviteModel {
  const TeamInviteModel({
    required this.id,
    required this.email,
    required this.expiresAt,
  });
  final String id;
  final String email;
  final DateTime expiresAt;
  factory TeamInviteModel.fromMap(Map<String, dynamic> map) => TeamInviteModel(
    id: map['invite_id'] as String,
    email: (map['invited_email'] as String?) ?? '',
    expiresAt: asDate(map['expires_at']),
  );
}

class IncomingTeamInviteModel {
  const IncomingTeamInviteModel({
    required this.id,
    required this.teamName,
    required this.ownerName,
    required this.expiresAt,
  });
  final String id;
  final String teamName;
  final String ownerName;
  final DateTime expiresAt;
  factory IncomingTeamInviteModel.fromMap(Map<String, dynamic> map) =>
      IncomingTeamInviteModel(
        id: map['invite_id'] as String,
        teamName: (map['team_name'] as String?) ?? 'Бригада',
        ownerName: (map['owner_name'] as String?) ?? 'Владелец',
        expiresAt: asDate(map['expires_at']),
      );
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
    this.documentVersion = 1,
    this.revisionOf,
    this.pdfStoragePath,
    this.signedPdfStoragePath,
    this.clientSignaturePath,
    this.clientSignatureUrl,
    this.clientSignedAt,
    this.clientSignedName,
    this.clientSignedPhone,
    this.clientSignatureOtpChallengeId,
    this.clientSignatureMethod,
    this.clientSignatureLinkId,
    this.signedDocumentHash,
    this.clientPhoneVerifiedAt,
    this.clientSignatureStatementVersion,
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
  final int documentVersion;
  final String? revisionOf;
  final String? pdfStoragePath;
  final String? signedPdfStoragePath;
  final String? clientSignaturePath;
  final String? clientSignatureUrl;
  final DateTime? clientSignedAt;
  final String? clientSignedName;
  final String? clientSignedPhone;
  final String? clientSignatureOtpChallengeId;
  final String? clientSignatureMethod;
  final String? clientSignatureLinkId;
  final String? signedDocumentHash;
  final DateTime? clientPhoneVerifiedAt;
  final String? clientSignatureStatementVersion;
  final DateTime createdAt;

  bool get isLocked => clientSignedAt != null;

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
      documentVersion: asIntOrNull(map['document_version']) ?? 1,
      revisionOf: map['revision_of'] as String?,
      pdfStoragePath: map['pdf_storage_path'] as String?,
      signedPdfStoragePath: map['signed_pdf_storage_path'] as String?,
      clientSignaturePath: map['client_signature_path'] as String?,
      clientSignatureUrl: map['client_signature_url'] as String?,
      clientSignedAt: asDateOrNull(map['client_signed_at']),
      clientSignedName: map['client_signed_name'] as String?,
      clientSignedPhone: map['client_signed_phone'] as String?,
      clientSignatureOtpChallengeId:
          map['client_signature_otp_challenge_id'] as String?,
      clientSignatureMethod: map['client_signature_method'] as String?,
      clientSignatureLinkId: map['client_signature_link_id'] as String?,
      signedDocumentHash: map['signed_document_hash'] as String?,
      clientPhoneVerifiedAt: asDateOrNull(map['client_phone_verified_at']),
      clientSignatureStatementVersion:
          map['client_signature_statement_version'] as String?,
      createdAt: asDate(map['created_at']),
    );
  }

  EstimateModel copyWith({
    String? id,
    String? clientId,
    ClientModel? client,
    String? objectTitle,
    DateTime? estimateDate,
    int? durationDays,
    String? status,
    double? totalAmount,
    int? documentVersion,
    String? revisionOf,
    String? pdfStoragePath,
    String? signedPdfStoragePath,
    String? clientSignaturePath,
    String? clientSignatureUrl,
    DateTime? clientSignedAt,
    String? clientSignedName,
    String? clientSignedPhone,
    String? clientSignatureOtpChallengeId,
    String? clientSignatureMethod,
    String? clientSignatureLinkId,
    String? signedDocumentHash,
    DateTime? clientPhoneVerifiedAt,
    String? clientSignatureStatementVersion,
    DateTime? createdAt,
  }) {
    return EstimateModel(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      client: client ?? this.client,
      objectTitle: objectTitle ?? this.objectTitle,
      estimateDate: estimateDate ?? this.estimateDate,
      durationDays: durationDays ?? this.durationDays,
      status: status ?? this.status,
      totalAmount: totalAmount ?? this.totalAmount,
      documentVersion: documentVersion ?? this.documentVersion,
      revisionOf: revisionOf ?? this.revisionOf,
      pdfStoragePath: pdfStoragePath ?? this.pdfStoragePath,
      signedPdfStoragePath: signedPdfStoragePath ?? this.signedPdfStoragePath,
      clientSignaturePath: clientSignaturePath ?? this.clientSignaturePath,
      clientSignatureUrl: clientSignatureUrl ?? this.clientSignatureUrl,
      clientSignedAt: clientSignedAt ?? this.clientSignedAt,
      clientSignedName: clientSignedName ?? this.clientSignedName,
      clientSignedPhone: clientSignedPhone ?? this.clientSignedPhone,
      clientSignatureOtpChallengeId:
          clientSignatureOtpChallengeId ?? this.clientSignatureOtpChallengeId,
      clientSignatureMethod:
          clientSignatureMethod ?? this.clientSignatureMethod,
      clientSignatureLinkId:
          clientSignatureLinkId ?? this.clientSignatureLinkId,
      signedDocumentHash: signedDocumentHash ?? this.signedDocumentHash,
      clientPhoneVerifiedAt:
          clientPhoneVerifiedAt ?? this.clientPhoneVerifiedAt,
      clientSignatureStatementVersion:
          clientSignatureStatementVersion ??
          this.clientSignatureStatementVersion,
      createdAt: createdAt ?? this.createdAt,
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

class EstimateSignatureOtpChallenge {
  const EstimateSignatureOtpChallenge({
    required this.id,
    required this.maskedPhone,
    this.expiresAt,
    this.verifiedAt,
  });

  final String id;
  final String maskedPhone;
  final DateTime? expiresAt;
  final DateTime? verifiedAt;
}

class EstimateApprovalLink {
  const EstimateApprovalLink({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;
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
