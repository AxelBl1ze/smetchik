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
          : AppBar(title: const _AdminMark(dark: false, compact: true)),
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

class _AdminContent extends StatefulWidget {
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
  State<_AdminContent> createState() => _AdminContentState();
}

class _AdminContentState extends State<_AdminContent> {
  final Map<_AdminSection, Widget> _cachedTabs = {};

  Widget _tabFor(_AdminSection section, Map<String, dynamic> operator) {
    if (section == _AdminSection.overview) {
      return _DashboardView(
        dashboard: widget.dashboard,
        loading: widget.loading,
      );
    }

    return _cachedTabs.putIfAbsent(section, () {
      final isOwner = _fallback(operator['role'], 'owner') == 'owner';
      return switch (section) {
        _AdminSection.users => _UsersView(
          api: widget.api,
          canManageAdmins: isOwner,
          currentAdminId: _fallback(operator['id'], ''),
        ),
        _AdminSection.promos => _PromosView(api: widget.api),
        _AdminSection.signatures => _SignaturesView(api: widget.api),
        _AdminSection.audit => _AuditView(api: widget.api),
        _AdminSection.overview => throw StateError('Обзор создаётся отдельно.'),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final operator = _record(widget.dashboard?['operator']);
    final title = switch (widget.section) {
      _AdminSection.overview => 'Обзор',
      _AdminSection.users => 'Пользователи',
      _AdminSection.promos => 'Промокоды',
      _AdminSection.signatures => 'Подписанные сметы',
      _AdminSection.audit => 'Журнал действий',
    };
    final subtitle = switch (widget.section) {
      _AdminSection.overview => 'Состояние сервиса и последние события',
      _AdminSection.users => 'Тарифы, блокировки и служебные доступы',
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
                  _AdminRefreshButton(
                    enabled: !widget.loading,
                    onTap: widget.onRefresh,
                  ),
                ],
              ),
            ),
          ),
          if (widget.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: _AdminNotice(
                  icon: Icons.lock_outline,
                  color: AppColors.danger,
                  background: AppColors.dangerBg,
                  text: widget.error!,
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            sliver: SliverToBoxAdapter(child: _cachedBody(operator)),
          ),
        ],
      ),
    );
  }

  Widget _cachedBody(Map<String, dynamic> operator) {
    _cachedTabs[_AdminSection.overview] = _tabFor(
      _AdminSection.overview,
      operator,
    );
    _tabFor(widget.section, operator);
    final sections = _cachedTabs.keys.toList(growable: false);
    return IndexedStack(
      index: sections.indexOf(widget.section),
      children: sections
          .map(
            (section) => KeyedSubtree(
              key: PageStorageKey('admin-${section.name}'),
              child: _cachedTabs[section]!,
            ),
          )
          .toList(growable: false),
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
                'Платные',
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
  const _UsersView({
    required this.api,
    required this.canManageAdmins,
    required this.currentAdminId,
  });

  final AdminApi api;
  final bool canManageAdmins;
  final String currentAdminId;

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
      builder: (context) => _AdminConfirmDialog(
        icon: Icons.workspace_premium_outlined,
        title: 'Отключить Профи',
        description:
            '$name вернётся на Базовый тариф. Неиспользованные дни Профи будут сброшены.',
        confirmLabel: 'Отключить',
        danger: true,
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

  Future<void> _setBlocked(Map<String, dynamic> user, bool blocked) async {
    final name = _fallback(user['fullName'], 'этого пользователя');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _AdminConfirmDialog(
        icon: blocked ? Icons.block_outlined : Icons.lock_open_rounded,
        title: blocked
            ? 'Заблокировать пользователя'
            : 'Разблокировать пользователя',
        description: blocked
            ? '$name не сможет войти в Сметчик, пока вы не снимете блокировку.'
            : '$name снова сможет войти в Сметчик.',
        confirmLabel: blocked ? 'Заблокировать' : 'Разблокировать',
        danger: blocked,
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.call(
        'set_user_block',
        body: {'userId': user['id'], 'blocked': blocked},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? 'Пользователь заблокирован'
                : 'Пользователь разблокирован',
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

  Future<void> _setAdminRole(Map<String, dynamic> user, String? role) async {
    final name = _fallback(user['fullName'], 'этого пользователя');
    final label = _adminRoleLabel(role);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _AdminConfirmDialog(
        icon: role == null
            ? Icons.admin_panel_settings_outlined
            : Icons.verified_user_outlined,
        title: role == null ? 'Отозвать доступ' : 'Назначить роль',
        description: role == null
            ? '$name потеряет доступ к админ-панели.'
            : '$name получит роль «$label» в админ-панели.',
        confirmLabel: role == null ? 'Отозвать' : 'Назначить',
        danger: role == null,
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.call(
        'set_admin_role',
        body: {'userId': user['id'], 'role': role},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            role == null
                ? 'Служебный доступ отозван'
                : 'Роль «$label» назначена',
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
                onBlockChanged: (blocked) => _setBlocked(user, blocked),
                onAdminRoleChanged: widget.canManageAdmins
                    ? (role) => _setAdminRole(user, role)
                    : null,
                currentAdminId: widget.currentAdminId,
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
    required this.onBlockChanged,
    required this.onAdminRoleChanged,
    required this.currentAdminId,
  });

  final Map<String, dynamic> user;
  final VoidCallback onGrant;
  final VoidCallback onRevoke;
  final ValueChanged<bool> onBlockChanged;
  final ValueChanged<String?>? onAdminRoleChanged;
  final String currentAdminId;

  void _openControls(
    BuildContext context, {
    required String adminRole,
    required bool blocked,
    required bool canBlock,
    required bool canChangeRoles,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _UserControlsSheet(
        userName: _fallback(user['fullName'], 'Пользователь'),
        adminRole: adminRole,
        blocked: blocked,
        canBlock: canBlock,
        canChangeRoles: canChangeRoles,
        onBlockChanged: onBlockChanged,
        onAdminRoleChanged: onAdminRoleChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = user['subscriptionPlan']?.toString() ?? 'basic';
    final renewsAt = _date(user['subscriptionRenewsAt']);
    final pro =
        plan == 'pro' && (renewsAt == null || renewsAt.isAfter(DateTime.now()));
    final team = _record(user['team']);
    final teamManaged = user['teamManaged'] == true || plan == 'team';
    final isTeamOwner = team['role']?.toString() == 'owner';
    final teamActive =
        teamManaged && (renewsAt == null || renewsAt.isAfter(DateTime.now()));
    final paid = pro || teamActive;
    final bannedUntil = _date(user['bannedUntil']);
    final blocked = bannedUntil != null && bannedUntil.isAfter(DateTime.now());
    final adminRole = _fallback(user['adminRole'], '');
    final isCurrentAdmin = user['id']?.toString() == currentAdminId;
    final canBlock = adminRole.isEmpty;
    final canChangeRoles = onAdminRoleChanged != null && !isCurrentAdmin;
    final canManage = canBlock || canChangeRoles;
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
                  color: paid ? AppColors.graphite : AppColors.orangeLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _initials(user['fullName']?.toString() ?? ''),
                  style: TextStyle(
                    color: paid ? AppColors.orange : AppColors.orangeDark,
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
                    if (adminRole.isNotEmpty || blocked || teamManaged) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (adminRole.isNotEmpty)
                            _UserMiniPill(
                              icon: Icons.admin_panel_settings_outlined,
                              label: _adminRoleLabel(adminRole),
                              color: AppColors.info,
                              background: AppColors.infoBg,
                            ),
                          if (blocked)
                            const _UserMiniPill(
                              icon: Icons.block_outlined,
                              label: 'Заблокирован',
                              color: AppColors.danger,
                              background: AppColors.dangerBg,
                            ),
                          if (teamManaged)
                            _UserMiniPill(
                              icon: Icons.groups_2_outlined,
                              label: isTeamOwner
                                  ? 'Владелец бригады'
                                  : 'Участник бригады',
                              color: AppColors.orangeDark,
                              background: AppColors.orangeLight,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
          final action = teamManaged
              ? null
              : pro
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
            premium: paid,
            label: teamManaged
                ? renewsAt != null
                      ? 'Бригада до ${formatDate(renewsAt)}'
                      : 'Бригада'
                : pro && renewsAt != null
                ? 'Профи до ${formatDate(renewsAt)}'
                : pro
                ? 'Профи'
                : 'Базовый',
          );
          final menu = canManage
              ? IconButton.outlined(
                  tooltip: 'Управление пользователем',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.graphite,
                    backgroundColor: AppColors.card,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  onPressed: () => _openControls(
                    context,
                    adminRole: adminRole,
                    blocked: blocked,
                    canBlock: canBlock,
                    canChangeRoles: canChangeRoles,
                  ),
                  icon: const Icon(Icons.tune_rounded),
                )
              : null;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 12),
                status,
                const SizedBox(height: 12),
                if (action != null)
                  Row(
                    children: [
                      Expanded(child: action),
                      if (menu != null) ...[const SizedBox(width: 8), menu],
                    ],
                  )
                else if (menu != null)
                  Align(alignment: Alignment.centerRight, child: menu),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 12),
              status,
              if (action != null) ...[const SizedBox(width: 10), action],
              if (menu != null) ...[const SizedBox(width: 4), menu],
            ],
          );
        },
      ),
    );
  }
}

class _UserControlsSheet extends StatelessWidget {
  const _UserControlsSheet({
    required this.userName,
    required this.adminRole,
    required this.blocked,
    required this.canBlock,
    required this.canChangeRoles,
    required this.onBlockChanged,
    required this.onAdminRoleChanged,
  });

  final String userName;
  final String adminRole;
  final bool blocked;
  final bool canBlock;
  final bool canChangeRoles;
  final ValueChanged<bool> onBlockChanged;
  final ValueChanged<String?>? onAdminRoleChanged;

  void _closeThen(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.graphite,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: AppColors.orange,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Управление доступом',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          userName,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (canBlock) ...[
                const SizedBox(height: 16),
                _UserControlActionButton(
                  icon: blocked
                      ? Icons.lock_open_rounded
                      : Icons.block_outlined,
                  title: blocked
                      ? 'Разблокировать аккаунт'
                      : 'Заблокировать аккаунт',
                  subtitle: blocked
                      ? 'Пользователь снова сможет войти.'
                      : 'Доступ к приложению будет закрыт.',
                  color: blocked ? AppColors.success : AppColors.danger,
                  background: blocked
                      ? AppColors.successBg
                      : AppColors.dangerBg,
                  onTap: () =>
                      _closeThen(context, () => onBlockChanged(!blocked)),
                ),
              ],
              if (canChangeRoles) ...[
                const SizedBox(height: 18),
                const Text(
                  'Роль в админ-панели',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                for (final role in const ['owner', 'support', 'auditor']) ...[
                  _UserControlActionButton(
                    icon: _adminRoleIcon(role),
                    title: _adminRoleLabel(role),
                    subtitle: _adminRoleDescription(role),
                    selected: adminRole == role,
                    onTap: adminRole == role
                        ? null
                        : () => _closeThen(
                            context,
                            () => onAdminRoleChanged?.call(role),
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (adminRole.isNotEmpty)
                  _UserControlActionButton(
                    icon: Icons.remove_moderator_outlined,
                    title: 'Отозвать админ-доступ',
                    subtitle: 'Оставить доступ только к приложению мастера.',
                    color: AppColors.danger,
                    background: AppColors.dangerBg,
                    onTap: () => _closeThen(
                      context,
                      () => onAdminRoleChanged?.call(null),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UserControlActionButton extends StatelessWidget {
  const _UserControlActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color = AppColors.graphite,
    this.background = AppColors.background,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color background;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = selected ? AppColors.orangeDark : color;
    return Material(
      color: selected ? AppColors.orangeLight : background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.orange : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: activeColor, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: activeColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: AppColors.orange),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserMiniPill extends StatelessWidget {
  const _UserMiniPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _PlanPill extends StatelessWidget {
  const _PlanPill({required this.premium, required this.label});

  final bool premium;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: premium ? AppColors.graphite : AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: premium ? AppColors.graphite : AppColors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: premium ? Colors.white : AppColors.textSecondary,
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
        builder: (_) => _PromoCreatedDialog(code: code),
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
                    'Выберите тариф, срок и количество активаций для кода.',
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
                        '${_fallback(promo['code_hint'], '***')} · ${_integer(promo['grant_days'])} дней ${promo['plan'] == 'team' ? 'Бригада' : 'Профи'}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '$redemptions из $maximum активаций · ${_integer(promo['grant_days'])} дней ${promo['plan'] == 'team' ? 'Бригада' : 'Профи'}${expires == null ? '' : ' · до ${formatDate(expires)}'}',
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

  void _exportRegistry() {
    final stamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    downloadAdminJson(
      fileName: 'smetchik-signed-estimates-$stamp.json',
      contents: const JsonEncoder.withIndent('  ').convert({
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'count': _estimates.length,
        'estimates': _estimates,
      }),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Реестр подписанных смет скачан')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final field = TextField(
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
            );
            final export = OutlinedButton.icon(
              onPressed: _loading || _estimates.isEmpty
                  ? null
                  : _exportRegistry,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Реестр'),
            );
            if (constraints.maxWidth < 540) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [field, const SizedBox(height: 10), export],
              );
            }
            return Row(
              children: [
                Expanded(child: field),
                const SizedBox(width: 10),
                export,
              ],
            );
          },
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
  final _query = TextEditingController();
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;
  String _category = 'all';

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
        'audit',
        body: {'query': _query.text.trim(), 'category': _category},
      );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _query,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(
            labelText: 'Поиск по действию или идентификатору',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Найти',
              onPressed: _load,
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final item in const [
                ('all', 'Все'),
                ('access', 'Доступы'),
                ('promos', 'Промокоды'),
                ('documents', 'Документы'),
                ('admins', 'Админы'),
              ]) ...[
                ChoiceChip(
                  label: Text(item.$2),
                  selected: _category == item.$1,
                  onSelected: (_) {
                    if (_category == item.$1) return;
                    setState(() => _category = item.$1);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          _InlineError(message: _error!)
        else if (_events.isEmpty)
          const _EmptyPanel(
            icon: Icons.history_outlined,
            text: 'События по этому фильтру не найдены',
          )
        else
          SmetchikCard(
            child: Column(
              children: [for (final event in _events) _AuditLine(event: event)],
            ),
          ),
      ],
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
  final _days = TextEditingController(text: '30');
  final _limit = TextEditingController(text: '1');
  DateTime? _expiresAt;
  String _plan = 'pro';

  @override
  void dispose() {
    _title.dispose();
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
        plan: _plan,
        days: days,
        limit: limit,
        expiresAt: _expiresAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AdminDialogFrame(
      icon: Icons.local_offer_outlined,
      title: 'Новый промокод',
      subtitle: 'Код из 16 символов будет создан автоматически.',
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Создать'),
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Название для себя'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            style: ButtonStyle(
              visualDensity: VisualDensity.standard,
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.graphite
                    : AppColors.background,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : AppColors.textSecondary,
              ),
              side: const WidgetStatePropertyAll(
                BorderSide(color: AppColors.border),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            segments: const [
              ButtonSegment(
                value: 'pro',
                label: Text('Профи'),
                icon: Icon(Icons.workspace_premium_outlined),
              ),
              ButtonSegment(
                value: 'team',
                label: Text('Бригада'),
                icon: Icon(Icons.groups_2_outlined),
              ),
            ],
            selected: {_plan},
            onSelectionChanged: (value) => setState(() => _plan = value.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _days,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Дней Профи'),
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
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _pickExpiry,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _expiresAt == null
                    ? 'Без срока действия'
                    : 'Действует до ${formatDate(_expiresAt!)}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoRequest {
  const _PromoRequest({
    required this.title,
    required this.plan,
    required this.days,
    required this.limit,
    required this.expiresAt,
  });

  final String title;
  final String plan;
  final int days;
  final int limit;
  final DateTime? expiresAt;

  Map<String, dynamic> toJson() => {
    'title': title,
    'plan': plan,
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

class _AdminDialogFrame extends StatelessWidget {
  const _AdminDialogFrame({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.orangeLight,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(icon, color: AppColors.orangeDark),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Divider(height: 1),
                ),
                child,
                if (footer != null) ...[const SizedBox(height: 18), footer!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminRefreshButton extends StatelessWidget {
  const _AdminRefreshButton({required this.enabled, required this.onTap});

  final bool enabled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.graphite : AppColors.graphite2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: const SizedBox(
          width: 46,
          height: 46,
          child: Icon(Icons.refresh_rounded, color: AppColors.orange),
        ),
      ),
    );
  }
}

class _AdminConfirmDialog extends StatelessWidget {
  const _AdminConfirmDialog({
    required this.icon,
    required this.title,
    required this.description,
    required this.confirmLabel,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String confirmLabel;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return _AdminDialogFrame(
      icon: icon,
      title: title,
      subtitle: danger
          ? 'Действие можно отменить позднее в админ-панели.'
          : null,
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: danger ? AppColors.danger : AppColors.graphite,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ),
        ],
      ),
      child: Text(
        description,
        style: const TextStyle(
          color: AppColors.textSecondary,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PromoCreatedDialog extends StatelessWidget {
  const _PromoCreatedDialog({required this.code});

  final String code;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Промокод скопирован')));
  }

  @override
  Widget build(BuildContext context) {
    return _AdminDialogFrame(
      icon: Icons.verified_outlined,
      title: 'Промокод создан',
      subtitle: 'Сохраните код: он будет доступен в списке промокодов.',
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Копировать'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.graphite,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Готово'),
            ),
          ),
        ],
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.graphite,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          code,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.3,
          ),
        ),
      ),
    );
  }
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
    builder: (context) => _AdminDialogFrame(
      icon: Icons.workspace_premium_outlined,
      title: title,
      subtitle: 'Доступ включится сразу после подтверждения.',
      footer: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.graphite,
              ),
              onPressed: () =>
                  Navigator.of(context).pop(int.tryParse(controller.text)),
              child: const Text('Выдать'),
            ),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Количество дней'),
      ),
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

String _adminRoleLabel(String? role) {
  return switch (role) {
    'owner' => 'Владелец',
    'support' => 'Поддержка',
    'auditor' => 'Аудитор',
    _ => 'Без роли',
  };
}

IconData _adminRoleIcon(String role) {
  return switch (role) {
    'owner' => Icons.workspace_premium_outlined,
    'support' => Icons.support_agent_rounded,
    'auditor' => Icons.fact_check_outlined,
    _ => Icons.admin_panel_settings_outlined,
  };
}

String _adminRoleDescription(String role) {
  return switch (role) {
    'owner' => 'Полный доступ к настройкам и сотрудникам.',
    'support' => 'Пользователи, тарифы и промокоды.',
    'auditor' => 'Только журнал и подписанные документы.',
    _ => '',
  };
}

String _auditLabel(String action) {
  return switch (action) {
    'promo_created' => 'Создан промокод',
    'promo_enabled' => 'Промокод включён',
    'promo_disabled' => 'Промокод отключён',
    'promo_redeemed' => 'Промокод активирован',
    'subscription_granted' => 'Выдан доступ Профи',
    'subscription_revoked' => 'Отключён доступ Профи',
    'user_blocked' => 'Пользователь заблокирован',
    'user_unblocked' => 'Пользователь разблокирован',
    'admin_role_changed' => 'Изменены права администратора',
    'signed_estimate_evidence_exported' => 'Выгружен пакет доказательств',
    _ => action.replaceAll('_', ' '),
  };
}
