import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController();
});

class AuthController extends ChangeNotifier {
  AuthController() {
    if (!AppConfig.hasSupabaseConfig) return;
    _client = Supabase.instance.client;
    user = _client!.auth.currentUser;
    _sub = _client!.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.passwordRecovery) {
        isPasswordRecovery = true;
      }
      if (event.event == AuthChangeEvent.signedOut) {
        isPasswordRecovery = false;
        user = null;
        notifyListeners();
        return;
      }
      user = event.session?.user ?? _client!.auth.currentUser;
      notifyListeners();
    });
  }

  SupabaseClient? _client;
  StreamSubscription<AuthState>? _sub;
  User? user;
  bool isPasswordRecovery = false;
  bool isBusy = false;
  String? _phoneRequestId;
  String? _phoneForRequest;

  bool get isLoggedIn => user != null;

  Future<void> signIn({required String email, required String password}) async {
    await _run(() async {
      // Never keep an old session alive while another account is attempting
      // to enter. This prevents routing with a previous user's profile.
      if (_client!.auth.currentSession != null) {
        await _client!.auth.signOut(scope: SignOutScope.local);
        user = null;
      }
      final response = await _client!.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final signedInEmail = response.user?.email?.trim().toLowerCase();
      if (response.session == null ||
          signedInEmail != email.trim().toLowerCase()) {
        await _client!.auth.signOut(scope: SignOutScope.local);
        throw const AuthException(
          'Не удалось открыть сессию этого аккаунта. Войдите ещё раз.',
        );
      }
      user = response.user;
    });
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String termsVersion,
    required String privacyVersion,
  }) async {
    await _run(() async {
      // Registration is only reachable for signed-out users. Clear any stale
      // local session before creating a new account so sessions cannot cross.
      if (_client!.auth.currentSession != null) {
        await _client!.auth.signOut(scope: SignOutScope.local);
        user = null;
      }
      final response = await _client!.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          'legal_terms_version': termsVersion,
          'legal_privacy_version': privacyVersion,
          'legal_accepted_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      if (response.session == null && response.user != null) {
        throw const AuthException(
          'Аккаунт создан. Если включено подтверждение email, проверьте почту и затем войдите.',
        );
      }
      if (response.session != null) {
        final signedUpEmail = response.session!.user.email
            ?.trim()
            .toLowerCase();
        if (signedUpEmail != email.trim().toLowerCase()) {
          throw const AuthException(
            'Не удалось подтвердить сессию нового аккаунта. Войдите ещё раз.',
          );
        }
        user = response.session!.user;
      }
    });
  }

  Future<void> signOut() async {
    await _run(() async {
      await _client!.auth.signOut(scope: SignOutScope.local);
      user = null;
      isPasswordRecovery = false;
    });
  }

  Future<void> requestPasswordResetCode({required String email}) async {
    await _run(() async {
      await _client!.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: _authRedirectUrl('/auth/reset'),
      );
    });
  }

  Future<void> requestEmailCode({required String email}) async {
    await _run(() async {
      await _client!.auth.signInWithOtp(
        email: email.trim(),
        shouldCreateUser: false,
        emailRedirectTo: _authRedirectUrl('/home'),
      );
    });
  }

  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    await _run(() async {
      if (_client!.auth.currentSession != null) {
        await _client!.auth.signOut(scope: SignOutScope.local);
        user = null;
      }
      final response = await _client!.auth.verifyOTP(
        email: email.trim(),
        token: code.trim(),
        type: OtpType.email,
      );
      final signedInEmail = response.user?.email?.trim().toLowerCase();
      if (response.session == null ||
          signedInEmail != email.trim().toLowerCase()) {
        await _client!.auth.signOut(scope: SignOutScope.local);
        throw const AuthException('Код не открыл сессию указанного аккаунта.');
      }
      user = response.user;
    });
  }

  Future<void> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    await _run(() async {
      await _client!.auth.verifyOTP(
        email: email.trim(),
        token: code.trim(),
        type: OtpType.recovery,
      );
      isPasswordRecovery = true;
    });
  }

  Future<void> updatePassword({required String password}) async {
    await _run(() async {
      await _client!.auth.updateUser(UserAttributes(password: password));
      isPasswordRecovery = false;
    });
  }

  Future<void> requestPhoneCode({required String phone}) async {
    await _run(() async {
      final response = await _client!.functions.invoke(
        'telegram-auth',
        body: {'action': 'send', 'phone': phone.trim()},
      );
      final data = _functionData(response.data);
      _phoneRequestId = data['requestId'] as String?;
      _phoneForRequest = data['phone'] as String? ?? phone.trim();
      if (_phoneRequestId == null || _phoneRequestId!.isEmpty) {
        throw const AuthException('Telegram не вернул номер запроса.');
      }
    });
  }

  Future<void> verifyPhoneCode({
    required String phone,
    required String code,
    String purpose = 'login',
  }) async {
    await _run(() async {
      final requestId = _phoneRequestId;
      if (requestId == null || requestId.isEmpty) {
        throw const AuthException('Сначала запросите код Telegram.');
      }

      final response = await _client!.functions.invoke(
        'telegram-auth',
        body: {
          'action': 'verify',
          'phone': _phoneForRequest ?? phone.trim(),
          'code': code.trim(),
          'requestId': requestId,
          'purpose': purpose,
        },
      );
      final data = _functionData(response.data);
      final session = _functionData(data['session']);
      final accessToken = session['access_token'] as String?;
      final refreshToken = session['refresh_token'] as String?;
      if (accessToken == null || refreshToken == null) {
        throw const AuthException('Telegram-код принят, но сессия не создана.');
      }
      await _client!.auth.setSession(refreshToken, accessToken: accessToken);
      _phoneRequestId = null;
      _phoneForRequest = null;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_client == null) {
      throw StateError('Supabase is not configured.');
    }
    isBusy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String? _authRedirectUrl(String route) {
    if (!kIsWeb) {
      final path = route == '/auth/reset' ? '/reset' : '/callback';
      return Uri(scheme: 'smetchik', host: 'auth', path: path).toString();
    }

    final base = Uri.base;
    if (!base.hasScheme || base.scheme == 'file') return null;
    return base.replace(path: '/', query: '', fragment: route).toString();
  }

  Map<String, dynamic> _functionData(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const AuthException('Сервер вернул неожиданный ответ.');
  }
}
