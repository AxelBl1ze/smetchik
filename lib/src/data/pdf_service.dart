import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models.dart';
import 'pdf_templates.dart';

class PdfService {
  static pw.Font? _regular;
  static pw.Font? _bold;
  static final Map<String, Future<pw.ImageProvider?>> _remoteImageCache = {};

  static Future<(pw.Font, pw.Font)> _fonts() async {
    _regular ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
    );
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    return (_regular!, _bold!);
  }

  static Future<Uint8List> buildCatalogPdf({
    required List<CatalogItemModel> items,
    required ProfileModel? profile,
  }) async {
    final (regular, bold) = await _fonts();
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final doc = pw.Document(theme: theme);
    final logoImage = await _loadProfileImage(profile?.logoUrl);
    final render = _PdfRenderOptions.fromProfile(profile, logoImage: logoImage);
    final grouped = <String, List<CatalogItemModel>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(render),
        footer: render.showServiceMark ? _serviceFooter : null,
        build: (context) => [
          _documentHeader(
            render: render,
            title: 'Прайс-лист',
            subtitle: 'Услуги и цены для быстрых смет',
            meta: [
              'Дата: ${formatDate(DateTime.now())}',
              'Позиций: ${items.length}',
            ],
          ),
          pw.SizedBox(height: 20),
          for (final entry in grouped.entries) ...[
            _sectionTitle(render, entry.key),
            pw.SizedBox(height: 8),
            _catalogTable(render, entry.value),
            pw.SizedBox(height: 16),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> buildProjectReportPdf({
    required ProjectDetail detail,
    required ProfileModel? profile,
  }) async {
    final (regular, bold) = await _fonts();
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final doc = pw.Document(theme: theme);
    final logoImage = await _loadProfileImage(profile?.logoUrl);
    final render = _PdfRenderOptions.fromProfile(profile, logoImage: logoImage);
    final project = detail.project;
    final expenses = detail.transactions
        .where((item) => item.type == ProjectTransactionType.expense)
        .toList();
    final income = detail.transactions
        .where((item) => item.type == ProjectTransactionType.income)
        .toList();

    doc.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(render),
        footer: render.showServiceMark ? _serviceFooter : null,
        build: (context) => [
          _documentHeader(
            render: render,
            title: 'Отчёт по объекту',
            subtitle: project.title,
            meta: [
              'Статус: ${ProjectStatus.label(project.status)}',
              'Сформировано: ${formatDate(DateTime.now())}',
            ],
          ),
          pw.SizedBox(height: 18),
          _projectDetailsBlock(render, project),
          pw.SizedBox(height: 18),
          _sectionTitle(render, 'Финансовая сводка'),
          pw.SizedBox(height: 8),
          _projectFinanceSummary(render, project),
          pw.SizedBox(height: 18),
          _sectionTitle(render, 'Расходы'),
          pw.SizedBox(height: 8),
          expenses.isEmpty
              ? _noteBlock(render, 'Расходы', 'Расходов по объекту пока нет.')
              : _projectTransactionsTable(render, expenses),
          pw.SizedBox(height: 18),
          _sectionTitle(render, 'Поступления'),
          pw.SizedBox(height: 8),
          income.isEmpty
              ? _noteBlock(
                  render,
                  'Поступления',
                  'Поступлений по объекту пока нет.',
                )
              : _projectTransactionsTable(render, income),
          if (project.notes?.trim().isNotEmpty == true) ...[
            pw.SizedBox(height: 18),
            _noteBlock(render, 'Заметка по объекту', project.notes!.trim()),
          ],
        ],
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> buildEstimatePdf({
    required EstimateDetail detail,
    required ProfileModel? profile,
    Uint8List? clientSignatureBytes,
  }) async {
    final (regular, bold) = await _fonts();
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final doc = pw.Document(theme: theme);
    final images = await Future.wait<pw.ImageProvider?>([
      _loadProfileImage(profile?.logoUrl),
      _loadProfileImage(profile?.signatureUrl),
      _loadProfileImage(detail.estimate.clientSignatureUrl),
      if (profile?.hasActivePro == true)
        _loadProfileImage(profile?.paymentQrUrl)
      else
        Future.value(),
      if (profile?.hasActivePro == true)
        _loadProfileImage(profile?.contactQrUrl)
      else
        Future.value(),
    ]);
    final render = _PdfRenderOptions.fromProfile(
      profile,
      logoImage: images[0],
      signatureImage: images[1],
      clientSignatureImage: clientSignatureBytes == null
          ? images[2]
          : pw.MemoryImage(clientSignatureBytes),
      paymentQrImage: images[3],
      contactQrImage: images[4],
    );
    final estimate = detail.estimate;

    if (render.template.features.showCoverPage) {
      doc.addPage(
        pw.Page(
          pageFormat: _pageFormat(render),
          margin: pw.EdgeInsets.zero,
          build: (context) => _coverPage(render, detail),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageTheme: _pageTheme(render),
        footer: render.showServiceMark ? _serviceFooter : null,
        build: (context) {
          final blocks = <pw.Widget>[
            _documentHeader(
              render: render,
              title: render.template.features.showDocTypeBadge
                  ? 'КП / смета'
                  : 'Коммерческое предложение',
              subtitle: estimate.objectTitle,
              meta: [
                'Дата: ${formatDate(estimate.estimateDate)}',
                'Смета: ${estimate.id.substring(0, 8).toUpperCase()}',
                'Версия: ${estimate.documentVersion}',
              ],
            ),
            pw.SizedBox(height: render.isStory ? 14 : 22),
          ];

          if (render.template.layout.totalsPosition == 'top') {
            blocks.add(_totalBlock(render, estimate.totalAmount, wide: true));
            blocks.add(pw.SizedBox(height: 14));
          }

          blocks.add(_detailsBlock(render, detail));
          blocks.add(pw.SizedBox(height: 18));
          blocks.add(_sectionTitle(render, 'Работы'));
          blocks.add(pw.SizedBox(height: 8));
          blocks.add(_estimateLines(render, detail.lines));
          blocks.add(pw.SizedBox(height: 16));

          if (render.paymentTerms?.isNotEmpty == true) {
            blocks.add(
              _noteBlock(render, 'Условия оплаты', render.paymentTerms!),
            );
            blocks.add(pw.SizedBox(height: 10));
          }
          if (render.footerNote?.isNotEmpty == true) {
            blocks.add(_noteBlock(render, 'Примечание', render.footerNote!));
            blocks.add(pw.SizedBox(height: 10));
          }
          if (render.template.features.greetingLine?.isNotEmpty == true) {
            blocks.add(
              _greeting(render, render.template.features.greetingLine!),
            );
            blocks.add(pw.SizedBox(height: 10));
          }
          if (render.template.layout.totalsPosition != 'top') {
            blocks.add(
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [_totalBlock(render, estimate.totalAmount)],
              ),
            );
          }
          if (render.hasQrBlocks) {
            blocks.add(pw.SizedBox(height: 16));
            blocks.add(_qrBlocks(render));
          }
          if ((render.showSignatures &&
                  render.template.features.showSignatureLine) ||
              render.clientSignatureImage != null) {
            blocks.add(pw.SizedBox(height: 38));
            blocks.add(_signatures(render, estimate));
          }
          if (render.template.features.showStampArea) {
            blocks.add(pw.SizedBox(height: 18));
            blocks.add(_stampArea(render));
          }
          return blocks;
        },
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> buildCompletionActPdf({
    required EstimateDetail detail,
    required ProfileModel? profile,
  }) async {
    final (regular, bold) = await _fonts();
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final doc = pw.Document(theme: theme);
    final images = await Future.wait<pw.ImageProvider?>([
      _loadProfileImage(profile?.logoUrl),
      _loadProfileImage(profile?.signatureUrl),
      _loadProfileImage(detail.estimate.clientSignatureUrl),
      _loadProfileImage(profile?.contactQrUrl),
    ]);
    final estimate = detail.estimate;
    final render = _PdfRenderOptions.fromProfile(
      profile,
      logoImage: images[0],
      signatureImage: images[1],
      clientSignatureImage: images[2],
      contactQrImage: images[3],
    ).formalDocument();

    doc.addPage(
      pw.MultiPage(
        pageTheme: _formalPageTheme(render),
        footer: render.showServiceMark ? _serviceFooter : null,
        build: (context) => [
          _documentHeader(
            render: render,
            title: 'Акт выполненных работ',
            subtitle: estimate.objectTitle,
            meta: [
              'Дата: ${formatDate(DateTime.now())}',
              'К смете: ${estimate.id.substring(0, 8).toUpperCase()}',
              'Версия сметы: ${estimate.documentVersion}',
            ],
          ),
          pw.SizedBox(height: 20),
          _actIntro(render, estimate),
          pw.SizedBox(height: 18),
          _sectionTitle(render, 'Выполненные работы'),
          pw.SizedBox(height: 8),
          _estimateLines(render, detail.lines),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [_totalBlock(render, estimate.totalAmount)],
          ),
          pw.SizedBox(height: 22),
          _noteBlock(
            render,
            'Подтверждение сторон',
            'Заказчик подтверждает, что работы приняты в полном объёме. Претензии по объёму и качеству на дату подписания отсутствуют.',
          ),
          if (render.contactQrImage != null) ...[
            pw.SizedBox(height: 18),
            _sectionTitle(render, 'Связаться с исполнителем'),
            pw.SizedBox(height: 8),
            _qrBlocks(render),
          ],
          pw.SizedBox(height: 30),
          _signatures(render, estimate),
        ],
      ),
    );
    return doc.save();
  }

  static Future<pw.ImageProvider?> _loadProfileImage(String? value) async {
    final url = value?.trim();
    if (url == null || url.isEmpty) return null;
    return _remoteImageCache.putIfAbsent(url, () async {
      try {
        return await networkImage(url);
      } catch (_) {
        return null;
      }
    });
  }

  static pw.PageTheme _pageTheme(_PdfRenderOptions render) {
    return pw.PageTheme(
      pageFormat: _pageFormat(render),
      margin: _pageMargin(render),
      buildBackground: render.hasColoredPageBackground
          ? (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Container(color: render.background),
            )
          : null,
      buildForeground: render.template.features.showWatermark
          ? (context) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Center(
                child: pw.Transform.rotate(
                  angle: -0.55,
                  child: pw.Opacity(
                    opacity: render.template.features.watermarkOpacity,
                    child: pw.Text(
                      render.template.features.watermarkText,
                      style: pw.TextStyle(
                        color: render.primaryText,
                        fontSize: 84,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  static pw.PageTheme _formalPageTheme(_PdfRenderOptions render) {
    return pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(34, 34, 34, 38),
    );
  }

  static PdfPageFormat _pageFormat(_PdfRenderOptions render) {
    if (render.template.layout.aspectRatio == '9:16') {
      return PdfPageFormat(540, 960);
    }
    return PdfPageFormat.a4;
  }

  static pw.EdgeInsets _pageMargin(_PdfRenderOptions render) {
    if (render.isStory) return const pw.EdgeInsets.fromLTRB(26, 28, 26, 30);
    return switch (render.template.layout.cornerStyle) {
      'sharp' => const pw.EdgeInsets.fromLTRB(34, 34, 34, 34),
      _ => const pw.EdgeInsets.fromLTRB(32, 32, 32, 36),
    };
  }

  static pw.Widget _coverPage(_PdfRenderOptions render, EstimateDetail detail) {
    final coverBg = _pdfColor(
      render.template.colors.coverBackground ?? render.template.colors.accent,
    );
    final coverText = _pdfColor(
      render.template.colors.coverText ?? render.template.colors.primaryText,
    );
    return pw.Container(
      color: coverBg,
      padding: const pw.EdgeInsets.all(46),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _logoMark(render, large: true, foreground: coverText),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Коммерческое предложение',
                style: pw.TextStyle(
                  color: coverText,
                  fontSize: 34,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                detail.estimate.objectTitle,
                style: pw.TextStyle(color: coverText, fontSize: 16),
              ),
              if (detail.estimate.client?.name.trim().isNotEmpty == true)
                pw.Text(
                  'Клиент: ${detail.estimate.client!.name}',
                  style: pw.TextStyle(color: coverText, fontSize: 14),
                ),
            ],
          ),
          pw.Text(
            formatDate(detail.estimate.estimateDate),
            style: pw.TextStyle(color: coverText, fontSize: 14),
          ),
        ],
      ),
    );
  }

  static pw.Widget _documentHeader({
    required _PdfRenderOptions render,
    required String title,
    required String? subtitle,
    required List<String> meta,
  }) {
    final centered = render.template.layout.headerAlign == 'center';
    final headerContent = centered
        ? pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              _logoMark(render),
              pw.SizedBox(height: 10),
              _headerText(render, title, subtitle, centered: true),
              pw.SizedBox(height: 8),
              _metaColumn(render, meta, centered: true),
            ],
          )
        : pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (render.template.features.showLogo) ...[
                _logoMark(render),
                pw.SizedBox(width: 12),
              ],
              pw.Expanded(child: _headerText(render, title, subtitle)),
              pw.SizedBox(width: 14),
              _metaColumn(render, meta),
            ],
          );

    return pw.Container(
      padding: pw.EdgeInsets.all(render.isStory ? 12 : 16),
      decoration: pw.BoxDecoration(
        color: render.headerSurface,
        borderRadius: pw.BorderRadius.circular(render.radius),
        border: pw.Border.all(color: render.border),
      ),
      child: headerContent,
    );
  }

  static pw.Widget _headerText(
    _PdfRenderOptions render,
    String title,
    String? subtitle, {
    bool centered = false,
  }) {
    return pw.Column(
      crossAxisAlignment: centered
          ? pw.CrossAxisAlignment.center
          : pw.CrossAxisAlignment.start,
      children: [
        if (render.showBrandHeader)
          pw.Text(
            'Сметчик',
            textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left,
            style: pw.TextStyle(
              color: render.headerText,
              fontSize: render.isStory ? 18 : 22,
              fontWeight: pw.FontWeight.bold,
            ),
          )
        else
          pw.Text(
            render.masterName,
            textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left,
            style: pw.TextStyle(
              color: render.headerText,
              fontSize: render.isStory ? 18 : 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        pw.SizedBox(height: 4),
        pw.Text(
          title,
          textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left,
          style: pw.TextStyle(
            color: render.headerText,
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (subtitle?.trim().isNotEmpty == true) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            subtitle!.trim(),
            textAlign: centered ? pw.TextAlign.center : pw.TextAlign.left,
            style: pw.TextStyle(color: render.headerMuted, fontSize: 10),
          ),
        ],
        if (!render.showBrandHeader &&
            render.profile?.phone?.trim().isNotEmpty == true)
          pw.Text(
            render.profile!.phone!.trim(),
            style: pw.TextStyle(color: render.headerMuted, fontSize: 10),
          ),
      ],
    );
  }

  static pw.Widget _logoMark(
    _PdfRenderOptions render, {
    bool large = false,
    PdfColor? foreground,
  }) {
    final size = large ? 64.0 : 38.0;
    final iconSize = large ? 26.0 : 15.0;
    final color = foreground ?? render.headerText;
    final logoImage = render.logoImage;
    if (logoImage != null) {
      return pw.Container(
        width: size,
        height: size,
        padding: pw.EdgeInsets.all(large ? 7 : 4),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(large ? 18 : 12),
          border: pw.Border.all(color: render.border),
        ),
        child: pw.Center(
          child: pw.Image(
            logoImage,
            width: size - (large ? 14 : 8),
            height: size - (large ? 14 : 8),
            fit: pw.BoxFit.contain,
          ),
        ),
      );
    }

    return pw.Container(
      width: size,
      height: size,
      decoration: pw.BoxDecoration(
        color: render.accent,
        borderRadius: pw.BorderRadius.circular(large ? 18 : 12),
      ),
      child: pw.Center(
        child: pw.Text(
          'С',
          style: pw.TextStyle(
            color: color,
            fontSize: iconSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  static pw.Widget _metaColumn(
    _PdfRenderOptions render,
    List<String> meta, {
    bool centered = false,
  }) {
    return pw.Column(
      crossAxisAlignment: centered
          ? pw.CrossAxisAlignment.center
          : pw.CrossAxisAlignment.end,
      children: [
        for (final value in meta)
          pw.Text(
            value,
            textAlign: centered ? pw.TextAlign.center : pw.TextAlign.right,
            style: pw.TextStyle(color: render.headerMuted, fontSize: 9),
          ),
      ],
    );
  }

  static pw.Widget _detailsBlock(
    _PdfRenderOptions render,
    EstimateDetail detail,
  ) {
    final estimate = detail.estimate;
    final client = [
      estimate.client?.name,
      estimate.client?.phone,
      estimate.client?.objectAddress,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join('\n');

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: render.surface,
        borderRadius: pw.BorderRadius.circular(render.radius),
        border: pw.Border.all(color: render.border),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _infoBlock(render, 'Объект', estimate.objectTitle),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(child: _infoBlock(render, 'Клиент', client)),
        ],
      ),
    );
  }

  static pw.Widget _actIntro(_PdfRenderOptions render, EstimateModel estimate) {
    final master = [
      render.masterName,
      render.profile?.specialization?.trim(),
      render.profile?.phone?.trim(),
    ].whereType<String>().where((value) => value.isNotEmpty).join(', ');
    final customer = [
      estimate.clientSignedName ?? estimate.client?.name,
      estimate.clientSignedPhone ?? estimate.client?.phone,
      estimate.client?.objectAddress,
    ].whereType<String>().where((value) => value.isNotEmpty).join(', ');
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: render.surface,
        borderRadius: pw.BorderRadius.circular(render.radius),
        border: pw.Border.all(color: render.border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Исполнитель: ${master.isEmpty ? 'не указан' : master}',
            style: pw.TextStyle(color: render.primaryText, fontSize: 10),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'Заказчик: ${customer.isEmpty ? 'не указан' : customer}',
            style: pw.TextStyle(color: render.primaryText, fontSize: 10),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'Объект: ${estimate.objectTitle}',
            style: pw.TextStyle(color: render.primaryText, fontSize: 10),
          ),
        ],
      ),
    );
  }

  static pw.Widget _projectDetailsBlock(
    _PdfRenderOptions render,
    ProjectModel project,
  ) {
    final schedule = [
      'Начало: ${formatDate(project.startDate)}',
      if (project.targetDate != null)
        'План: ${formatDate(project.targetDate!)}',
    ].join('\n');
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: render.surface,
        borderRadius: pw.BorderRadius.circular(render.radius),
        border: pw.Border.all(color: render.border),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _infoBlock(
              render,
              'Адрес объекта',
              project.objectAddress ?? '',
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: _infoBlock(
              render,
              'Заказчик / владелец',
              project.customerName ?? '',
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(child: _infoBlock(render, 'Сроки', schedule)),
        ],
      ),
    );
  }

  static pw.Widget _infoBlock(
    _PdfRenderOptions render,
    String label,
    String value,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: render.secondaryText,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          value.isEmpty ? 'Не указан' : value,
          style: pw.TextStyle(
            fontSize: 11,
            color: render.primaryText,
            lineSpacing: 2,
          ),
        ),
      ],
    );
  }

  static pw.Widget _sectionTitle(_PdfRenderOptions render, String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        color: render.primaryText,
        fontSize: render.isStory ? 14 : 16,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  static pw.Widget _estimateLines(
    _PdfRenderOptions render,
    List<EstimateLineModel> lines,
  ) {
    return switch (render.template.layout.tableStyle) {
      'boxed' => _boxedLines(render, lines),
      'grid' => _tableLines(render, lines, grid: true),
      'detailed' => _tableLines(render, lines, detailed: true),
      _ => _tableLines(render, lines),
    };
  }

  static pw.Widget _catalogTable(
    _PdfRenderOptions render,
    List<CatalogItemModel> items,
  ) {
    return pw.TableHelper.fromTextArray(
      border: _tableBorder(render),
      headerDecoration: pw.BoxDecoration(color: render.tableHeader),
      headerStyle: _tableHeaderStyle(render),
      cellStyle: pw.TextStyle(color: render.primaryText, fontSize: 10),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FlexColumnWidth(4),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1.5),
      },
      headers: ['Услуга', 'Ед.', 'Цена'],
      data: [
        for (final item in items)
          [item.title, item.unit, formatMoney(item.unitPrice)],
      ],
    );
  }

  static pw.Widget _projectFinanceSummary(
    _PdfRenderOptions render,
    ProjectModel project,
  ) {
    final expectedColor = project.expectedProfit >= 0
        ? render.accent
        : PdfColors.red700;
    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _projectMetric(render, 'Плановая выручка', project.plannedRevenue),
        _projectMetric(render, 'Получено', project.incomeAmount),
        _projectMetric(render, 'Потрачено', project.expenseAmount),
        _projectMetric(
          render,
          'Ожидаемая прибыль',
          project.expectedProfit,
          valueColor: expectedColor,
        ),
      ],
    );
  }

  static pw.Widget _projectMetric(
    _PdfRenderOptions render,
    String label,
    double value, {
    PdfColor? valueColor,
  }) {
    return pw.Container(
      width: 125,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: render.surface,
        borderRadius: pw.BorderRadius.circular(render.radius),
        border: pw.Border.all(color: render.border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(color: render.secondaryText, fontSize: 8),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            formatMoney(value),
            style: pw.TextStyle(
              color: valueColor ?? render.primaryText,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _projectTransactionsTable(
    _PdfRenderOptions render,
    List<ProjectTransactionModel> transactions,
  ) {
    return pw.TableHelper.fromTextArray(
      border: _tableBorder(render, grid: true),
      headerDecoration: pw.BoxDecoration(color: render.tableHeader),
      headerStyle: _tableHeaderStyle(render).copyWith(fontSize: 8),
      cellStyle: pw.TextStyle(color: render.primaryText, fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.center,
        4: pw.Alignment.centerLeft,
        5: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FlexColumnWidth(1.1),
        1: const pw.FlexColumnWidth(2.4),
        2: const pw.FlexColumnWidth(1.45),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(1.45),
        5: const pw.FlexColumnWidth(1.2),
      },
      headers: [
        'Дата',
        'Операция',
        'Категория',
        'Кол-во',
        'Контрагент',
        'Сумма',
      ],
      data: [
        for (final item in transactions)
          [
            formatDate(item.transactionDate),
            item.title,
            item.category,
            item.quantity == null
                ? '—'
                : '${formatQuantity(item.quantity!)} ${item.unit?.trim() ?? ''}'
                      .trim(),
            item.counterparty?.trim().isNotEmpty == true
                ? item.counterparty!.trim()
                : '—',
            formatMoney(item.amount),
          ],
      ],
    );
  }

  static pw.Widget _tableLines(
    _PdfRenderOptions render,
    List<EstimateLineModel> lines, {
    bool grid = false,
    bool detailed = false,
  }) {
    return pw.TableHelper.fromTextArray(
      border: _tableBorder(render, grid: grid || detailed),
      headerDecoration: pw.BoxDecoration(color: render.tableHeader),
      headerStyle: _tableHeaderStyle(render),
      cellStyle: pw.TextStyle(color: render.primaryText, fontSize: 10),
      cellPadding: pw.EdgeInsets.symmetric(
        horizontal: detailed ? 7 : 6,
        vertical: detailed ? 8 : 6,
      ),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: pw.FlexColumnWidth(detailed ? 3.2 : 3),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
      },
      headers: detailed
          ? ['Работа / описание', 'Ед.', 'Цена', 'Сумма']
          : ['Работа', 'Кол-во', 'Цена', 'Сумма'],
      data: [
        for (final line in lines)
          [
            line.title,
            detailed ? line.unit : '${_formatQty(line.quantity)} ${line.unit}',
            formatMoney(line.unitPrice),
            formatMoney(line.lineTotal),
          ],
      ],
    );
  }

  static pw.Widget _boxedLines(
    _PdfRenderOptions render,
    List<EstimateLineModel> lines,
  ) {
    return pw.Column(
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: render.surface,
              borderRadius: pw.BorderRadius.circular(render.radius),
              border: pw.Border.all(color: render.border),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 24,
                  height: 24,
                  decoration: pw.BoxDecoration(
                    color: render.accent,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      '${i + 1}',
                      style: pw.TextStyle(
                        color: render.accentText,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        lines[i].title,
                        style: pw.TextStyle(
                          color: render.primaryText,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        '${_formatQty(lines[i].quantity)} ${lines[i].unit} x ${formatMoney(lines[i].unitPrice)}',
                        style: pw.TextStyle(
                          color: render.secondaryText,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Text(
                  formatMoney(lines[i].lineTotal),
                  style: pw.TextStyle(
                    color: render.primaryText,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (i != lines.length - 1) pw.SizedBox(height: 8),
        ],
      ],
    );
  }

  static pw.TableBorder _tableBorder(
    _PdfRenderOptions render, {
    bool grid = false,
  }) {
    if (render.template.layout.dividerStyle == 'none') {
      return const pw.TableBorder();
    }
    final side = pw.BorderSide(
      color: render.border,
      width: render.template.layout.dividerStyle == 'double' ? 1.2 : 0.7,
    );
    if (grid || render.template.layout.dividerStyle == 'double') {
      return pw.TableBorder.all(color: render.border, width: side.width);
    }
    return pw.TableBorder(horizontalInside: side, top: side, bottom: side);
  }

  static pw.TextStyle _tableHeaderStyle(_PdfRenderOptions render) {
    return pw.TextStyle(
      color: render.tableHeaderText,
      fontWeight: pw.FontWeight.bold,
      fontSize: 10,
    );
  }

  static pw.Widget _totalBlock(
    _PdfRenderOptions render,
    double total, {
    bool wide = false,
  }) {
    return pw.Container(
      width: wide ? double.infinity : 230,
      padding: pw.EdgeInsets.all(wide ? 18 : 14),
      decoration: pw.BoxDecoration(
        color: render.accent,
        borderRadius: pw.BorderRadius.circular(render.radius),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Итого',
            style: pw.TextStyle(color: render.accentText, fontSize: 11),
          ),
          pw.Text(
            formatMoney(total),
            style: pw.TextStyle(
              color: render.accentText,
              fontSize:
                  render.template.features.totalFontSize ?? (wide ? 22 : 16),
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _noteBlock(
    _PdfRenderOptions render,
    String label,
    String value,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: render.surface,
        borderRadius: pw.BorderRadius.circular(render.radius),
        border: pw.Border.all(color: render.border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              color: render.accent,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(color: render.primaryText, fontSize: 10),
          ),
        ],
      ),
    );
  }

  static pw.Widget _greeting(_PdfRenderOptions render, String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        color: render.accent,
        fontSize: 16,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  static pw.Widget _signatures(
    _PdfRenderOptions render,
    EstimateModel estimate,
  ) {
    final masterDetails = [
      render.profile?.specialization?.trim(),
      render.profile?.phone?.trim(),
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return pw.Row(
      children: [
        _signature(
          render,
          'Исполнитель',
          signerName: render.masterName,
          details: masterDetails,
        ),
        pw.SizedBox(width: 32),
        _signature(
          render,
          'Заказчик',
          signerName: estimate.clientSignedName ?? estimate.client?.name,
          signedAt: estimate.clientSignedAt,
          phoneVerifiedAt: estimate.clientPhoneVerifiedAt,
        ),
      ],
    );
  }

  static pw.Widget _signature(
    _PdfRenderOptions render,
    String label, {
    String? signerName,
    String? details,
    DateTime? signedAt,
    DateTime? phoneVerifiedAt,
  }) {
    final signatureImage = label == 'Исполнитель'
        ? render.signatureImage
        : label == 'Заказчик'
        ? render.clientSignatureImage
        : null;
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (signatureImage != null) ...[
            pw.Container(
              height: 38,
              alignment: pw.Alignment.centerLeft,
              child: pw.Image(
                signatureImage,
                width: 128,
                height: 36,
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 2),
          ],
          pw.Container(height: 1, color: render.border),
          pw.SizedBox(height: 4),
          pw.Text(
            signerName?.trim().isNotEmpty == true
                ? '$label: $signerName'
                : label,
            style: pw.TextStyle(color: render.secondaryText, fontSize: 9),
          ),
          if (details?.trim().isNotEmpty == true) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              details!.trim(),
              style: pw.TextStyle(color: render.secondaryText, fontSize: 8),
            ),
          ],
          if (signedAt != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              'Подписано: ${formatDateTime(signedAt)}',
              style: pw.TextStyle(color: render.secondaryText, fontSize: 8),
            ),
          ],
          if (phoneVerifiedAt != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              'Номер подтверждён: ${formatDateTime(phoneVerifiedAt)}',
              style: pw.TextStyle(color: render.secondaryText, fontSize: 8),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _stampArea(_PdfRenderOptions render) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 120,
        height: 58,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: render.accent, width: 1.1),
          borderRadius: pw.BorderRadius.circular(render.radius),
        ),
        child: pw.Center(
          child: pw.Text(
            'место печати',
            style: pw.TextStyle(color: render.accent, fontSize: 10),
          ),
        ),
      ),
    );
  }

  static pw.Widget _qrBlocks(_PdfRenderOptions render) {
    final blocks = <pw.Widget>[
      if (render.paymentQrImage != null)
        _qrBlock(
          render,
          image: render.paymentQrImage!,
          title: 'Оплата',
          label: render.paymentQrLabel,
        ),
      if (render.contactQrImage != null)
        _qrBlock(
          render,
          image: render.contactQrImage!,
          title: 'Связаться',
          label: render.contactQrLabel,
        ),
    ];

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final block in blocks) ...[
          pw.Container(width: 148, child: block),
          if (block != blocks.last) pw.SizedBox(width: 10),
        ],
      ],
    );
  }

  static pw.Widget _qrBlock(
    _PdfRenderOptions render, {
    required pw.ImageProvider image,
    required String title,
    required String label,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: render.surface,
        borderRadius: pw.BorderRadius.circular(render.radius),
        border: pw.Border.all(color: render.border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 54,
                height: 54,
                padding: const pw.EdgeInsets.all(3),
                color: PdfColors.white,
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      title,
                      style: pw.TextStyle(
                        color: render.primaryText,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      label,
                      style: pw.TextStyle(
                        color: render.secondaryText,
                        fontSize: 8,
                        lineSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _serviceFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 12),
      child: pw.Text(
        'Составлено в Сметчик',
        style: pw.TextStyle(fontSize: 9, color: PdfColor.fromHex('#888780')),
      ),
    );
  }

  static String _formatQty(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  static PdfColor _pdfColor(String hex) => PdfColor.fromHex(hex);
}

class _PdfRenderOptions {
  _PdfRenderOptions({
    required this.profile,
    required this.template,
    required this.accentHex,
    required this.showBrandHeader,
    required this.showSignatures,
    required this.showServiceMark,
    required this.paymentTerms,
    required this.footerNote,
    required this.logoImage,
    required this.signatureImage,
    required this.clientSignatureImage,
    required this.paymentQrImage,
    required this.contactQrImage,
  });

  final ProfileModel? profile;
  final SmetaTemplateConfig template;
  final String accentHex;
  final bool showBrandHeader;
  final bool showSignatures;
  final bool showServiceMark;
  final String? paymentTerms;
  final String? footerNote;
  final pw.ImageProvider? logoImage;
  final pw.ImageProvider? signatureImage;
  final pw.ImageProvider? clientSignatureImage;
  final pw.ImageProvider? paymentQrImage;
  final pw.ImageProvider? contactQrImage;

  factory _PdfRenderOptions.fromProfile(
    ProfileModel? profile, {
    pw.ImageProvider? logoImage,
    pw.ImageProvider? signatureImage,
    pw.ImageProvider? clientSignatureImage,
    pw.ImageProvider? paymentQrImage,
    pw.ImageProvider? contactQrImage,
  }) {
    final hasPro = profile?.hasActivePro == true;
    final template = hasPro
        ? SmetaTemplates.byId(profile?.pdfTemplate)
        : SmetaTemplates.standardFree;
    final accent = hasPro && template.features.allowCustomAccent
        ? PdfAccentColor.normalize(profile?.pdfAccentColor)
        : template.colors.accent.toUpperCase();
    return _PdfRenderOptions(
      profile: profile,
      template: template,
      accentHex: accent,
      showBrandHeader: !hasPro,
      showSignatures: !hasPro || profile?.pdfShowSignatures == true,
      showServiceMark: !hasPro,
      paymentTerms: hasPro ? profile?.pdfPaymentTerms?.trim() : null,
      footerNote: hasPro ? profile?.pdfFooterNote?.trim() : null,
      logoImage: logoImage,
      signatureImage: signatureImage,
      clientSignatureImage: clientSignatureImage,
      paymentQrImage: paymentQrImage,
      contactQrImage: contactQrImage,
    );
  }

  _PdfRenderOptions formalDocument() {
    return _PdfRenderOptions(
      profile: profile,
      template: SmetaTemplates.standardFree,
      accentHex: accentHex,
      showBrandHeader: showBrandHeader,
      showSignatures: true,
      showServiceMark: showServiceMark,
      paymentTerms: null,
      footerNote: null,
      logoImage: logoImage,
      signatureImage: signatureImage,
      clientSignatureImage: clientSignatureImage,
      paymentQrImage: null,
      contactQrImage: contactQrImage,
    );
  }

  String get masterName => profile?.fullName.trim().isNotEmpty == true
      ? profile!.fullName.trim()
      : 'Сметчик';

  bool get isStory => template.layout.aspectRatio == '9:16';
  bool get hasColoredPageBackground =>
      template.colors.background.toUpperCase() != '#FFFFFF' &&
      !template.features.showCoverPage;
  bool get hasQrBlocks => paymentQrImage != null || contactQrImage != null;
  String get paymentQrLabel =>
      profile?.paymentQrLabel?.trim().isNotEmpty == true
      ? profile!.paymentQrLabel!.trim()
      : 'Оплата по QR';
  String get contactQrLabel =>
      profile?.contactQrLabel?.trim().isNotEmpty == true
      ? profile!.contactQrLabel!.trim()
      : 'Связаться с мастером';

  PdfColor get background => template.features.showCoverPage
      ? PdfColor.fromHex(template.colors.surface)
      : PdfColor.fromHex(template.colors.background);
  PdfColor get surface => PdfColor.fromHex(template.colors.surface);
  PdfColor get primaryText => PdfColor.fromHex(template.colors.primaryText);
  PdfColor get secondaryText => PdfColor.fromHex(template.colors.secondaryText);
  PdfColor get accent => PdfColor.fromHex(accentHex);
  PdfColor get border => PdfColor.fromHex(template.colors.border);

  PdfColor get accentText => _isDark(accentHex) ? PdfColors.white : primaryText;

  PdfColor get headerSurface {
    if (template.layout.dividerStyle == 'none') return surface;
    if (template.id == SmetaTemplates.standardFree.id) return surface;
    return accent;
  }

  PdfColor get headerText =>
      _isDarkColor(headerSurface) ? PdfColors.white : primaryText;
  PdfColor get headerMuted =>
      _isDarkColor(headerSurface) ? PdfColors.white : secondaryText;
  PdfColor get tableHeader =>
      template.layout.dividerStyle == 'none' ? background : accent;
  PdfColor get tableHeaderText =>
      _isDarkColor(tableHeader) ? PdfColors.white : primaryText;

  double get radius => switch (template.layout.cornerStyle) {
    'sharp' => 0,
    'pill' => 18,
    _ => 10,
  };

  static bool _isDark(String hex) {
    final value = hex.replaceFirst('#', '');
    final red = int.parse(value.substring(0, 2), radix: 16);
    final green = int.parse(value.substring(2, 4), radix: 16);
    final blue = int.parse(value.substring(4, 6), radix: 16);
    return (red * 0.299 + green * 0.587 + blue * 0.114) < 150;
  }

  static bool _isDarkColor(PdfColor color) {
    return (color.red * 255 * 0.299 +
            color.green * 255 * 0.587 +
            color.blue * 255 * 0.114) <
        150;
  }
}
