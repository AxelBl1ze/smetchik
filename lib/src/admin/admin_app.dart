import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';
import '../data/models.dart';
import '../shared/keyboard_dismiss_on_tap.dart';
import '../shared/ui.dart';
import 'admin_api.dart';
import 'admin_download.dart';

class SmetchikAdminApp extends StatelessWidget {
  const SmetchikAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Сметчик · Админ',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: AppConfig.hasSupabaseConfig
          ? const _AdminSessionGate()
          : const _AdminConfigRequired(),
      builder: (context, child) =>
          KeyboardDismissOnTap(child: child ?? const SizedBox.shrink()),
    );
  }
}

class _AdminConfigRequired extends StatelessWidget {
  const _AdminConfigRequired();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Не настроено подключение к Сметчику.'),
        ),
      ),
    );
  }
}

class _AdminSessionGate extends StatefulWidget {
  const _AdminSessionGate();

  @override
  State<_AdminSessionGate> createState() => _AdminSessionGateState();
}

class _AdminSessionGateState extends State<_AdminSessionGate> {
  late final SupabaseClient _client;
  StreamSubscription<AuthState>? _subscription;
  User? _user;

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    _user = _client.auth.currentUser;
    _subscription = _client.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() => _user = state.session?.user);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) return _AdminLogin(onSignedIn: () {});
    return _AdminWorkspace(user: user);
  }
}

class _AdminLogin extends StatefulWidget {
  const _AdminLogin({required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<_AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<_AdminLogin> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.isEmpty) {
      setState(() => _error = 'Введите email и пароль администратора.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      widget.onSignedIn();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Не удалось войти. Повторите попытку.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: AppColors.graphite)),
          Align(
            alignment: Alignment.center,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 42,
                        offset: Offset(0, 22),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 720;
                      final form = Padding(
                        padding: const EdgeInsets.all(36),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 470),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _AdminMark(dark: false),
                                const SizedBox(height: 30),
                                const Text(
                                  'Вход в админку',
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Доступ есть только у назначенных администраторов.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                TextField(
                                  controller: _email,
                                  autofillHints: const [AutofillHints.username],
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Email администратора',
                                    prefixIcon: Icon(Icons.alternate_email),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _password,
                                  obscureText: _obscure,
                                  autofillHints: const [AutofillHints.password],
                                  onSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Пароль',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      tooltip: _obscure
                                          ? 'Показать пароль'
                                          : 'Скрыть пароль',
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 14),
                                  _AdminNotice(
                                    icon: Icons.error_outline,
                                    color: AppColors.danger,
                                    background: AppColors.dangerBg,
                                    text: _error!,
                                  ),
                                ],
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: _busy ? null : _submit,
                                  icon: _busy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.login),
                                  label: const Text('Войти в админку'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      return narrow
                          ? form
                          : Row(
                              children: [
                                Expanded(child: form),
                                const SizedBox(
                                  width: 360,
                                  child: _AdminLoginSide(),
                                ),
                              ],
                            );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminLoginSide extends StatelessWidget {
  const _AdminLoginSide();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: const BoxDecoration(color: AppColors.graphite),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _AdminMark(dark: true),
          SizedBox(height: 52),
          Icon(
            Icons.admin_panel_settings_outlined,
            color: AppColors.orange,
            size: 46,
          ),
          SizedBox(height: 16),
          Text(
            'Операционная\nпанель',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Доступы, промокоды и подписанные документы в одном защищённом месте.',
            style: TextStyle(
              color: Color(0xFFD5D2CC),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 26),
          _AdminSidePoint(
            icon: Icons.verified_user_outlined,
            text: 'Проверка прав',
          ),
          SizedBox(height: 12),
          _AdminSidePoint(
            icon: Icons.history_outlined,
            text: 'Журнал действий',
          ),
          SizedBox(height: 40),
          Text(
            'Сметчик · служебный доступ',
            style: TextStyle(color: Color(0xFFAAA6A0), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AdminSidePoint extends StatelessWidget {
  const _AdminSidePoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.orange),
        const SizedBox(width: 10),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFFD5D2CC),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AdminWorkspace extends StatefulWidget {
  const _AdminWorkspace({required this.user});

  final User user;

  @override
  State<_AdminWorkspace> createState() => _AdminWorkspaceState();
}

class _AdminWorkspaceState extends State<_AdminWorkspace> {
  late final AdminApi _api;
  Map<String, dynamic>? _dashboard;
  String? _error;
  bool _loading = true;
  _AdminSection _section = _AdminSection.overview;

  @override
  void initState() {
    super.initState();
    _api = AdminApi(Supabase.instance.client);
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.call('bootstrap');
      if (mounted) setState(() => _dashboard = data);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  void _select(_AdminSection value) {
    if (_section == value) return;
    setState(() => _section = value);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 960;
    final body = _AdminContent(
      section: _section,
      api: _api,
      dashboard: _dashboard,
      loading: _loading,
      error: _error,
      onRefresh: _loadDashboard,
    );

    return Scaffold(
      drawer: desktop
          ? null
          : Drawer(
              child: SafeArea(
                child: _AdminNavigation(
                  selected: _section,
                  onSelect: (section) {
                    Navigator.of(context).pop();
                    _select(section);
                  },
                  onSignOut: _signOut,
                  email: widget.user.email ?? '',
                  expanded: true,
                ),
              ),
            ),
      appBar: desktop
          ? null
          : AppBar(
              title: const _AdminMark(dark: false, compact: true),
              actions: [
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: _loading ? null : _loadDashboard,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: Row(
        children: [
          if (desktop)
            SizedBox(
              width: 264,
              child: _AdminNavigation(
                selected: _section,
                onSelect: _select,
                onSignOut: _signOut,
                email: widget.user.email ?? '',
                expanded: true,
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

enum _AdminSection { overview, users, promos, signatures, audit }

class _AdminNavigation extends StatelessWidget {
  const _AdminNavigation({
    required this.selected,
    required this.onSelect,
    required this.onSignOut,
    required this.email,
    required this.expanded,
  });

  final _AdminSection selected;
  final ValueChanged<_AdminSection> onSelect;
  final VoidCallback onSignOut;
  final String email;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    const items = [
      (
        section: _AdminSection.overview,
        icon: Icons.grid_view_outlined,
        label: 'Обзор',
      ),
      (
        section: _AdminSection.users,
        icon: Icons.people_alt_outlined,
        label: 'Пользователи',
      ),
      (
        section: _AdminSection.promos,
        icon: Icons.confirmation_number_outlined,
        label: 'Промокоды',
      ),
      (
        section: _AdminSection.signatures,
        icon: Icons.verified_user_outlined,
        label: 'Подписи',
      ),
      (
        section: _AdminSection.audit,
        icon: Icons.history_outlined,
        label: 'Журнал',
      ),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.graphite),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: _AdminMark(dark: true),
              ),
              const SizedBox(height: 34),
              for (final item in items) ...[
                _AdminNavItem(
                  icon: item.icon,
                  label: item.label,
                  selected: item.section == selected,
                  onTap: () => onSelect(item.section),
                ),
                const SizedBox(height: 5),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onSignOut,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD5D2CC),
                  alignment: Alignment.centerLeft,
                ),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Выйти'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminNavItem extends StatelessWidget {
  const _AdminNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.orange : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : const Color(0xFFD5D2CC),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFFD5D2CC),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminContent extends StatelessWidget {
  const _AdminContent({
    required this.section,
    required this.api,
    required this.dashboard,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  final _AdminSection section;
  final AdminApi api;
  final Map<String, dynamic>? dashboard;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final title = switch (section) {
      _AdminSection.overview => 'Обзор',
      _AdminSection.users => 'Пользователи',
      _AdminSection.promos => 'Промокоды',
      _AdminSection.signatures => 'Подписанные сметы',
      _AdminSection.audit => 'Журнал действий',
    };
    final subtitle = switch (section) {
      _AdminSection.overview => 'Состояние сервиса и последние события',
      _AdminSection.users => 'Тарифы и ручная поддержка доступа',
      _AdminSection.promos => 'Выдача Профи без подключения оплаты',
      _AdminSection.signatures =>
        'Зафиксированные документы и пакет доказательств',
      _AdminSection.audit => 'Следы служебных операций',
    };

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Обновить',
                    onPressed: loading ? null : onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
          if (error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: _AdminNotice(
                  icon: Icons.lock_outline,
                  color: AppColors.danger,
                  background: AppColors.dangerBg,
                  text: error!,
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            sliver: SliverToBoxAdapter(
              child: switch (section) {
                _AdminSection.overview => _DashboardView(
                  dashboard: dashboard,
                  loading: loading,
                ),
                _AdminSection.users => _UsersView(api: api),
                _AdminSection.promos => _PromosView(api: api),
                _AdminSection.signatures => _SignaturesView(api: api),
                _AdminSection.audit => _AuditView(api: api),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({required this.dashboard, required this.loading});

  final Map<String, dynamic>? dashboard;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading && dashboard == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 90),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final metrics = _record(dashboard?['metrics']);
    final events = _records(dashboard?['events']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 920
                ? 5
                : constraints.maxWidth >= 620
                ? 3
                : 2;
            final cards = [
              _MetricData(
                'Мастера',
                _number(metrics['users']),
                Icons.people_alt_outlined,
                AppColors.orangeLight,
                AppColors.orangeDark,
              ),
              _MetricData(
                'Сметы',
                _number(metrics['estimates']),
                Icons.receipt_long_outlined,
                const Color(0xFFE6F1FB),
                AppColors.info,
              ),
              _MetricData(
                'Подписано',
                _number(metrics['signedEstimates']),
                Icons.verified_user_outlined,
                AppColors.successBg,
                AppColors.success,
              ),
              _MetricData(
                'Профи',
                _number(metrics['activePro']),
                Icons.workspace_premium_outlined,
                const Color(0xFFF1EAFE),
                const Color(0xFF6342A1),
              ),
              _MetricData(
                'Активные коды',
                _number(metrics['activePromos']),
                Icons.confirmation_number_outlined,
                const Color(0xFFFBE9D6),
                const Color(0xFF8F4D00),
              ),
            ];
            return GridView.count(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: columns == 2 ? 1.45 : 1.32,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final item in cards) _MetricCard(data: item)],
            );
          },
        ),
        const SizedBox(height: 22),
        SmetchikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bolt_outlined, color: AppColors.orangeDark),
                  SizedBox(width: 9),
                  Text(
                    'Последние события',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (events.isEmpty)
                const Text(
                  'Здесь появятся выдачи доступа и выгрузки документов.',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              else
                for (final event in events) _AuditLine(event: event),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricData {
  const _MetricData(
    this.label,
    this.value,
    this.icon,
    this.background,
    this.color,
  );

  final String label;
  final String value;
  final IconData icon;
  final Color background;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: data.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon, color: data.color, size: 21),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.value,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                data.label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsersView extends StatefulWidget {
  const _UsersView({required this.api});

  final AdminApi api;

  @override
  State<_UsersView> createState() => _UsersViewState();
}

class _UsersViewState extends State<_UsersView> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.call(
        'users',
        body: {'query': _query.text.trim()},
      );
      if (mounted) setState(() => _users = _records(data['users']));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _grant(Map<String, dynamic> user) async {
    final days = await _askDays(context, title: 'Выдать Профи');
    if (days == null) return;
    try {
      final data = await widget.api.call(
        'grant_subscription',
        body: {'userId': user['id'], 'days': days},
      );
      if (!mounted) return;
      final renewsAt = _date(data['renewsAt']);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Профи выдан до ${renewsAt == null ? 'указанной даты' : formatDate(renewsAt)}',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  Future<void> _revoke(Map<String, dynamic> user) async {
    final name = _fallback(user['fullName'], 'этого пользователя');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отключить Профи'),
        content: Text(
          '$name вернётся на Базовый тариф. Неиспользованные дни Профи будут сброшены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.api.call(
        'revoke_subscription',
        body: {'userId': user['id']},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пользователь переведён на Базовый тариф'),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                onSubmitted: (_) => _load(),
                decoration: const InputDecoration(
                  labelText: 'Поиск по имени, email или телефону',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              tooltip: 'Найти',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null) _InlineError(message: _error!),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_users.isEmpty)
          const _EmptyPanel(
            icon: Icons.people_outline,
            text: 'Пользователи не найдены',
          )
        else
          ..._users.map(
            (user) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AdminUserCard(
                user: user,
                onGrant: () => _grant(user),
                onRevoke: () => _revoke(user),
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminUserCard extends StatelessWidget {
  const _AdminUserCard({
    required this.user,
    required this.onGrant,
    required this.onRevoke,
  });

  final Map<String, dynamic> user;
  final VoidCallback onGrant;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final plan = user['subscriptionPlan']?.toString() ?? 'basic';
    final renewsAt = _date(user['subscriptionRenewsAt']);
    final pro =
        plan == 'pro' && (renewsAt == null || renewsAt.isAfter(DateTime.now()));
    return SmetchikCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pro ? AppColors.graphite : AppColors.orangeLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _initials(user['fullName']?.toString() ?? ''),
                  style: TextStyle(
                    color: pro ? AppColors.orange : AppColors.orangeDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fallback(user['fullName'], 'Без имени'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _fallback(user['email'], 'email не указан'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (_fallback(user['phone'], '').isNotEmpty)
                      Text(
                        _fallback(user['phone'], ''),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
          final action = pro
              ? OutlinedButton.icon(
                  onPressed: onRevoke,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: Color(0x33A32D2D)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  label: const Text('Отключить Профи'),
                )
              : FilledButton.icon(
                  onPressed: onGrant,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                  label: const Text('Выдать Профи'),
                );
          final status = _PlanPill(
            pro: pro,
            label: pro && renewsAt != null
                ? 'Профи до ${formatDate(renewsAt)}'
                : pro
                ? 'Профи'
                : 'Базовый',
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 12),
                status,
                const SizedBox(height: 12),
                action,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 12),
              status,
              const SizedBox(width: 10),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _PlanPill extends StatelessWidget {
  const _PlanPill({required this.pro, required this.label});

  final bool pro;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: pro ? AppColors.graphite : AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: pro ? AppColors.graphite : AppColors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: pro ? Colors.white : AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PromosView extends StatefulWidget {
  const _PromosView({required this.api});

  final AdminApi api;

  @override
  State<_PromosView> createState() => _PromosViewState();
}

class _PromosViewState extends State<_PromosView> {
  List<Map<String, dynamic>> _promos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.call('promos');
      if (mounted) setState(() => _promos = _records(data['promos']));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final request = await showDialog<_PromoRequest>(
      context: context,
      builder: (_) => const _PromoCreateDialog(),
    );
    if (request == null) return;
    try {
      final data = await widget.api.call(
        'create_promo',
        body: request.toJson(),
      );
      if (!mounted) return;
      final code = _fallback(data['code'], '');
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Промокод создан'),
          content: SelectableText(
            code,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Готово'),
            ),
          ],
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  Future<void> _toggle(Map<String, dynamic> promo) async {
    try {
      await widget.api.call(
        'set_promo_active',
        body: {'id': promo['id'], 'active': promo['is_active'] != true},
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SmetchikCard(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 540;
              final text = const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Доступ без оплаты',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Код можно ограничить сроком, количеством активаций и днями Профи.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              );
              final action = FilledButton.icon(
                onPressed: _create,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                icon: const Icon(Icons.add),
                label: const Text('Создать код'),
              );
              return narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [text, const SizedBox(height: 14), action],
                    )
                  : Row(
                      children: [
                        Expanded(child: text),
                        const SizedBox(width: 16),
                        action,
                      ],
                    );
            },
          ),
        ),
        const SizedBox(height: 14),
        if (_error != null) _InlineError(message: _error!),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_promos.isEmpty)
          const _EmptyPanel(
            icon: Icons.confirmation_number_outlined,
            text: 'Промокодов ещё нет',
          )
        else
          ..._promos.map(
            (promo) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PromoCard(promo: promo, onToggle: () => _toggle(promo)),
            ),
          ),
      ],
    );
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.promo, required this.onToggle});

  final Map<String, dynamic> promo;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final active = promo['is_active'] == true;
    final redemptions = _integer(promo['redemption_count']);
    final maximum = _integer(promo['max_redemptions']);
    final expires = _date(promo['expires_at']);
    final rawCode = _fallback(promo['code_value'], '');
    return SmetchikCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: active ? AppColors.orangeLight : AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.local_offer_outlined,
                  color: active ? AppColors.orangeDark : AppColors.textHint,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fallback(promo['title'], 'Промокод'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    if (rawCode.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: _PromoCodeValue(code: rawCode),
                      )
                    else
                      Text(
                        '${_fallback(promo['code_hint'], '***')} · ${_integer(promo['grant_days'])} дней Профи',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '$redemptions из $maximum активаций · ${_integer(promo['grant_days'])} дней Профи${expires == null ? '' : ' · до ${formatDate(expires)}'}',
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final switcher = Switch.adaptive(
            value: active,
            onChanged: (_) => onToggle(),
          );
          if (constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      active ? 'Активен' : 'Отключён',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    switcher,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 12),
              Text(
                active ? 'Активен' : 'Отключён',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              switcher,
            ],
          );
        },
      ),
    );
  }
}

class _PromoCodeValue extends StatelessWidget {
  const _PromoCodeValue({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.graphite,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Промокод скопирован')));
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              const Icon(Icons.copy_rounded, color: AppColors.orange, size: 17),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignaturesView extends StatefulWidget {
  const _SignaturesView({required this.api});

  final AdminApi api;

  @override
  State<_SignaturesView> createState() => _SignaturesViewState();
}

class _SignaturesViewState extends State<_SignaturesView> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _estimates = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.call(
        'signed_estimates',
        body: {'query': _query.text.trim()},
      );
      if (mounted) setState(() => _estimates = _records(data['estimates']));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _evidence(Map<String, dynamic> estimate) async {
    try {
      final data = await widget.api.call(
        'evidence',
        body: {'estimateId': estimate['id']},
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _EvidenceDialog(data: data, estimate: estimate),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _query,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(
            labelText: 'Объект, клиент или мастер',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Найти',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null) _InlineError(message: _error!),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_estimates.isEmpty)
          const _EmptyPanel(
            icon: Icons.verified_user_outlined,
            text: 'Подписанных смет пока нет',
          )
        else
          ..._estimates.map(
            (estimate) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SignedEstimateCard(
                estimate: estimate,
                onEvidence: () => _evidence(estimate),
              ),
            ),
          ),
      ],
    );
  }
}

class _SignedEstimateCard extends StatelessWidget {
  const _SignedEstimateCard({required this.estimate, required this.onEvidence});

  final Map<String, dynamic> estimate;
  final VoidCallback onEvidence;

  @override
  Widget build(BuildContext context) {
    final signedAt = _date(estimate['client_signed_at']);
    return SmetchikCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _fallback(estimate['object_title'], 'Смета'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                '${_fallback(estimate['client_signed_name'], 'Клиент')} · ${_fallback(estimate['masterName'], 'Мастер')}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatMoney(_asDouble(estimate['total_amount']))} · подписано ${signedAt == null ? '—' : formatDateTime(signedAt)}',
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
            ],
          );
          final action = OutlinedButton.icon(
            onPressed: onEvidence,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('Пакет'),
          );
          if (constraints.maxWidth < 510) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [details, const SizedBox(height: 12), action],
            );
          }
          return Row(
            children: [
              const Icon(Icons.verified, color: AppColors.success),
              const SizedBox(width: 10),
              Expanded(child: details),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _EvidenceDialog extends StatelessWidget {
  const _EvidenceDialog({required this.data, required this.estimate});

  final Map<String, dynamic> data;
  final Map<String, dynamic> estimate;

  @override
  Widget build(BuildContext context) {
    final master = _record(data['master']);
    final client = _record(data['client']);
    final files = _record(data['files']);
    return AlertDialog(
      title: const Text('Пакет доказательств'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Выгрузка фиксирует текущую неизменяемую версию документа и данные подписания.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 16),
              _EvidenceRow(
                label: 'Мастер',
                value: _fallback(master['full_name'], '—'),
              ),
              _EvidenceRow(
                label: 'Клиент',
                value: _fallback(
                  client['name'],
                  _fallback(estimate['client_signed_name'], '—'),
                ),
              ),
              _EvidenceRow(
                label: 'Подписано',
                value:
                    _date(
                          data['estimate'] is Map
                              ? (data['estimate'] as Map)['client_signed_at']
                              : null,
                        ) ==
                        null
                    ? '—'
                    : formatDateTime(
                        _date((data['estimate'] as Map)['client_signed_at'])!,
                      ),
              ),
              _EvidenceRow(
                label: 'Версия',
                value: '#${_fallback(estimate['document_version'], '1')}',
              ),
              if (_fallback(files['signedPdfUrl'], '').isNotEmpty)
                const _EvidenceRow(
                  label: 'PDF',
                  value: 'ссылка включена в экспорт',
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
        FilledButton.icon(
          onPressed: () {
            final title = _fallback(estimate['object_title'], 'smetchik');
            downloadAdminJson(
              fileName:
                  'smetchik-evidence-${_fallback(estimate['id'], 'document')}.json',
              contents: const JsonEncoder.withIndent('  ').convert(data),
            );
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Пакет «$title» скачан')));
          },
          icon: const Icon(Icons.download_outlined),
          label: const Text('Скачать JSON'),
        ),
      ],
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _AuditView extends StatefulWidget {
  const _AuditView({required this.api});

  final AdminApi api;

  @override
  State<_AuditView> createState() => _AuditViewState();
}

class _AuditViewState extends State<_AuditView> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.call('audit');
      if (mounted) setState(() => _events = _records(data['events']));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) return _InlineError(message: _error!);
    if (_events.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.history_outlined,
        text: 'Журнал пока пуст',
      );
    }
    return SmetchikCard(
      child: Column(
        children: [for (final event in _events) _AuditLine(event: event)],
      ),
    );
  }
}

class _AuditLine extends StatelessWidget {
  const _AuditLine({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final at = _date(event['created_at']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bolt_outlined,
              color: AppColors.orangeDark,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _auditLabel(_fallback(event['action'], 'Событие')),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (_fallback(event['entity_type'], '').isNotEmpty)
                  Text(
                    '${_fallback(event['entity_type'], '')} · ${_fallback(event['entity_id'], '')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            at == null ? '—' : formatDateTime(at),
            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PromoCreateDialog extends StatefulWidget {
  const _PromoCreateDialog();

  @override
  State<_PromoCreateDialog> createState() => _PromoCreateDialogState();
}

class _PromoCreateDialogState extends State<_PromoCreateDialog> {
  final _title = TextEditingController(text: 'Профи на 30 дней');
  final _code = TextEditingController();
  final _days = TextEditingController(text: '30');
  final _limit = TextEditingController(text: '1');
  DateTime? _expiresAt;

  @override
  void dispose() {
    _title.dispose();
    _code.dispose();
    _days.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 1095)),
      locale: const Locale('ru'),
    );
    if (date != null && mounted) setState(() => _expiresAt = date);
  }

  void _submit() {
    final days = int.tryParse(_days.text) ?? 0;
    final limit = int.tryParse(_limit.text) ?? 0;
    if (_title.text.trim().isEmpty || days < 1 || limit < 1) return;
    Navigator.of(context).pop(
      _PromoRequest(
        title: _title.text.trim(),
        code: _code.text.trim(),
        days: days,
        limit: limit,
        expiresAt: _expiresAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый промокод'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Название для себя',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Свой код',
                  hintText: 'Оставьте пустым для генерации',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _days,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Дней Профи',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _limit,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Активаций'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickExpiry,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _expiresAt == null
                      ? 'Без срока действия'
                      : 'Действует до ${formatDate(_expiresAt!)}',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Создать')),
      ],
    );
  }
}

class _PromoRequest {
  const _PromoRequest({
    required this.title,
    required this.code,
    required this.days,
    required this.limit,
    required this.expiresAt,
  });

  final String title;
  final String code;
  final int days;
  final int limit;
  final DateTime? expiresAt;

  Map<String, dynamic> toJson() => {
    'title': title,
    'code': code,
    'grantDays': days,
    'maxRedemptions': limit,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
  };
}

class _AdminMark extends StatelessWidget {
  const _AdminMark({required this.dark, this.compact = false});

  final bool dark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 30 : 36,
          height: compact ? 30 : 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(compact ? 9 : 11),
          ),
          child: Icon(
            Icons.receipt_long_outlined,
            color: Colors.white,
            size: compact ? 18 : 21,
          ),
        ),
        const SizedBox(width: 9),
        Text(
          compact ? 'Сметчик · Админ' : 'Сметчик',
          style: TextStyle(
            color: dark ? Colors.white : AppColors.graphite,
            fontSize: compact ? 16 : 19,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _AdminNotice extends StatelessWidget {
  const _AdminNotice({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: _AdminNotice(
      icon: Icons.error_outline,
      color: AppColors.danger,
      background: AppColors.dangerBg,
      text: message,
    ),
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => SmetchikCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 52),
      child: Column(
        children: [
          Icon(icon, size: 38, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

Future<int?> _askDays(BuildContext context, {required String title}) async {
  final controller = TextEditingController(text: '30');
  final value = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Количество дней'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(int.tryParse(controller.text)),
          child: const Text('Выдать'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value == null || value < 1 ? null : value;
}

Map<String, dynamic> _record(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

List<Map<String, dynamic>> _records(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : const [];

String _fallback(Object? value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? fallback : text;
}

String _number(Object? value) =>
    NumberFormat.decimalPattern('ru_RU').format(_integer(value));

int _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

double _asDouble(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2);
  final value = parts.map((part) => part[0].toUpperCase()).join();
  return value.isEmpty ? 'СМ' : value;
}

String _message(Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '').trim();
  return raw.isEmpty ? 'Не удалось выполнить действие.' : raw;
}

String _auditLabel(String action) {
  return switch (action) {
    'promo_created' => 'Создан промокод',
    'promo_enabled' => 'Промокод включён',
    'promo_disabled' => 'Промокод отключён',
    'promo_redeemed' => 'Промокод активирован',
    'subscription_granted' => 'Выдан доступ Профи',
    'signed_estimate_evidence_exported' => 'Выгружен пакет доказательств',
    _ => action.replaceAll('_', ' '),
  };
}
