import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../core/app_error.dart';
import '../../core/auth_controller.dart';
import '../../legal/legal_documents.dart';
import 'auth_legal_consent.dart';
import '../../shared/russian_phone_input_formatter.dart';
import '../../shared/ui.dart';

enum AuthEntryMode { password, code, register, resetRequest, resetPassword }

enum _CodeTarget { email, phone }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.initialMode = AuthEntryMode.password});

  final AuthEntryMode initialMode;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _newPassword = TextEditingController();
  final _repeatPassword = TextEditingController();

  late AuthEntryMode _mode;
  _CodeTarget _codeTarget = _CodeTarget.email;
  bool _codeRequested = false;
  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _phone.dispose();
    _code.dispose();
    _newPassword.dispose();
    _repeatPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 880;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ScreenPadding(
              maxWidth: isWide ? 1040 : 480,
              child: isWide
                  ? _AuthDesktopStage(
                      isRegister: _mode == AuthEntryMode.register,
                      form: _buildAuthCard(auth, framed: false),
                    )
                  : _buildAuthCard(auth),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthCard(AuthController auth, {bool framed = true}) {
    final content = AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AuthHeader(
            title: _title,
            subtitle: _subtitle,
            canGoBack: _mode != AuthEntryMode.password,
            onBack: auth.isBusy ? null : () => _setMode(AuthEntryMode.password),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offset = Tween<Offset>(
                begin: const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: KeyedSubtree(
              key: ValueKey(_mode),
              child: _buildModeBody(auth),
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => context.push('/help'),
            icon: const Icon(Icons.support_agent_outlined),
            label: const Text('Написать в поддержку'),
          ),
        ],
      ),
    );

    if (!framed) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(22),
        ),
        child: SingleChildScrollView(child: content),
      );
    }

    return SmetchikCard(padding: const EdgeInsets.all(18), child: content);
  }

  Widget _buildModeBody(AuthController auth) {
    return switch (_mode) {
      AuthEntryMode.register => _buildRegister(auth),
      AuthEntryMode.resetRequest => _buildResetRequest(auth),
      AuthEntryMode.resetPassword => _buildResetPassword(auth),
      AuthEntryMode.code => _buildCodeLogin(auth),
      AuthEntryMode.password => _buildPasswordLogin(auth),
    };
  }

  Widget _buildPasswordLogin(AuthController auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LoginTabs(selected: _mode, onSelected: auth.isBusy ? null : _setMode),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => auth.isBusy ? null : _signInWithPassword(),
          decoration: const InputDecoration(
            labelText: 'Пароль',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: auth.isBusy
                ? null
                : () => _setMode(AuthEntryMode.resetRequest),
            child: const Text('Забыли пароль?'),
          ),
        ),
        _Messages(error: _error, info: _info),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: auth.isBusy ? null : _signInWithPassword,
          icon: _BusyIcon(isBusy: auth.isBusy, fallback: Icons.login),
          label: const Text('Войти'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: auth.isBusy
              ? null
              : () => _setMode(AuthEntryMode.register),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Создать аккаунт'),
        ),
      ],
    );
  }

  Widget _buildCodeLogin(AuthController auth) {
    final isEmail = _codeTarget == _CodeTarget.email;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LoginTabs(selected: _mode, onSelected: auth.isBusy ? null : _setMode),
        const SizedBox(height: 16),
        _CodeTargetTabs(
          selected: _codeTarget,
          onSelected: auth.isBusy
              ? null
              : (value) {
                  setState(() {
                    _codeTarget = value;
                    _codeRequested = false;
                    _code.clear();
                    _error = null;
                    _info = null;
                  });
                },
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: isEmail
              ? Column(
                  key: const ValueKey('email-code'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.email],
                      enabled: !_codeRequested && !auth.isBusy,
                      onSubmitted: (_) =>
                          auth.isBusy ? null : _requestEmailCode(),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    if (_codeRequested) ...[
                      const SizedBox(height: 14),
                      _CodeInput(
                        controller: _code,
                        enabled: !auth.isBusy,
                        onCompleted: (_) =>
                            auth.isBusy ? null : _verifyEmailCode(),
                      ),
                      const SizedBox(height: 12),
                      const _HintBox(
                        icon: Icons.mark_email_read_outlined,
                        title: 'Проверьте письмо',
                        text:
                            'Введите 6 цифр из письма. Код одноразовый и действует ограниченное время.',
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      const _EmailCodeNotice(),
                    ],
                  ],
                )
              : Column(
                  key: const ValueKey('phone-code'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: const [RussianPhoneInputFormatter()],
                      enabled: !_codeRequested && !auth.isBusy,
                      onSubmitted: (_) =>
                          auth.isBusy ? null : _requestPhoneCode(),
                      decoration: const InputDecoration(
                        labelText: 'Телефон',
                        prefixIcon: Icon(Icons.phone_iphone),
                      ),
                    ),
                    if (_codeRequested) ...[
                      const SizedBox(height: 14),
                      _CodeInput(
                        controller: _code,
                        enabled: !auth.isBusy,
                        label: 'Код из Telegram',
                        onCompleted: (_) =>
                            auth.isBusy ? null : _verifyPhoneCode(),
                      ),
                      const SizedBox(height: 12),
                      const _HintBox(
                        icon: Icons.telegram,
                        title: 'Проверьте Telegram',
                        text:
                            'Введите 6 цифр из сообщения Telegram Gateway. Код действует несколько минут.',
                        color: AppColors.orangeDark,
                        background: AppColors.orangeLight,
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      const _PhoneCodeNotice(),
                    ],
                  ],
                ),
        ),
        _Messages(error: _error, info: _info),
        const SizedBox(height: 14),
        if (isEmail && !_codeRequested)
          FilledButton.icon(
            onPressed: auth.isBusy ? null : _requestEmailCode,
            icon: _BusyIcon(isBusy: auth.isBusy, fallback: Icons.password),
            label: const Text('Получить письмо'),
          )
        else if (isEmail)
          FilledButton.icon(
            onPressed: auth.isBusy ? null : _verifyEmailCode,
            icon: _BusyIcon(isBusy: auth.isBusy, fallback: Icons.check),
            label: const Text('Войти по коду'),
          )
        else
          FilledButton.icon(
            onPressed: auth.isBusy
                ? null
                : (_codeRequested ? _verifyPhoneCode : _requestPhoneCode),
            icon: _BusyIcon(
              isBusy: auth.isBusy,
              fallback: _codeRequested ? Icons.check : Icons.telegram,
            ),
            label: Text(_codeRequested ? 'Войти по коду' : 'Получить код'),
          ),
        if (_codeRequested) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: auth.isBusy
                ? null
                : (isEmail ? _requestEmailCode : _requestPhoneCode),
            icon: const Icon(Icons.refresh),
            label: const Text('Отправить код ещё раз'),
          ),
        ],
      ],
    );
  }

  Widget _buildRegister(AuthController auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(
            labelText: 'Имя мастера',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => auth.isBusy ? null : _signUp(),
          decoration: const InputDecoration(
            labelText: 'Пароль',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 10),
        SignupConsentRow(
          value: _termsAccepted,
          label: 'Принимаю',
          documentTitle: LegalDocuments.terms.title,
          onChanged: (value) => setState(() => _termsAccepted = value),
          onOpen: () => context.push('/legal/terms'),
        ),
        SignupConsentRow(
          value: _privacyAccepted,
          label: 'Соглашаюсь с',
          documentTitle: LegalDocuments.privacy.title,
          onChanged: (value) => setState(() => _privacyAccepted = value),
          onOpen: () => context.push('/legal/privacy'),
        ),
        _Messages(error: _error, info: _info),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: auth.isBusy ? null : _signUp,
          icon: _BusyIcon(isBusy: auth.isBusy, fallback: Icons.person_add),
          label: const Text('Зарегистрироваться'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: auth.isBusy
              ? null
              : () => _setMode(AuthEntryMode.password),
          icon: const Icon(Icons.login),
          label: const Text('Войти'),
        ),
      ],
    );
  }

  Widget _buildResetRequest(AuthController auth) {
    final isEmail = _codeTarget == _CodeTarget.email;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CodeTargetTabs(
          selected: _codeTarget,
          onSelected: auth.isBusy
              ? null
              : (value) {
                  setState(() {
                    _codeTarget = value;
                    _codeRequested = false;
                    _code.clear();
                    _error = null;
                    _info = null;
                  });
                },
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: isEmail
              ? Column(
                  key: const ValueKey('reset-email'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.email],
                      enabled: !_codeRequested && !auth.isBusy,
                      onSubmitted: (_) =>
                          auth.isBusy ? null : _requestResetEmailCode(),
                      decoration: const InputDecoration(
                        labelText: 'Email аккаунта',
                        prefixIcon: Icon(Icons.mark_email_read_outlined),
                      ),
                    ),
                    if (_codeRequested) ...[
                      const SizedBox(height: 14),
                      _CodeInput(
                        controller: _code,
                        enabled: !auth.isBusy,
                        label: 'Код из письма',
                        onCompleted: (_) =>
                            auth.isBusy ? null : _verifyResetEmailCode(),
                      ),
                      const SizedBox(height: 12),
                      const _HintBox(
                        icon: Icons.lock_reset,
                        title: 'Подтвердите email',
                        text:
                            'Введите 6 цифр из письма. После правильного кода откроется экран нового пароля.',
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      const _HintBox(
                        icon: Icons.password,
                        title: 'Код придёт на email',
                        text:
                            'Введите email аккаунта. Мы отправим одноразовый код для сброса пароля.',
                      ),
                    ],
                  ],
                )
              : Column(
                  key: const ValueKey('reset-telegram'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: const [RussianPhoneInputFormatter()],
                      enabled: !_codeRequested && !auth.isBusy,
                      onSubmitted: (_) =>
                          auth.isBusy ? null : _requestResetPhoneCode(),
                      decoration: const InputDecoration(
                        labelText: 'Телефон',
                        prefixIcon: Icon(Icons.phone_iphone),
                      ),
                    ),
                    if (_codeRequested) ...[
                      const SizedBox(height: 14),
                      _CodeInput(
                        controller: _code,
                        enabled: !auth.isBusy,
                        label: 'Код из Telegram',
                        onCompleted: (_) =>
                            auth.isBusy ? null : _verifyResetPhoneCode(),
                      ),
                      const SizedBox(height: 12),
                      const _HintBox(
                        icon: Icons.lock_reset,
                        title: 'Подтвердите номер',
                        text:
                            'После правильного кода откроется экран нового пароля.',
                        color: AppColors.orangeDark,
                        background: AppColors.orangeLight,
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      const _HintBox(
                        icon: Icons.telegram,
                        title: 'Код придёт в Telegram',
                        text:
                            'Введите номер, который привязан к аккаунту. После кода можно будет задать новый пароль.',
                        color: AppColors.orangeDark,
                        background: AppColors.orangeLight,
                      ),
                    ],
                  ],
                ),
        ),
        _Messages(error: _error, info: _info),
        const SizedBox(height: 18),
        if (isEmail)
          FilledButton.icon(
            onPressed: auth.isBusy
                ? null
                : (_codeRequested
                      ? _verifyResetEmailCode
                      : _requestResetEmailCode),
            icon: _BusyIcon(
              isBusy: auth.isBusy,
              fallback: _codeRequested ? Icons.check : Icons.password,
            ),
            label: Text(_codeRequested ? 'Подтвердить код' : 'Получить код'),
          )
        else
          FilledButton.icon(
            onPressed: auth.isBusy
                ? null
                : (_codeRequested
                      ? _verifyResetPhoneCode
                      : _requestResetPhoneCode),
            icon: _BusyIcon(
              isBusy: auth.isBusy,
              fallback: _codeRequested ? Icons.check : Icons.telegram,
            ),
            label: Text(_codeRequested ? 'Подтвердить код' : 'Получить код'),
          ),
        if (_codeRequested) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: auth.isBusy
                ? null
                : (isEmail ? _requestResetEmailCode : _requestResetPhoneCode),
            icon: const Icon(Icons.refresh),
            label: const Text('Отправить код ещё раз'),
          ),
        ],
      ],
    );
  }

  Widget _buildResetPassword(AuthController auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!auth.isLoggedIn) ...[
          const _HintBox(
            icon: Icons.mail_lock_outlined,
            title: 'Сначала подтвердите код',
            text:
                'Введите код восстановления из письма или Telegram, затем задайте новый пароль.',
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _newPassword,
          obscureText: true,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: 'Новый пароль',
            prefixIcon: Icon(Icons.lock_reset),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _repeatPassword,
          obscureText: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => auth.isBusy ? null : _saveNewPassword(),
          decoration: const InputDecoration(
            labelText: 'Повторите пароль',
            prefixIcon: Icon(Icons.verified_user_outlined),
          ),
        ),
        _Messages(error: _error, info: _info),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: auth.isBusy ? null : _saveNewPassword,
          icon: _BusyIcon(isBusy: auth.isBusy, fallback: Icons.check),
          label: const Text('Сохранить пароль'),
        ),
      ],
    );
  }

  String get _title {
    return switch (_mode) {
      AuthEntryMode.register => 'Создать аккаунт',
      AuthEntryMode.resetRequest => 'Восстановить пароль',
      AuthEntryMode.resetPassword => 'Новый пароль',
      AuthEntryMode.code => 'Войти по коду',
      AuthEntryMode.password => 'Войти в Сметчик',
    };
  }

  String get _subtitle {
    return switch (_mode) {
      AuthEntryMode.register =>
        'Пара минут, и можно делать первые сметы для клиентов.',
      AuthEntryMode.resetRequest =>
        'Получите код на email или подтвердите номер через Telegram.',
      AuthEntryMode.resetPassword =>
        'Задайте пароль, который будете помнить на объекте и в офисе.',
      AuthEntryMode.code => 'Получите короткий код на email или в Telegram.',
      AuthEntryMode.password => 'Сметы, клиенты и прайс-лист всегда под рукой.',
    };
  }

  void _setMode(AuthEntryMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _info = null;
      if (mode != AuthEntryMode.code) {
        _codeRequested = false;
        _code.clear();
      }
    });
  }

  Future<void> _signInWithPassword() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!_isValidEmail(email)) {
      _setError('Введите корректный email');
      return;
    }
    if (password.length < 6) {
      _setError('Пароль должен быть не короче 6 символов');
      return;
    }
    await _runAuthAction(() async {
      await ref
          .read(authControllerProvider)
          .signIn(email: email, password: password);
      if (mounted) context.go('/home');
    });
  }

  Future<void> _signUp() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (name.length < 2) {
      _setError('Введите имя мастера');
      return;
    }
    if (!_isValidEmail(email)) {
      _setError('Введите корректный email');
      return;
    }
    if (password.length < 6) {
      _setError('Пароль должен быть не короче 6 символов');
      return;
    }
    if (!_termsAccepted || !_privacyAccepted) {
      _setError('Ознакомьтесь и согласитесь с документами');
      return;
    }

    await _runAuthAction(() async {
      await ref
          .read(authControllerProvider)
          .signUp(
            email: email,
            password: password,
            fullName: name,
            termsVersion: LegalDocuments.terms.version,
            privacyVersion: LegalDocuments.privacy.version,
          );
      if (mounted) context.go('/home');
    });
  }

  Future<void> _requestEmailCode() async {
    final email = _email.text.trim();
    if (!_isValidEmail(email)) {
      _setError('Введите email, на который отправить код');
      return;
    }

    await _runAuthAction(() async {
      await ref.read(authControllerProvider).requestEmailCode(email: email);
      if (!mounted) return;
      setState(() {
        _codeRequested = true;
        _code.clear();
        _info = null;
      });
    });
  }

  Future<void> _requestPhoneCode() async {
    final phone = _phone.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      _setError('Введите телефон, на который отправить код');
      return;
    }

    await _runAuthAction(() async {
      await ref.read(authControllerProvider).requestPhoneCode(phone: phone);
      if (!mounted) return;
      setState(() {
        _codeRequested = true;
        _code.clear();
        _info = null;
      });
    });
  }

  Future<void> _verifyEmailCode() async {
    final email = _email.text.trim();
    final code = _code.text.trim();
    if (!_isValidEmail(email)) {
      _setError('Введите email, на который пришёл код');
      return;
    }
    if (code.length != 6) {
      _setError('Введите 6 цифр из письма');
      return;
    }

    await _runAuthAction(() async {
      await ref
          .read(authControllerProvider)
          .verifyEmailCode(email: email, code: code);
      if (mounted) context.go('/home');
    });
  }

  Future<void> _verifyPhoneCode() async {
    final phone = _phone.text.trim();
    final code = _code.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      _setError('Введите телефон, на который пришёл код');
      return;
    }
    if (code.length < 4) {
      _setError('Введите код из Telegram');
      return;
    }

    await _runAuthAction(() async {
      await ref
          .read(authControllerProvider)
          .verifyPhoneCode(phone: phone, code: code);
      if (mounted) context.go('/home');
    });
  }

  Future<void> _requestResetPhoneCode() async {
    final phone = _phone.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      _setError('Введите телефон аккаунта');
      return;
    }

    await _runAuthAction(() async {
      await ref.read(authControllerProvider).requestPhoneCode(phone: phone);
      if (!mounted) return;
      setState(() {
        _codeRequested = true;
        _code.clear();
        _info = null;
      });
    });
  }

  Future<void> _verifyResetPhoneCode() async {
    final phone = _phone.text.trim();
    final code = _code.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      _setError('Введите телефон аккаунта');
      return;
    }
    if (code.length < 4) {
      _setError('Введите код из Telegram');
      return;
    }

    await _runAuthAction(() async {
      await ref
          .read(authControllerProvider)
          .verifyPhoneCode(phone: phone, code: code, purpose: 'reset');
      if (!mounted) return;
      setState(() {
        _mode = AuthEntryMode.resetPassword;
        _codeRequested = false;
        _code.clear();
        _newPassword.clear();
        _repeatPassword.clear();
        _info = null;
      });
    });
  }

  Future<void> _requestResetEmailCode() async {
    final email = _email.text.trim();
    if (!_isValidEmail(email)) {
      _setError('Введите email, чтобы восстановить пароль');
      return;
    }

    await _runAuthAction(() async {
      await ref
          .read(authControllerProvider)
          .requestPasswordResetCode(email: email);
      if (!mounted) return;
      setState(() {
        _codeRequested = true;
        _code.clear();
        _info = null;
      });
    });
  }

  Future<void> _verifyResetEmailCode() async {
    final email = _email.text.trim();
    final code = _code.text.trim();
    if (!_isValidEmail(email)) {
      _setError('Введите email аккаунта');
      return;
    }
    if (code.length != 6) {
      _setError('Введите 6 цифр из письма');
      return;
    }

    await _runAuthAction(() async {
      await ref
          .read(authControllerProvider)
          .verifyPasswordResetCode(email: email, code: code);
      if (!mounted) return;
      setState(() {
        _mode = AuthEntryMode.resetPassword;
        _codeRequested = false;
        _code.clear();
        _newPassword.clear();
        _repeatPassword.clear();
        _info = null;
      });
    });
  }

  Future<void> _saveNewPassword() async {
    final password = _newPassword.text;
    final repeat = _repeatPassword.text;
    if (password.length < 6) {
      _setError('Новый пароль должен быть не короче 6 символов');
      return;
    }
    if (password != repeat) {
      _setError('Пароли не совпадают');
      return;
    }
    if (!ref.read(authControllerProvider).isLoggedIn) {
      _setError('Сначала подтвердите код восстановления и попробуйте ещё раз');
      return;
    }

    await _runAuthAction(() async {
      await ref.read(authControllerProvider).updatePassword(password: password);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Пароль обновлён')));
      context.go('/home');
    });
  }

  Future<void> _runAuthAction(Future<void> Function() action) async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyAuthError(error));
    }
  }

  void _setError(String value) {
    setState(() {
      _error = value;
      _info = null;
    });
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
  }

  String _friendlyAuthError(Object error) {
    final raw = error.toString();
    if (raw.contains('Invalid login credentials')) {
      return 'Email или пароль не подошли';
    }
    if (raw.contains('Email not confirmed')) {
      return 'Email ещё не подтверждён';
    }
    if (raw.contains('unexpected_failure') ||
        raw.contains('Unexpected status code returned from hook')) {
      return 'Почтовый сервис не отправил код. Попробуйте Telegram или другой способ входа.';
    }
    if (raw.contains('upstream request timeout') ||
        raw.contains('statusCode: 504')) {
      return 'Почтовый сервис долго не отвечает. Проверьте, что Send Email Hook выключен, или попробуйте Telegram.';
    }
    if (raw.contains('Token has expired') || raw.contains('expired')) {
      return 'Код устарел, запросите новый';
    }
    if (raw.contains('Invalid token') || raw.contains('invalid')) {
      return 'Код не подошёл, проверьте письмо';
    }
    if (raw.contains('For security purposes')) {
      return 'Слишком часто. Подождите немного и попробуйте ещё раз';
    }
    if (raw.contains('Signups not allowed')) {
      return 'Аккаунт с таким email не найден';
    }
    return appErrorMessage(error);
  }
}

class _AuthDesktopStage extends StatelessWidget {
  const _AuthDesktopStage({required this.isRegister, required this.form});

  final bool isRegister;
  final Widget form;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 620,
      child: Material(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final panelWidth = (constraints.maxWidth - gap) / 2;
              final heroLeft = isRegister ? panelWidth + gap : 0.0;
              final formLeft = isRegister ? 0.0 : panelWidth + gap;

              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 460),
                    curve: Curves.easeInOutCubic,
                    left: heroLeft,
                    top: 0,
                    bottom: 0,
                    width: panelWidth,
                    child: const _AuthHeroPanel(),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 460),
                    curve: Curves.easeInOutCubic,
                    left: formLeft,
                    top: 0,
                    bottom: 0,
                    width: panelWidth,
                    child: form,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AuthHeader extends StatelessWidget {
  const _AuthHeader({
    required this.title,
    required this.subtitle,
    required this.canGoBack,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final bool canGoBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.receipt_long,
                color: AppColors.orange,
                size: 32,
              ),
            ),
            const Spacer(),
            if (canGoBack)
              IconButton.filledTonal(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Назад ко входу',
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.textSecondary,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LoginTabs extends StatelessWidget {
  const _LoginTabs({required this.selected, required this.onSelected});

  final AuthEntryMode selected;
  final ValueChanged<AuthEntryMode>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              label: 'Пароль',
              icon: Icons.lock_outline,
              selected: selected == AuthEntryMode.password,
              onTap: onSelected == null
                  ? null
                  : () => onSelected!(AuthEntryMode.password),
            ),
          ),
          Expanded(
            child: _SegmentButton(
              label: 'Код',
              icon: Icons.password,
              selected: selected == AuthEntryMode.code,
              onTap: onSelected == null
                  ? null
                  : () => onSelected!(AuthEntryMode.code),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeTargetTabs extends StatelessWidget {
  const _CodeTargetTabs({required this.selected, required this.onSelected});

  final _CodeTarget selected;
  final ValueChanged<_CodeTarget>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              label: 'Email',
              icon: Icons.mail_outline,
              selected: selected == _CodeTarget.email,
              onTap: onSelected == null
                  ? null
                  : () => onSelected!(_CodeTarget.email),
            ),
          ),
          Expanded(
            child: _SegmentButton(
              label: 'Telegram',
              icon: Icons.telegram,
              selected: selected == _CodeTarget.phone,
              onTap: onSelected == null
                  ? null
                  : () => onSelected!(_CodeTarget.phone),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.textSecondary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? AppColors.graphite : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeInput extends StatefulWidget {
  const _CodeInput({
    required this.controller,
    required this.enabled,
    required this.onCompleted,
    this.label = 'Код из письма',
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onCompleted;
  final String label;

  @override
  State<_CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<_CodeInput> {
  final _focusNode = FocusNode();
  String _lastCompleted = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _CodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    setState(() {});
  }

  void _handleTextChanged() {
    final value = widget.controller.text;
    setState(() {});
    if (widget.enabled && value.length == 6 && value != _lastCompleted) {
      _lastCompleted = value;
      widget.onCompleted(value);
    }
    if (value.length < 6) {
      _lastCompleted = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: widget.enabled ? _focusNode.requestFocus : null,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gap = constraints.maxWidth < 350 ? 6.0 : 8.0;
              final boxWidth = math
                  .min(48, (constraints.maxWidth - gap * 5) / 6)
                  .clamp(38.0, 48.0);

              return SizedBox(
                height: 58,
                child: Stack(
                  children: [
                    TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      enabled: widget.enabled,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      enableSuggestions: true,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      cursorColor: Colors.transparent,
                      style: const TextStyle(color: Colors.transparent),
                      decoration: const InputDecoration(
                        counterText: '',
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                    IgnorePointer(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var index = 0; index < 6; index++) ...[
                            _CodeBox(
                              value: index < text.length ? text[index] : null,
                              active:
                                  _focusNode.hasFocus &&
                                  widget.enabled &&
                                  index == math.min(text.length, 5),
                              width: boxWidth.toDouble(),
                            ),
                            if (index != 5) SizedBox(width: gap),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({
    required this.value,
    required this.active,
    required this.width,
  });

  final String? value;
  final bool active;
  final double width;

  @override
  Widget build(BuildContext context) {
    final filled = value != null;
    return AnimatedScale(
      scale: active ? 1.06 : 1,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: width,
        height: 54,
        decoration: BoxDecoration(
          color: filled ? AppColors.orangeLight : AppColors.card,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: active || filled ? AppColors.orange : AppColors.border,
            width: active ? 1.8 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppColors.orange.withAlpha(46),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          transitionBuilder: (child, animation) {
            return ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: Text(
            value ?? '',
            key: ValueKey(value ?? 'empty'),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.graphite,
            ),
          ),
        ),
      ),
    );
  }
}

class _Messages extends StatelessWidget {
  const _Messages({required this.error, required this.info});

  final String? error;
  final String? info;

  @override
  Widget build(BuildContext context) {
    final text = error ?? info;
    if (text == null) return const SizedBox.shrink();

    final isError = error != null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _HintBox(
        icon: isError ? Icons.error_outline : Icons.check_circle_outline,
        title: isError ? 'Не получилось' : 'Готово',
        text: text,
        color: isError ? AppColors.danger : AppColors.success,
        background: isError ? AppColors.dangerBg : AppColors.successBg,
      ),
    );
  }
}

class _HintBox extends StatelessWidget {
  const _HintBox({
    required this.icon,
    required this.title,
    required this.text,
    this.color = AppColors.info,
    this.background = AppColors.infoBg,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(34)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailCodeNotice extends StatelessWidget {
  const _EmailCodeNotice();

  @override
  Widget build(BuildContext context) {
    return const _HintBox(
      icon: Icons.mark_email_read_outlined,
      title: 'Код придёт на email',
      text: 'Введите почту аккаунта. Мы отправим одноразовый 6-значный код.',
    );
  }
}

class _PhoneCodeNotice extends StatelessWidget {
  const _PhoneCodeNotice();

  @override
  Widget build(BuildContext context) {
    return const _HintBox(
      icon: Icons.telegram,
      title: 'Код придёт в Telegram',
      text:
          'Введите номер, который привязан к Telegram. Gateway отправит одноразовый код прямо в приложение.',
      color: AppColors.orangeDark,
      background: AppColors.orangeLight,
    );
  }
}

class _BusyIcon extends StatelessWidget {
  const _BusyIcon({required this.isBusy, required this.fallback});

  final bool isBusy;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    if (!isBusy) return Icon(fallback);
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}

class _AuthHeroPanel extends StatelessWidget {
  const _AuthHeroPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.bolt, color: Colors.white, size: 34),
          ),
          const Spacer(),
          Text(
            'Смета за пару минут прямо на объекте',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Клиенты, прайс-лист, PDF и отправка клиенту собраны в одном быстром инструменте.',
            style: TextStyle(
              color: Color(0xFFD7D4CC),
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 26),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroChip(icon: Icons.receipt_long, label: 'Сметы'),
              _HeroChip(icon: Icons.contact_phone_outlined, label: 'Клиенты'),
              _HeroChip(icon: Icons.picture_as_pdf, label: 'PDF'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.orange, size: 18),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
