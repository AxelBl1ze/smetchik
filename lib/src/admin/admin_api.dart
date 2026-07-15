import 'package:supabase_flutter/supabase_flutter.dart';

class AdminApi {
  const AdminApi(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> call(
    String action, {
    Map<String, dynamic> body = const {},
  }) async {
    final response = await _client.functions.invoke(
      'admin-console',
      body: {'action': action, ...body},
    );
    if (response.data is Map<String, dynamic>) {
      return response.data as Map<String, dynamic>;
    }
    if (response.data is Map) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    throw const AuthException('Админ-панель вернула неожиданный ответ.');
  }
}
