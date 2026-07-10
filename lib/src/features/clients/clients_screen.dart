import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/ui.dart';
import '../../shared/upgrade_sheet.dart';

class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider);
    final profile = ref.watch(profileProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;
    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: null,
              actions: [
                IconButton(
                  tooltip: 'Добавить клиента',
                  onPressed: () => _openNewClient(profile, clients),
                  icon: const Icon(Icons.person_add_alt_1),
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(clientsProvider),
        child: ResponsiveListView(
          maxWidth: 980,
          children: [
            ScreenTitle(
              title: 'Клиенты',
              subtitle: 'Контакты, адреса объектов и заметки по людям',
              icon: Icons.contact_phone_outlined,
              actions: isDesktop
                  ? [
                      SizedBox(
                        width: 210,
                        child: FilledButton.icon(
                          onPressed: () => _openNewClient(profile, clients),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Добавить клиента'),
                        ),
                      ),
                    ]
                  : const [],
            ),
            const SizedBox(height: 14),
            _ClientsSearchField(onChanged: _setQuery),
            const SizedBox(height: 12),
            profile.when(
              data: (value) => clients.when(
                data: (items) => _ClientLimitBanner(
                  profile: value,
                  clientsCount: items.length,
                  onUpgrade: _openPlans,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            profile.asData?.value?.hasActivePro == true
                ? const SizedBox.shrink()
                : const SizedBox(height: 12),
            clients.when(
              data: (items) {
                final filtered = items.where((client) {
                  final haystack =
                      '${client.name} ${client.phone ?? ''} ${client.objectAddress ?? ''}'
                          .toLowerCase();
                  return haystack.contains(_query);
                }).toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.contact_phone_outlined,
                    title: 'Клиентов ещё нет',
                    body:
                        'Добавьте клиента вручную или он появится при создании сметы.',
                    action: FilledButton.icon(
                      onPressed: () => _openNewClient(profile, clients),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Добавить клиента'),
                    ),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 760;
                    if (isDesktop) {
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              mainAxisExtent: 92,
                            ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) =>
                            _ClientCard(client: filtered[index]),
                      );
                    }
                    return Column(
                      children: [
                        for (final client in filtered) ...[
                          _ClientCard(client: client),
                          const SizedBox(height: 8),
                        ],
                      ],
                    );
                  },
                );
              },
              loading: () => const LoadingPane(),
              error: (error, _) => ErrorPane(error: error),
            ),
          ],
        ),
      ),
    );
  }

  void _setQuery(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }

  void _openNewClient(
    AsyncValue<ProfileModel?> profile,
    AsyncValue<List<ClientModel>> clients,
  ) {
    final current = profile.asData?.value;
    final items = clients.asData?.value ?? const <ClientModel>[];
    if (current?.hasActivePro != true &&
        items.length >= ProfileModel.basicClientLimit) {
      showUpgradeSheet(
        context: context,
        message:
            'На Базовом тарифе можно хранить до ${ProfileModel.basicClientLimit} клиентов. Подключите Профи, чтобы вести клиентскую базу без ограничений.',
        onOpenPlans: _openPlans,
      );
      return;
    }
    context.push('/clients/new');
  }

  void _openPlans() {
    context.go('/settings');
  }
}

class _ClientLimitBanner extends StatelessWidget {
  const _ClientLimitBanner({
    required this.profile,
    required this.clientsCount,
    required this.onUpgrade,
  });

  final ProfileModel? profile;
  final int clientsCount;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    if (profile?.hasActivePro == true) return const SizedBox.shrink();
    final limit = ProfileModel.basicClientLimit;
    final displayed = clientsCount > limit ? limit : clientsCount;
    final remaining = limit - displayed;
    final reached = remaining == 0;
    return SmetchikCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                reached ? Icons.lock_outline : Icons.group_outlined,
                color: reached ? AppColors.danger : AppColors.orangeDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reached
                      ? 'Лимит клиентов исчерпан'
                      : 'Базовый тариф: $displayed/$limit клиентов',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (reached)
                FilledButton(
                  onPressed: onUpgrade,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: const Text('Профи'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: (clientsCount / limit).clamp(0.0, 1.0),
              color: reached ? AppColors.danger : AppColors.orange,
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            reached
                ? 'Подключите Профи, чтобы добавлять клиентов без ограничений.'
                : 'Осталось $remaining клиентов на Базовом тарифе.',
            style: TextStyle(
              color: reached ? AppColors.danger : AppColors.textHint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientsSearchField extends StatelessWidget {
  const _ClientsSearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: const InputDecoration(
        hintText: 'Поиск клиентов',
        prefixIcon: Icon(Icons.search),
      ),
      onChanged: onChanged,
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client});

  final ClientModel client;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      onTap: () => context.push('/clients/${client.id}/edit'),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.orangeLight,
            foregroundColor: AppColors.orangeDark,
            child: Text(
              client.name.isEmpty
                  ? '?'
                  : client.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  client.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (client.phone?.isNotEmpty == true)
                  Text(
                    client.phone!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                if (client.objectAddress?.isNotEmpty == true)
                  Text(
                    client.objectAddress!,
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
          const Icon(Icons.chevron_right, color: AppColors.textHint),
        ],
      ),
    );
  }
}
