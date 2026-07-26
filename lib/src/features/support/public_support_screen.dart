import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_error.dart';
import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../shared/ui.dart';

/// A public support thread used when the person cannot sign in, for example
/// after an account block. Access is limited to an unguessable link token.
class PublicSupportScreen extends StatefulWidget {
  const PublicSupportScreen({super.key, this.token, this.created = false});

  final String? token;
  final bool created;

  @override
  State<PublicSupportScreen> createState() => _PublicSupportScreenState();
}

class _PublicSupportScreenState extends State<PublicSupportScreen> {
  final _email = TextEditingController();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  Map<String, dynamic>? _ticket;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  bool _sending = false;
  String? _error;

  bool get _isThread => widget.token != null;

  @override
  void initState() {
    super.initState();
    if (_isThread) _loadThread();
  }

  @override
  void dispose() {
    _email.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _loadThread() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _call('thread', {'token': widget.token});
      if (!mounted) return;
      setState(() {
        _ticket = _asMap(data['ticket']);
        _messages = _asMaps(data['messages']);
      });
    } catch (error) {
      if (mounted) setState(() => _error = appErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createTicket() async {
    if (_sending) return;
    final email = _email.text.trim();
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Введите email, на который можно ответить.');
      return;
    }
    if (subject.length < 3) {
      setState(() => _error = 'Коротко укажите тему обращения.');
      return;
    }
    if (message.isEmpty) {
      setState(() => _error = 'Опишите, что произошло.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final data = await _call('create', {
        'email': email,
        'subject': subject,
        'message': message,
      });
      final token = data['token'] as String?;
      if (!mounted || token == null || token.isEmpty) return;
      context.go('/help/$token?created=1');
    } catch (error) {
      if (mounted) setState(() => _error = appErrorMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reply() async {
    final message = _message.text.trim();
    if (message.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _call('reply', {'token': widget.token, 'message': message});
      _message.clear();
      await _loadThread();
    } catch (error) {
      if (mounted) setState(() => _error = appErrorMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<Map<String, dynamic>> _call(
    String action,
    Map<String, dynamic> body,
  ) async {
    final response = await Supabase.instance.client.functions.invoke(
      'public-support',
      body: {'action': action, ...body},
    );
    return _asMap(response.data);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _ticket?['status'] == SupportTicketStatus.resolved;
    return Scaffold(
      body: ResponsiveListView(
        maxWidth: 720,
        children: [
          Row(
            children: [
              IconButton.outlined(
                tooltip: 'Ко входу',
                onPressed: () => context.go('/auth'),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Поддержка Сметчика',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
              if (_isThread)
                IconButton.outlined(
                  tooltip: 'Обновить переписку',
                  onPressed: _loading ? null : _loadThread,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_isThread)
            _PublicSupportForm(
              email: _email,
              subject: _subject,
              message: _message,
              busy: _sending,
              error: _error,
              onSubmit: _createTicket,
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.all(42),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            EmptyState(
              icon: Icons.error_outline,
              title: 'Не удалось открыть обращение',
              body: _error!,
              action: OutlinedButton.icon(
                onPressed: _loadThread,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            )
          else ...[
            _PublicThreadHeader(ticket: _ticket ?? const {}),
            const SizedBox(height: 14),
            if (widget.created) ...[
              _PublicDeliveryNote(onCopy: _copyThreadLink),
              const SizedBox(height: 14),
            ],
            SmetchikCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final message in _messages) ...[
                    _PublicMessageBubble(message: message),
                    if (message != _messages.last) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (resolved)
              const _PublicResolvedNote()
            else
              _PublicReplyComposer(
                controller: _message,
                busy: _sending,
                onSend: _reply,
              ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _copyThreadLink() async {
    await Clipboard.setData(ClipboardData(text: Uri.base.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка на обращение скопирована')),
    );
  }
}

class _PublicSupportForm extends StatelessWidget {
  const _PublicSupportForm({
    required this.email,
    required this.subject,
    required this.message,
    required this.busy,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController email;
  final TextEditingController subject;
  final TextEditingController message;
  final bool busy;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PublicSupportIntro(),
          const SizedBox(height: 16),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email для ответа',
              prefixIcon: Icon(Icons.alternate_email),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: subject,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Тема',
              hintText: 'Например, не могу войти в аккаунт',
              prefixIcon: Icon(Icons.subject_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: message,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Сообщение',
              hintText: 'Опишите, что произошло',
              alignLabelWithHint: true,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            _PublicError(text: error!),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy ? null : onSubmit,
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
            label: const Text('Отправить обращение'),
          ),
        ],
      ),
    );
  }
}

class _PublicSupportIntro extends StatelessWidget {
  const _PublicSupportIntro();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Не можете войти?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 3),
              Text(
                'Напишите нам без входа. После отправки откроется личная ссылка на переписку.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PublicThreadHeader extends StatelessWidget {
  const _PublicThreadHeader({required this.ticket});

  final Map<String, dynamic> ticket;

  @override
  Widget build(BuildContext context) {
    final status = ticket['status'] as String? ?? SupportTicketStatus.open;
    return SmetchikCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _publicStatusBackground(status),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _publicStatusIcon(status),
              color: _publicStatusColor(status),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket['subject'] as String? ?? 'Обращение',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  _publicStatusLabel(status),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicMessageBubble extends StatelessWidget {
  const _PublicMessageBubble({required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final fromSupport = message['author_role'] == 'support';
    final created = DateTime.tryParse(
      message['created_at']?.toString() ?? '',
    )?.toLocal();
    return Align(
      alignment: fromSupport ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fromSupport ? AppColors.background : AppColors.graphite,
            borderRadius: BorderRadius.circular(16),
            border: fromSupport ? Border.all(color: AppColors.border) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fromSupport ? 'Поддержка' : 'Вы',
                  style: TextStyle(
                    color: fromSupport
                        ? AppColors.orangeDark
                        : const Color(0xFFFFC58E),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message['body'] as String? ?? '',
                  style: TextStyle(
                    color: fromSupport ? AppColors.graphite : Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  created == null ? '—' : formatDateTime(created),
                  style: TextStyle(
                    color: fromSupport ? AppColors.textHint : Colors.white70,
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

class _PublicReplyComposer extends StatelessWidget {
  const _PublicReplyComposer({
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

class _PublicResolvedNote extends StatelessWidget {
  const _PublicResolvedNote();

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

class _PublicDeliveryNote extends StatelessWidget {
  const _PublicDeliveryNote({required this.onCopy});

  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orangeLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.link_outlined, color: AppColors.orangeDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Сохраните ссылку на эту переписку. По ней можно вернуться к обращению без входа.',
              style: const TextStyle(color: AppColors.orangeDark, height: 1.3),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Скопировать ссылку',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined, color: AppColors.orangeDark),
          ),
        ],
      ),
    );
  }
}

class _PublicError extends StatelessWidget {
  const _PublicError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _asMaps(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map(_asMap).toList();
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

String _publicStatusLabel(String value) => switch (value) {
  SupportTicketStatus.inProgress => 'Поддержка разбирается с вопросом',
  SupportTicketStatus.waitingUser => 'Нужен ваш ответ',
  SupportTicketStatus.resolved => 'Обращение закрыто',
  _ => 'Обращение получено',
};

Color _publicStatusColor(String value) => switch (value) {
  SupportTicketStatus.inProgress => AppColors.info,
  SupportTicketStatus.waitingUser => AppColors.orangeDark,
  SupportTicketStatus.resolved => AppColors.success,
  _ => AppColors.orangeDark,
};

Color _publicStatusBackground(String value) => switch (value) {
  SupportTicketStatus.inProgress => AppColors.infoBg,
  SupportTicketStatus.waitingUser => AppColors.orangeLight,
  SupportTicketStatus.resolved => AppColors.successBg,
  _ => AppColors.orangeLight,
};

IconData _publicStatusIcon(String value) => switch (value) {
  SupportTicketStatus.inProgress => Icons.pending_actions_outlined,
  SupportTicketStatus.waitingUser => Icons.mark_email_unread_outlined,
  SupportTicketStatus.resolved => Icons.task_alt_outlined,
  _ => Icons.support_agent_outlined,
};
