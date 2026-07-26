import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_error.dart';
import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/ui.dart';

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(supportTicketsProvider);
    return Scaffold(
      body: tickets.when(
        loading: () => const LoadingPane(),
        error: (error, _) => ErrorPane(error: error),
        data: (items) => ResponsiveListView(
          maxWidth: 760,
          children: [
            ScreenTitle(
              title: 'Поддержка',
              subtitle: 'Ответим здесь и сохраним историю обращения',
              icon: Icons.support_agent_rounded,
              actions: [
                FilledButton.icon(
                  onPressed: () => _openNewTicket(context, ref),
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('Новое обращение'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (items.isEmpty)
              EmptyState(
                icon: Icons.forum_outlined,
                title: 'Обращений пока нет',
                body:
                    'Если что-то не работает или нужна помощь с приложением, напишите нам.',
                action: FilledButton.icon(
                  onPressed: () => _openNewTicket(context, ref),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Написать в поддержку'),
                ),
              )
            else
              Column(
                children: [
                  for (final ticket in items) ...[
                    _TicketCard(
                      ticket: ticket,
                      onTap: () => context.push('/support/${ticket.id}'),
                    ),
                    if (ticket != items.last) const SizedBox(height: 10),
                  ],
                ],
              ),
            const SizedBox(height: 18),
            const _SupportHint(),
          ],
        ),
      ),
    );
  }

  Future<void> _openNewTicket(BuildContext context, WidgetRef ref) async {
    final draft = await showModalBottomSheet<_SupportDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewTicketSheet(),
    );
    if (draft == null || !context.mounted) return;
    try {
      final id = await ref
          .read(repositoryProvider)
          .createSupportTicket(subject: draft.subject, message: draft.message);
      ref.invalidate(supportTicketsProvider);
      if (!context.mounted) return;
      context.push('/support/$id');
    } catch (error) {
      if (context.mounted) showAppErrorSnackBar(context, error);
    }
  }
}

class SupportTicketDetailScreen extends ConsumerStatefulWidget {
  const SupportTicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<SupportTicketDetailScreen> createState() =>
      _SupportTicketDetailScreenState();
}

class _SupportTicketDetailScreenState
    extends ConsumerState<SupportTicketDetailScreen> {
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _message.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(repositoryProvider)
          .sendSupportMessage(ticketId: widget.ticketId, message: body);
      _message.clear();
      ref.invalidate(supportMessagesProvider(widget.ticketId));
      ref.invalidate(supportTicketsProvider);
    } catch (error) {
      if (mounted) showAppErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(supportTicketsProvider);
    final messages = ref.watch(supportMessagesProvider(widget.ticketId));
    SupportTicketModel? ticket;
    for (final item in tickets.asData?.value ?? const <SupportTicketModel>[]) {
      if (item.id == widget.ticketId) {
        ticket = item;
        break;
      }
    }

    return Scaffold(
      body: ResponsiveListView(
        maxWidth: 760,
        children: [
          Row(
            children: [
              IconButton.outlined(
                tooltip: 'К обращениям',
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ticket?.subject ?? 'Обращение в поддержку',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton.outlined(
                tooltip: 'Обновить',
                onPressed: () =>
                    ref.invalidate(supportMessagesProvider(widget.ticketId)),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (ticket != null) _TicketSummary(ticket: ticket),
          if (ticket != null) const SizedBox(height: 14),
          messages.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => ErrorPane(error: error),
            data: (items) => SmetchikCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final message in items) ...[
                    _MessageBubble(message: message),
                    if (message != items.last) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (ticket?.status == SupportTicketStatus.resolved)
            const _ResolvedTicketNote()
          else
            _MessageComposer(
              controller: _message,
              busy: _sending,
              onSend: _send,
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onTap});

  final SupportTicketModel ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _ticketStatusBackground(ticket.status),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _ticketStatusIcon(ticket.status),
              color: _ticketStatusColor(ticket.status),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.subject,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if ((ticket.lastMessagePreview ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    ticket.lastMessagePreview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StatusPill(status: ticket.status),
                    const Spacer(),
                    Text(
                      formatDateTime(ticket.lastMessageAt ?? ticket.updatedAt),
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: AppColors.textHint),
        ],
      ),
    );
  }
}

class _TicketSummary extends StatelessWidget {
  const _TicketSummary({required this.ticket});

  final SupportTicketModel ticket;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Row(
        children: [
          const Icon(Icons.support_agent_rounded, color: AppColors.orangeDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Создано ${formatDateTime(ticket.createdAt)}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          _StatusPill(status: ticket.status),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final SupportMessageModel message;

  @override
  Widget build(BuildContext context) {
    final support = message.isFromSupport;
    return Align(
      alignment: support ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: support ? AppColors.background : AppColors.graphite,
            borderRadius: BorderRadius.circular(16),
            border: support ? Border.all(color: AppColors.border) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  support ? 'Поддержка' : 'Вы',
                  style: TextStyle(
                    color: support
                        ? AppColors.orangeDark
                        : const Color(0xFFFFC58E),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message.body,
                  style: TextStyle(
                    color: support ? AppColors.graphite : Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatDateTime(message.createdAt),
                  style: TextStyle(
                    color: support ? AppColors.textHint : Colors.white70,
                    fontSize: 10,
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

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Сообщение',
              hintText: 'Опишите вопрос или уточните детали',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: busy ? null : onSend,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_outlined),
            label: const Text('Отправить сообщение'),
          ),
        ],
      ),
    );
  }
}

class _NewTicketSheet extends StatefulWidget {
  const _NewTicketSheet();

  @override
  State<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends State<_NewTicketSheet> {
  final _subject = TextEditingController();
  final _message = TextEditingController();

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  void _submit() {
    if (_subject.text.trim().length < 3 || _message.text.trim().isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      _SupportDraft(
        subject: _subject.text.trim(),
        message: _message.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: const BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.orangeLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.support_agent_rounded,
                          color: AppColors.orangeDark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Новое обращение',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _subject,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Тема',
                      hintText: 'Например: не получается отправить смету',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _message,
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Опишите вопрос',
                      hintText: 'Что произошло и что вы ожидали увидеть?',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Отправить в поддержку'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportHint extends StatelessWidget {
  const _SupportHint();

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, color: AppColors.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Не отправляйте пароли, коды из сообщений и данные банковских карт. Для разбора ошибки достаточно описать, что произошло.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolvedTicketNote extends StatelessWidget {
  const _ResolvedTicketNote();

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: AppColors.success),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Обращение закрыто. Создайте новое, если вопрос появился снова.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _ticketStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _ticketStatusBackground(status),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        SupportTicketStatus.label(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

IconData _ticketStatusIcon(String status) {
  return switch (SupportTicketStatus.normalize(status)) {
    SupportTicketStatus.inProgress => Icons.manage_search_outlined,
    SupportTicketStatus.waitingUser => Icons.mark_email_unread_outlined,
    SupportTicketStatus.resolved => Icons.check_circle_outline,
    _ => Icons.chat_bubble_outline,
  };
}

Color _ticketStatusColor(String status) {
  return switch (SupportTicketStatus.normalize(status)) {
    SupportTicketStatus.inProgress => AppColors.info,
    SupportTicketStatus.waitingUser => AppColors.orangeDark,
    SupportTicketStatus.resolved => AppColors.success,
    _ => AppColors.orangeDark,
  };
}

Color _ticketStatusBackground(String status) {
  return switch (SupportTicketStatus.normalize(status)) {
    SupportTicketStatus.inProgress => AppColors.infoBg,
    SupportTicketStatus.waitingUser => AppColors.orangeLight,
    SupportTicketStatus.resolved => AppColors.successBg,
    _ => AppColors.orangeLight,
  };
}

class _SupportDraft {
  const _SupportDraft({required this.subject, required this.message});

  final String subject;
  final String message;
}
