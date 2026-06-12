import 'package:supabase_flutter/supabase_flutter.dart';

class AddressSuggestionsService {
  AddressSuggestionsService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static final instance = AddressSuggestionsService();

  final SupabaseClient _client;

  Future<List<String>> suggestRussianAddresses(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) {
      return const [];
    }

    try {
      final response = await _client.functions.invoke(
        'suggest-addresses',
        body: {'query': trimmed, 'count': 6},
      );
      final payload = response.data;
      if (payload is! Map) {
        return const [];
      }

      final suggestions = payload['suggestions'];
      if (suggestions is! List) {
        return const [];
      }

      return suggestions
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
