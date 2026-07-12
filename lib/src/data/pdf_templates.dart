import 'package:flutter/material.dart';

class SmetaTemplateColors {
  const SmetaTemplateColors({
    required this.background,
    required this.surface,
    required this.primaryText,
    required this.secondaryText,
    required this.accent,
    required this.border,
    this.coverBackground,
    this.coverText,
  });

  final String background;
  final String surface;
  final String primaryText;
  final String secondaryText;
  final String accent;
  final String border;
  final String? coverBackground;
  final String? coverText;
}

class SmetaTemplateLayout {
  const SmetaTemplateLayout({
    required this.headerAlign,
    required this.logoPosition,
    required this.totalsPosition,
    required this.tableStyle,
    required this.cornerStyle,
    required this.dividerStyle,
    this.aspectRatio,
    this.lineHeightMultiplier = 1.25,
  });

  final String headerAlign;
  final String logoPosition;
  final String totalsPosition;
  final String tableStyle;
  final String cornerStyle;
  final String dividerStyle;
  final String? aspectRatio;
  final double lineHeightMultiplier;
}

class SmetaTemplateFeatures {
  const SmetaTemplateFeatures({
    this.showWatermark = false,
    this.watermarkText = 'Сметчик',
    this.watermarkOpacity = 0.08,
    this.showQrPayment = false,
    this.showSignatureLine = true,
    this.showLogo = true,
    this.showStampArea = false,
    this.showCoverPage = false,
    this.allowCustomAccent = true,
    this.allowCustomFont = false,
    this.allowLogoUpload = true,
    this.multilanguage = false,
    this.showProfessionIconBadge = false,
    this.showDocTypeBadge = false,
    this.exportAsImage = false,
    this.totalFontSize,
    this.greetingLine,
    this.specialAccentLine,
    this.accentPresetChoices = const [],
  });

  final bool showWatermark;
  final String watermarkText;
  final double watermarkOpacity;
  final bool showQrPayment;
  final bool showSignatureLine;
  final bool showLogo;
  final bool showStampArea;
  final bool showCoverPage;
  final bool allowCustomAccent;
  final bool allowCustomFont;
  final bool allowLogoUpload;
  final bool multilanguage;
  final bool showProfessionIconBadge;
  final bool showDocTypeBadge;
  final bool exportAsImage;
  final double? totalFontSize;
  final String? greetingLine;
  final String? specialAccentLine;
  final List<String> accentPresetChoices;
}

class SmetaTemplateConfig {
  const SmetaTemplateConfig({
    required this.id,
    required this.name,
    required this.shortName,
    required this.description,
    required this.isPremium,
    required this.colors,
    required this.headingFont,
    required this.bodyFont,
    required this.layout,
    required this.features,
    required this.icon,
  });

  final String id;
  final String name;
  final String shortName;
  final String description;
  final bool isPremium;
  final SmetaTemplateColors colors;
  final String headingFont;
  final String bodyFont;
  final SmetaTemplateLayout layout;
  final SmetaTemplateFeatures features;
  final IconData icon;

  List<String> get accentChoices {
    final values = <String>{colors.accent, ...features.accentPresetChoices};
    return values.toList();
  }
}

class SmetaTemplates {
  const SmetaTemplates._();

  static const standardFree = SmetaTemplateConfig(
    id: 'standard_free',
    name: 'Стандарт',
    shortName: 'Стандарт',
    description: 'бесплатный аккуратный шаблон',
    isPremium: false,
    colors: SmetaTemplateColors(
      background: '#FFFFFF',
      surface: '#F7F7F5',
      primaryText: '#1A1A18',
      secondaryText: '#6B6A64',
      accent: '#2F6FE0',
      border: '#E4E3DE',
    ),
    headingFont: 'Inter',
    bodyFont: 'Inter',
    layout: SmetaTemplateLayout(
      headerAlign: 'left',
      logoPosition: 'left',
      totalsPosition: 'bottom',
      tableStyle: 'compact',
      cornerStyle: 'rounded',
      dividerStyle: 'hairline',
    ),
    features: SmetaTemplateFeatures(
      showWatermark: false,
      showLogo: false,
      allowCustomAccent: false,
      allowCustomFont: false,
      allowLogoUpload: false,
    ),
    icon: Icons.description_outlined,
  );

  static const goldNoir = SmetaTemplateConfig(
    id: 'premium_gold_noir',
    name: 'Тёмный премиум (Gold Noir)',
    shortName: 'Gold Noir',
    description: 'тёмный фон и золотой акцент',
    isPremium: true,
    colors: SmetaTemplateColors(
      background: '#161513',
      surface: '#1F1E1B',
      primaryText: '#F5F3EC',
      secondaryText: '#8F8D84',
      accent: '#C9A24A',
      border: '#33322D',
    ),
    headingFont: 'Playfair Display',
    bodyFont: 'Inter',
    layout: SmetaTemplateLayout(
      headerAlign: 'left',
      logoPosition: 'left',
      totalsPosition: 'bottom',
      tableStyle: 'compact',
      cornerStyle: 'rounded',
      dividerStyle: 'hairline',
    ),
    features: SmetaTemplateFeatures(
      showQrPayment: true,
      specialAccentLine: 'gold-divider-above-total',
    ),
    icon: Icons.workspace_premium_outlined,
  );

  static const whiteSpace = SmetaTemplateConfig(
    id: 'premium_white_space',
    name: 'Минимал+ (White Space)',
    shortName: 'Минимал+',
    description: 'много воздуха, почти без линий',
    isPremium: true,
    colors: SmetaTemplateColors(
      background: '#FFFFFF',
      surface: '#FFFFFF',
      primaryText: '#1A1A18',
      secondaryText: '#8A8A83',
      accent: '#3C3A35',
      border: '#EDEBE4',
    ),
    headingFont: 'Inter',
    bodyFont: 'Inter',
    layout: SmetaTemplateLayout(
      headerAlign: 'left',
      logoPosition: 'left',
      totalsPosition: 'bottom',
      tableStyle: 'compact',
      cornerStyle: 'sharp',
      dividerStyle: 'none',
      lineHeightMultiplier: 1.6,
    ),
    features: SmetaTemplateFeatures(showQrPayment: true),
    icon: Icons.space_dashboard_outlined,
  );

  static const brightAccent = SmetaTemplateConfig(
    id: 'premium_bright_accent',
    name: 'Цветной акцент (Bright Accent)',
    shortName: 'Цветной акцент',
    description: 'карточки работ и яркая шапка',
    isPremium: true,
    colors: SmetaTemplateColors(
      background: '#FFFFFF',
      surface: '#F7F7F5',
      primaryText: '#1A1A18',
      secondaryText: '#6B6A64',
      accent: '#378ADD',
      border: '#E4E3DE',
    ),
    headingFont: 'Inter',
    bodyFont: 'Inter',
    layout: SmetaTemplateLayout(
      headerAlign: 'left',
      logoPosition: 'left',
      totalsPosition: 'bottom',
      tableStyle: 'boxed',
      cornerStyle: 'rounded',
      dividerStyle: 'hairline',
    ),
    features: SmetaTemplateFeatures(
      showQrPayment: true,
      showProfessionIconBadge: true,
      showDocTypeBadge: true,
      allowCustomFont: false,
      accentPresetChoices: ['#378ADD', '#639922', '#D85A30', '#D4537E'],
    ),
    icon: Icons.palette_outlined,
  );

  static const corporateClassic = SmetaTemplateConfig(
    id: 'premium_corporate_classic',
    name: 'Классика делового письма',
    shortName: 'Деловая классика',
    description: 'двойные линии, рамки, подпись и печать',
    isPremium: true,
    colors: SmetaTemplateColors(
      background: '#FFFFFF',
      surface: '#FFFFFF',
      primaryText: '#1A1A18',
      secondaryText: '#5C5C58',
      accent: '#1A1A18',
      border: '#1A1A18',
    ),
    headingFont: 'PT Serif',
    bodyFont: 'Inter',
    layout: SmetaTemplateLayout(
      headerAlign: 'center',
      logoPosition: 'top-center',
      totalsPosition: 'bottom',
      tableStyle: 'detailed',
      cornerStyle: 'sharp',
      dividerStyle: 'double',
    ),
    features: SmetaTemplateFeatures(
      showQrPayment: false,
      showStampArea: true,
      allowCustomAccent: false,
      allowCustomFont: false,
    ),
    icon: Icons.balance_outlined,
  );

  static const invoiceFirst = SmetaTemplateConfig(
    id: 'premium_invoice_first',
    name: 'Инвойс-стиль (Invoice First)',
    shortName: 'Инвойс',
    description: 'итоговая сумма сразу сверху',
    isPremium: true,
    colors: SmetaTemplateColors(
      background: '#FFFFFF',
      surface: '#F5F8FC',
      primaryText: '#1A1A18',
      secondaryText: '#6B6A64',
      accent: '#185FA5',
      border: '#DCE7F4',
    ),
    headingFont: 'Inter',
    bodyFont: 'Inter',
    layout: SmetaTemplateLayout(
      headerAlign: 'left',
      logoPosition: 'left',
      totalsPosition: 'top',
      tableStyle: 'compact',
      cornerStyle: 'rounded',
      dividerStyle: 'hairline',
    ),
    features: SmetaTemplateFeatures(
      showQrPayment: true,
      allowCustomFont: false,
      totalFontSize: 28,
    ),
    icon: Icons.payments_outlined,
  );

  static const craftPaper = SmetaTemplateConfig(
    id: 'premium_craft_paper',
    name: 'Тёплый крафт (Craft Paper)',
    shortName: 'Крафт',
    description: 'тёплая бумага и персональный тон',
    isPremium: true,
    colors: SmetaTemplateColors(
      background: '#F4EEE2',
      surface: '#FBF8F1',
      primaryText: '#3A2E22',
      secondaryText: '#7A6A57',
      accent: '#B0512E',
      border: '#E0D5C0',
    ),
    headingFont: 'Caveat',
    bodyFont: 'Inter',
    layout: SmetaTemplateLayout(
      headerAlign: 'left',
      logoPosition: 'left',
      totalsPosition: 'bottom',
      tableStyle: 'compact',
      cornerStyle: 'rounded',
      dividerStyle: 'bold-dashed',
    ),
    features: SmetaTemplateFeatures(
      showQrPayment: false,
      greetingLine: 'Спасибо за заказ!',
    ),
    icon: Icons.local_florist_outlined,
  );

  static const techGrid = SmetaTemplateConfig(
    id: 'premium_tech_grid',
    name: 'Технологичный (Tech Grid)',
    shortName: 'Tech Grid',
    description: 'сетка и технический акцент',
    isPremium: true,
    colors: SmetaTemplateColors(
      background: '#F2F3F5',
      surface: '#FFFFFF',
      primaryText: '#1A1A18',
      secondaryText: '#6B6A64',
      accent: '#0F6E56',
      border: '#D6D9DE',
    ),
    headingFont: 'Inter',
    bodyFont: 'Inter',
    layout: SmetaTemplateLayout(
      headerAlign: 'left',
      logoPosition: 'left',
      totalsPosition: 'bottom',
      tableStyle: 'grid',
      cornerStyle: 'sharp',
      dividerStyle: 'hairline',
    ),
    features: SmetaTemplateFeatures(
      showQrPayment: true,
      allowCustomFont: false,
    ),
    icon: Icons.grid_on_outlined,
  );

  static const coverDeluxe = SmetaTemplateConfig(
    id: 'premium_cover_deluxe',
    name: 'Фирменный люкс',
    shortName: 'Люкс',
    description: 'выразительная фирменная шапка',
    isPremium: true,
    colors: SmetaTemplateColors(
      background: '#FFFFFF',
      surface: '#FFFFFF',
      primaryText: '#1A1A18',
      secondaryText: '#6B6A64',
      accent: '#3C3489',
      border: '#E4E3DE',
      coverBackground: '#3C3489',
      coverText: '#F5F3EC',
    ),
    headingFont: 'Playfair Display',
    bodyFont: 'Inter',
    layout: SmetaTemplateLayout(
      headerAlign: 'left',
      logoPosition: 'left',
      totalsPosition: 'bottom',
      tableStyle: 'detailed',
      cornerStyle: 'rounded',
      dividerStyle: 'hairline',
    ),
    features: SmetaTemplateFeatures(
      showQrPayment: true,
      accentPresetChoices: ['#3C3489', '#085041'],
    ),
    icon: Icons.auto_awesome_outlined,
  );

  static const storyFormat = SmetaTemplateConfig(
    id: 'premium_story_format',
    name: 'Компактный для соцсетей',
    shortName: 'Story',
    description: 'вертикальный формат для мессенджеров',
    isPremium: true,
    colors: SmetaTemplateColors(
      background: '#FFFFFF',
      surface: '#F7F7F5',
      primaryText: '#1A1A18',
      secondaryText: '#6B6A64',
      accent: '#378ADD',
      border: '#E4E3DE',
    ),
    headingFont: 'Inter',
    bodyFont: 'Inter',
    layout: SmetaTemplateLayout(
      headerAlign: 'center',
      logoPosition: 'top-center',
      totalsPosition: 'top',
      tableStyle: 'compact',
      cornerStyle: 'rounded',
      dividerStyle: 'hairline',
      aspectRatio: '9:16',
    ),
    features: SmetaTemplateFeatures(
      showQrPayment: false,
      showSignatureLine: false,
      allowCustomFont: false,
      totalFontSize: 34,
      exportAsImage: true,
      accentPresetChoices: ['#378ADD', '#639922', '#D85A30', '#D4537E'],
    ),
    icon: Icons.phone_iphone_outlined,
  );

  static const bilingual = SmetaTemplateConfig(
    id: 'premium_bilingual',
    name: 'Мультиязычный экспорт',
    shortName: 'Bilingual',
    description: 'нейтральный стиль для разных языков',
    isPremium: true,
    colors: SmetaTemplateColors(
      background: '#FFFFFF',
      surface: '#FFFFFF',
      primaryText: '#1A1A18',
      secondaryText: '#8A8A83',
      accent: '#5F5E5A',
      border: '#EDEBE4',
    ),
    headingFont: 'Inter',
    bodyFont: 'Inter',
    layout: SmetaTemplateLayout(
      headerAlign: 'left',
      logoPosition: 'left',
      totalsPosition: 'bottom',
      tableStyle: 'compact',
      cornerStyle: 'sharp',
      dividerStyle: 'none',
    ),
    features: SmetaTemplateFeatures(showQrPayment: true, multilanguage: true),
    icon: Icons.translate_outlined,
  );

  static const signedSealed = SmetaTemplateConfig(
    id: 'premium_signed_sealed',
    name: 'Ручная подпись и печать',
    shortName: 'Подпись и печать',
    description: 'юридически более весомый вид',
    isPremium: true,
    colors: SmetaTemplateColors(
      background: '#FFFFFF',
      surface: '#FFFFFF',
      primaryText: '#1A1A18',
      secondaryText: '#5C5C58',
      accent: '#1A1A18',
      border: '#1A1A18',
    ),
    headingFont: 'PT Serif',
    bodyFont: 'Inter',
    layout: SmetaTemplateLayout(
      headerAlign: 'center',
      logoPosition: 'top-center',
      totalsPosition: 'bottom',
      tableStyle: 'detailed',
      cornerStyle: 'sharp',
      dividerStyle: 'double',
    ),
    features: SmetaTemplateFeatures(
      showQrPayment: false,
      showStampArea: true,
      allowCustomAccent: false,
      allowCustomFont: false,
    ),
    icon: Icons.draw_outlined,
  );

  static const values = [
    standardFree,
    goldNoir,
    whiteSpace,
    brightAccent,
    corporateClassic,
    invoiceFirst,
    craftPaper,
    techGrid,
    coverDeluxe,
    storyFormat,
    bilingual,
    signedSealed,
  ];

  static List<SmetaTemplateConfig> get premiumValues =>
      values.where((template) => template.isPremium).toList();

  static List<String> get ids => values.map((template) => template.id).toList();

  static SmetaTemplateConfig byId(String? id) {
    final normalized = normalizeId(id);
    for (final template in values) {
      if (template.id == normalized) return template;
    }
    return standardFree;
  }

  static String normalizeId(String? id) {
    final value = (id ?? '').trim();
    return switch (value) {
      'accent' => brightAccent.id,
      'classic' => corporateClassic.id,
      'compact' => storyFormat.id,
      '' => standardFree.id,
      _ => ids.contains(value) ? value : standardFree.id,
    };
  }

  static String defaultAccentFor(String? templateId) {
    return byId(templateId).colors.accent.toUpperCase();
  }

  static List<String> accentChoicesFor(String? templateId) {
    return byId(
      templateId,
    ).accentChoices.map((value) => value.toUpperCase()).toSet().toList();
  }
}
