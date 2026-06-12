import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/ui.dart';

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
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;
    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: null,
              actions: [
                IconButton(
                  tooltip: 'Добавить клиента',
                  onPressed: () => context.push('/clients/new'),
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
                          onPressed: () => context.push('/clients/new'),
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
                      onPressed: () => context.push('/clients/new'),
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
