import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/data/pdf_service.dart';
import 'package:smetchik/src/data/pdf_templates.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru_RU');
  });

  testWidgets('generates estimate PDFs for every configured template', (
    tester,
  ) async {
    final detail = EstimateDetail(
      estimate: EstimateModel(
        id: '199d3b78-00be-441b-8d88-c1e7707645f8',
        clientId: 'client-1',
        client: ClientModel(
          id: 'client-1',
          name: 'Илья',
          phone: '+7 932 841-02-12',
          objectAddress: 'Россия, Оренбург, улица Геннадия Донковцева, 5',
          notes: null,
          createdAt: DateTime(2026, 7, 10),
        ),
        objectTitle: 'Россия, Оренбург, улица Геннадия Донковцева, 5',
        estimateDate: DateTime(2026, 7, 10),
        durationDays: 14,
        status: EstimateStatus.inProgress,
        totalAmount: 13200,
        createdAt: DateTime(2026, 7, 10),
      ),
      lines: const [
        EstimateLineModel(
          id: 'line-1',
          title: 'Разводка труб водоснабжения',
          unit: 'м',
          quantity: 12,
          unitPrice: 750,
          lineTotal: 9000,
          sortOrder: 0,
        ),
        EstimateLineModel(
          id: 'line-2',
          title: 'Монтаж смесителя',
          unit: 'шт',
          quantity: 1,
          unitPrice: 2400,
          lineTotal: 2400,
          sortOrder: 1,
        ),
        EstimateLineModel(
          id: 'line-3',
          title: 'Герметизация примыканий',
          unit: 'компл.',
          quantity: 1,
          unitPrice: 1800,
          lineTotal: 1800,
          sortOrder: 2,
        ),
      ],
    );

    for (final template in SmetaTemplates.values) {
      final profile = ProfileModel(
        id: 'user-1',
        fullName: 'Илья',
        phone: '+7 932 841-02-12',
        specialization: 'Сантехник',
        currency: 'RUB',
        subscriptionPlan: template.isPremium
            ? SubscriptionPlan.pro
            : SubscriptionPlan.basic,
        subscriptionStatus: SubscriptionStatus.active,
        subscriptionRenewsAt: template.isPremium ? DateTime(2026, 8, 10) : null,
        pdfTemplate: template.id,
        pdfAccentColor: template.colors.accent,
        pdfPaymentTerms: '50% предоплата, остаток после приёмки.',
        pdfFooterNote: 'Смета действует 7 дней.',
      );

      final bytes = await PdfService.buildEstimatePdf(
        detail: detail,
        profile: profile,
      );

      expect(bytes.length, greaterThan(1500), reason: template.id);

      if (const bool.fromEnvironment('WRITE_SAMPLE_PDF') &&
          template.id == SmetaTemplates.coverDeluxe.id) {
        final directory = Directory('tmp/pdfs')..createSync(recursive: true);
        File(
          '${directory.path}/smeta-cover-deluxe.pdf',
        ).writeAsBytesSync(bytes);
      }
    }
  });
}
