import 'package:flutter_test/flutter_test.dart';
import 'package:smetchik/src/data/offline_sync_service.dart';

void main() {
  test('restores an estimate draft from the local sync queue', () {
    final createdAt = DateTime.utc(2026, 7, 14, 10, 30);
    final entry = OfflineDraftEntry(
      id: 'local-estimate',
      kind: OfflineDraftKind.estimate,
      createdAt: createdAt,
      updatedAt: createdAt,
      payload: {
        'object_title': 'Дом на Садовой',
        'client_id': null,
        'client_name': 'Анна',
        'client_phone': '+7 900 000-00-00',
        'estimate_date': '2026-07-14T00:00:00.000Z',
        'duration_days': 14,
        'lines': [
          {
            'id': 'line-1',
            'catalog_item_id': null,
            'title': 'Монтаж двери',
            'unit': 'шт',
            'quantity': 2,
            'unit_price': 1500,
            'line_total': 3000,
            'sort_order': 0,
          },
        ],
      },
    );

    final restored = OfflineDraftEntry.fromMap(entry.toMap());

    expect(restored.id, 'local-estimate');
    expect(restored.estimateDraft.objectTitle, 'Дом на Садовой');
    expect(restored.estimateDraft.lines.single.lineTotal, 3000);
    expect(restored.estimateDraft.totalAmount, 3000);
  });

  test('recognizes connection failures that may be queued safely', () {
    expect(isRecoverableNetworkError(Exception('Failed to fetch')), isTrue);
    expect(isRecoverableNetworkError(Exception('permission denied')), isFalse);
  });
}
