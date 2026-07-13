import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'core/auth_controller.dart';
import 'features/auth/auth_screen.dart';
import 'features/catalog/catalog_screen.dart';
import 'features/clients/client_form_screen.dart';
import 'features/clients/clients_screen.dart';
import 'features/config/config_required_screen.dart';
import 'features/estimates/client_approval_screen.dart';
import 'features/estimates/estimate_detail_screen.dart';
import 'features/estimates/estimate_form_screen.dart';
import 'features/estimates/estimates_screen.dart';
import 'features/home/home_screen.dart';
import 'features/legal/legal_documents_screen.dart';
import 'features/projects/project_detail_screen.dart';
import 'features/projects/project_form_screen.dart';
import 'features/settings/settings_screen.dart';
import 'shared/app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.read(authControllerProvider);

  final router = GoRouter(
    initialLocation: AppConfig.hasSupabaseConfig ? '/home' : '/config',
    refreshListenable: auth,
    redirect: (context, state) {
      final path = state.uri.path;
      final isAuthPath = path == '/auth' || path == '/auth/reset';
      final isLegalPath = path == '/legal' || path.startsWith('/legal/');
      final isApprovalPath = path.startsWith('/approve/');

      if (!AppConfig.hasSupabaseConfig) {
        return path == '/config' ? null : '/config';
      }

      if (!auth.isLoggedIn) {
        return isAuthPath || isLegalPath || isApprovalPath ? null : '/auth';
      }

      if (auth.isPasswordRecovery && path != '/auth/reset') {
        return '/auth/reset';
      }

      if (path == '/' || path == '/config' || path == '/onboarding') {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _page(state, const HomeScreen()),
      ),
      GoRoute(
        path: '/config',
        pageBuilder: (context, state) =>
            _page(state, const ConfigRequiredScreen()),
      ),
      GoRoute(
        path: '/auth',
        pageBuilder: (context, state) => _page(state, const AuthScreen()),
      ),
      GoRoute(
        path: '/auth/reset',
        pageBuilder: (context, state) => _page(
          state,
          const AuthScreen(initialMode: AuthEntryMode.resetPassword),
        ),
      ),
      GoRoute(
        path: '/legal',
        pageBuilder: (context, state) =>
            _page(state, const LegalDocumentsScreen()),
      ),
      GoRoute(
        path: '/legal/:id',
        pageBuilder: (context, state) => _page(
          state,
          LegalDocumentsScreen(documentId: state.pathParameters['id']),
        ),
      ),
      GoRoute(
        path: '/approve/:token',
        pageBuilder: (context, state) => _page(
          state,
          ClientApprovalScreen(token: state.pathParameters['token']!),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(
          selectedIndex: _shellIndexForPath(state.uri.path),
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => _page(state, const HomeScreen()),
          ),
          GoRoute(
            path: '/estimates',
            pageBuilder: (context, state) =>
                _page(state, const EstimatesScreen()),
          ),
          GoRoute(
            path: '/catalog',
            pageBuilder: (context, state) =>
                _page(state, const CatalogScreen()),
          ),
          GoRoute(
            path: '/clients',
            pageBuilder: (context, state) =>
                _page(state, const ClientsScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                _page(state, const SettingsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/clients/new',
        pageBuilder: (context, state) => _page(state, const ClientFormScreen()),
      ),
      GoRoute(
        path: '/clients/:id/edit',
        pageBuilder: (context, state) => _page(
          state,
          ClientFormScreen(clientId: state.pathParameters['id']),
        ),
      ),
      GoRoute(
        path: '/estimate/new',
        pageBuilder: (context, state) =>
            _page(state, const EstimateFormScreen()),
      ),
      GoRoute(
        path: '/estimate/:id/edit',
        pageBuilder: (context, state) => _page(
          state,
          EstimateFormScreen(
            estimateId: state.pathParameters['id'],
            createRevision: state.uri.queryParameters['revision'] == 'true',
          ),
        ),
      ),
      GoRoute(
        path: '/estimate/:id',
        pageBuilder: (context, state) => _page(
          state,
          EstimateDetailScreen(estimateId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/projects/new',
        pageBuilder: (context, state) =>
            _page(state, const ProjectFormScreen()),
      ),
      GoRoute(
        path: '/projects/:id/edit',
        pageBuilder: (context, state) => _page(
          state,
          ProjectFormScreen(projectId: state.pathParameters['id']),
        ),
      ),
      GoRoute(
        path: '/projects/:id',
        pageBuilder: (context, state) => _page(
          state,
          ProjectDetailScreen(projectId: state.pathParameters['id']!),
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class SmetchikApp extends ConsumerWidget {
  const SmetchikApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Сметчик',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}

Page<void> _page(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}

int _shellIndexForPath(String path) {
  return switch (path) {
    '/home' => 0,
    '/estimates' => 1,
    '/catalog' => 2,
    '/clients' => 3,
    '/settings' => 4,
    _ => 0,
  };
}
