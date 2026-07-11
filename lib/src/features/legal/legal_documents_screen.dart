import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart';
import '../../legal/legal_documents.dart';
import '../../shared/ui.dart';

class LegalDocumentsScreen extends StatelessWidget {
  const LegalDocumentsScreen({super.key, this.documentId});

  final String? documentId;

  @override
  Widget build(BuildContext context) {
    final document = documentId == null
        ? null
        : LegalDocuments.byId(documentId!);
    if (document == null) return _documentList(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/auth'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(document.title),
      ),
      body: ResponsiveListView(
        maxWidth: 840,
        children: [
          Text(
            document.title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Версия ${document.version}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          SmetchikCard(
            child: SelectionArea(
              child: Text(
                document.body.trim(),
                style: const TextStyle(height: 1.48, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _documentList(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Правовая информация')),
      body: ResponsiveListView(
        maxWidth: 720,
        children: [
          for (final document in LegalDocuments.values) ...[
            SmetchikCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.orangeLight,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.article_outlined,
                    color: AppColors.orange,
                  ),
                ),
                title: Text(
                  document.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(document.summary),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/legal/${document.id}'),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
