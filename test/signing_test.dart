import 'package:flutter_test/flutter_test.dart';
import 'package:smetchik/src/data/models.dart';
import 'package:smetchik/src/data/signing.dart';

void main() {
  test('captures the signed document facts and acceptance statement', () {
    final detail = EstimateDetail(
      estimate: EstimateModel(
        id: 'estimate-1',
        clientId: 'client-1',
        client: ClientModel(
          id: 'client-1',
          name: 'Иван Петров',
          phone: '+7 900 000-00-00',
          objectAddress: 'Оренбург, ул. Советская, 1',
          createdAt: DateTime.utc(2026, 7, 11),
        ),
        objectTitle: 'Оренбург, ул. Советская, 1',
        estimateDate: DateTime.utc(2026, 7, 11),
        durationDays: 10,
        status: EstimateStatus.sent,
        totalAmount: 15000,
        documentVersion: 3,
        createdAt: DateTime.utc(2026, 7, 11),
      ),
      lines: const [
        EstimateLineModel(
          id: 'line-1',
          title: 'Монтаж смесителя',
          unit: 'шт',
          quantity: 1,
          unitPrice: 15000,
          lineTotal: 15000,
          sortOrder: 0,
        ),
      ],
    );
    final signedAt = DateTime.utc(2026, 7, 11, 12, 30);

    final snapshot = buildSignedEstimateSnapshot(
      detail: detail,
      profile: const ProfileModel(
        id: 'master-1',
        fullName: 'Илья Сиднев',
        phone: '+7 901 000-00-00',
        currency: 'RUB',
      ),
      signedAt: signedAt,
    );

    final document = snapshot['document'] as Map<String, dynamic>;
    final client = document['client'] as Map<String, dynamic>;
    expect(snapshot['statement_version'], clientSignatureStatementVersion);
    expect(snapshot['signed_at'], signedAt.toIso8601String());
    expect(document['id'], 'estimate-1');
    expect(document['version'], 3);
    expect(document['total_amount'], 15000);
    expect(client['name'], 'Иван Петров');
    expect(client['phone'], '+7 900 000-00-00');
  });

  test('defines a separate consent statement for signing by QR link', () {
    expect(clientApprovalLinkStatementVersion, 'client-approval-link-v1');
    expect(clientApprovalLinkStatement, contains('Принять смету'));
    expect(clientApprovalLinkStatement, contains('версией сметы'));
  });
}
