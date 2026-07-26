import 'package:flutter/material.dart';

import 'app_theme.dart';

class AppErrorInfo {
  const AppErrorInfo({
    required this.title,
    required this.message,
    this.actionLabel,
  });

  final String title;
  final String message;
  final String? actionLabel;
}

/// Converts transport, database and authentication exceptions into language
/// that is useful to a master at an object and does not expose internals.
AppErrorInfo describeAppError(Object error) {
  final raw = error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('AuthException(message: ', '')
      .replaceFirst('FunctionException(', '')
      .replaceAll(RegExp(r'\)$'), '')
      .trim();
  final value = raw.toLowerCase();

  if (value.contains('user is banned') || value.contains('banned_until')) {
    return AppErrorInfo(
      title: 'Доступ к аккаунту ограничен',
      message:
          'Вход временно недоступен. Если это произошло по ошибке, обратитесь в поддержку.',
      actionLabel: 'Поддержка',
    );
  }
  if (value.contains('jwt') ||
      value.contains('refresh token') ||
      value.contains('session') ||
      value.contains('сессия не подтверждена')) {
    return const AppErrorInfo(
      title: 'Сессия завершилась',
      message: 'Войдите в аккаунт ещё раз, чтобы продолжить работу.',
      actionLabel: 'Войти',
    );
  }
  if (value.contains('network') ||
      value.contains('socket') ||
      value.contains('failed host lookup') ||
      value.contains('clientexception') ||
      value.contains('connection')) {
    return const AppErrorInfo(
      title: 'Нет подключения к интернету',
      message:
          'Проверьте сеть и повторите попытку. Черновики останутся на устройстве.',
      actionLabel: 'Повторить',
    );
  }
  if (value.contains('timeout') || value.contains('timed out')) {
    return const AppErrorInfo(
      title: 'Сервис отвечает слишком долго',
      message: 'Подождите немного и повторите действие.',
      actionLabel: 'Повторить',
    );
  }
  if (value.contains('permission denied') ||
      value.contains('row-level') ||
      value.contains('not authorized') ||
      value.contains('forbidden')) {
    return const AppErrorInfo(
      title: 'Недостаточно прав',
      message: 'У этого аккаунта нет доступа к нужным данным или действию.',
      actionLabel: 'Поддержка',
    );
  }
  if (value.contains('already exists') ||
      value.contains('duplicate') ||
      value.contains('unique constraint')) {
    return const AppErrorInfo(
      title: 'Такие данные уже есть',
      message: 'Проверьте введённые данные и попробуйте ещё раз.',
    );
  }
  if (value.contains('not found') || value.contains('не найден')) {
    return const AppErrorInfo(
      title: 'Данные не найдены',
      message: 'Возможно, запись была удалена или ссылка больше не действует.',
      actionLabel: 'Поддержка',
    );
  }
  if (value.contains('лимит') || value.contains('тариф')) {
    return AppErrorInfo(
      title: 'Достигнут лимит тарифа',
      message: _cleanMessage(raw),
      actionLabel: 'Тарифы',
    );
  }
  if (_containsRussian(raw)) {
    return AppErrorInfo(
      title: 'Не удалось выполнить действие',
      message: _cleanMessage(raw),
      actionLabel: 'Поддержка',
    );
  }
  return const AppErrorInfo(
    title: 'Что-то пошло не так',
    message:
        'Не удалось выполнить действие. Повторите попытку или напишите в поддержку.',
    actionLabel: 'Поддержка',
  );
}

String appErrorMessage(Object error) {
  final info = describeAppError(error);
  return '${info.title}. ${info.message}';
}

void showAppErrorSnackBar(
  BuildContext context,
  Object error, {
  VoidCallback? onAction,
}) {
  final info = describeAppError(error);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: AppColors.graphite,
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFFC58E)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(info.message),
                ],
              ),
            ),
          ],
        ),
        action: onAction == null || info.actionLabel == null
            ? null
            : SnackBarAction(label: info.actionLabel!, onPressed: onAction),
      ),
    );
}

bool _containsRussian(String value) => RegExp(r'[А-Яа-яЁё]').hasMatch(value);

String _cleanMessage(String value) {
  final normalized = value
      .replaceAll(
        RegExp(r'^(PostgrestException|AuthRetryableFetchException)\([^:]*:\s*'),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return normalized.length > 220
      ? '${normalized.substring(0, 217).trimRight()}...'
      : normalized;
}
