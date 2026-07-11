import 'models.dart';

const clientSignatureStatementVersion = 'client-acceptance-v1';

const clientSignatureStatement =
    'Подписываясь на экране устройства, я подтверждаю, что ознакомился(ась) со сметой, согласен(на) с её условиями и подтверждаю принятие документа. Я согласен(на) на фиксацию подписи, даты и сведений о принятии в сервисе «Сметчик». ';

const clientSignatureDisclosure =
    'Подпись фиксирует принятие сметы на этом устройстве. Для использования простой электронной подписи с подтверждением личности потребуется отдельный код клиента.';

Map<String, dynamic> buildSignedEstimateSnapshot({
  required EstimateDetail detail,
  required ProfileModel? profile,
  required DateTime signedAt,
  DateTime? phoneVerifiedAt,
  String? signatureChallengeId,
}) {
  final estimate = detail.estimate;
  final client = estimate.client;
  return {
    'schema_version': 'signed-estimate-v1',
    'statement_version': clientSignatureStatementVersion,
    'statement': clientSignatureStatement,
    'signed_at': signedAt.toUtc().toIso8601String(),
    'phone_verified_at': phoneVerifiedAt?.toUtc().toIso8601String(),
    'signature_challenge_id': signatureChallengeId,
    'document': {
      'id': estimate.id,
      'version': estimate.documentVersion,
      'object_title': estimate.objectTitle,
      'estimate_date': estimate.estimateDate.toIso8601String(),
      'duration_days': estimate.durationDays,
      'total_amount': estimate.totalAmount,
      'client': {
        'name': client?.name,
        'phone': client?.phone,
        'object_address': client?.objectAddress,
      },
      'lines': [
        for (final line in detail.lines)
          {
            'title': line.title,
            'unit': line.unit,
            'quantity': line.quantity,
            'unit_price': line.unitPrice,
            'line_total': line.lineTotal,
            'sort_order': line.sortOrder,
          },
      ],
    },
    'master': {
      'name': profile?.fullName,
      'phone': profile?.phone,
      'specialization': profile?.specialization,
      'signature_path': profile?.signaturePath,
    },
  };
}
