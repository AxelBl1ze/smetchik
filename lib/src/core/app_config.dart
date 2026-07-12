class AppConfig {
  static const _defaultSupabaseUrl = 'https://kvuhtxipcrjsglklaury.supabase.co';
  static const _defaultSupabaseAnonKey =
      'sb_publishable_dnu8h40YQdmKqOebGVEABw_ffmkq3ih';

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultSupabaseUrl,
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _defaultSupabaseAnonKey,
  );

  static const publicAppUrl = String.fromEnvironment(
    'PUBLIC_APP_URL',
    defaultValue: 'https://smetchik.pages.dev',
  );

  static String estimateApprovalUrl(String token) {
    final base = publicAppUrl.replaceFirst(RegExp(r'/+$'), '');
    return '$base/#/approve/$token';
  }

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
