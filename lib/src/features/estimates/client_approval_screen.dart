import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../data/models.dart';
import '../../data/signing.dart';
import '../../shared/russian_phone_input_formatter.dart';
import '../../shared/ui.dart';

class ClientApprovalScreen extends StatefulWidget {
  const ClientApprovalScreen({super.key, required this.token});

  final String token;

  @override
  State<ClientApprovalScreen> createState() => _ClientApprovalScreenState();
}

class _ClientApprovalScreenState extends State<ClientApprovalScreen> {
  late Future<_PublicApproval> _approvalFuture;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _signatureKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  final ValueNotifier<int> _signatureRevision = ValueNotifier(0);
  bool _consentAccepted = false;
  bool _saving = false;
  bool _prefilled = false;
  String? _error;
  DateTime? _signedAt;

  @override
  void initState() {
    super.initState();
    _approvalFuture = _loadApproval();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _signatureRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<_PublicApproval>(
          future: _approvalFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingPane();
            }
            if (snapshot.hasError) {
              return _UnavailableApproval(
                message: _readableError(snapshot.error),
                onRetry: _reload,
              );
            }
            final approval = snapshot.requireData;
            if (approval.isSigned || _signedAt != null) {
              return _SignedApproval(signedAt: _signedAt ?? approval.signedAt);
            }
            _prefill(approval);
            return _ApprovalForm(
              approval: approval,
              nameController: _name,
              phoneController: _phone,
              signatureKey: _signatureKey,
              strokes: _strokes,
              signatureRevision: _signatureRevision,
              consentAccepted: _consentAccepted,
              saving: _saving,
              error: _error,
              onConsentChanged: (value) =>
                  setState(() => _consentAccepted = value),
              onOpenAgreement: () => context.push('/legal/signature'),
              onStartStroke: _startStroke,
              onAppendStroke: _appendStroke,
              onClear: _strokes.isEmpty ? null : _clearSignature,
              onSign: () => _sign(approval),
            );
          },
        ),
      ),
    );
  }

  Future<_PublicApproval> _loadApproval() async {
    final response = await Supabase.instance.client.functions.invoke(
      'estimate-approval',
      body: {'action': 'get', 'token': widget.token},
    );
    final data = _asMap(response.data);
    return _PublicApproval.fromMap(data);
  }

  void _reload() {
    setState(() {
      _error = null;
      _approvalFuture = _loadApproval();
    });
  }

  void _prefill(_PublicApproval approval) {
    if (_prefilled) return;
    _prefilled = true;
    _name.text = approval.clientName;
    _phone.text = approval.clientPhone;
  }

  void _startStroke(Offset point) {
    if (!_consentAccepted || _saving) return;
    setState(() => _strokes.add([point]));
  }

  void _appendStroke(Offset point) {
    if (_strokes.isEmpty || !_consentAccepted || _saving) return;
    _strokes.last.add(point);
    _signatureRevision.value++;
  }

  void _clearSignature() {
    setState(() => _strokes.clear());
    _signatureRevision.value++;
  }

  bool get _hasSignature => _strokes.any((stroke) => stroke.length > 1);

  Future<void> _sign(_PublicApproval approval) async {
    if (!_consentAccepted) {
      setState(() => _error = 'Подтвердите, что вы ознакомились со сметой.');
      return;
    }
    if (!_hasSignature) {
      setState(() => _error = 'Поставьте подпись в поле выше.');
      return;
    }
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Укажите ФИО клиента.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bytes = await _renderSignature();
      final response = await Supabase.instance.client.functions.invoke(
        'estimate-approval',
        body: {
          'action': 'sign',
          'token': widget.token,
          'clientName': _name.text.trim(),
          'clientPhone': _phone.text.trim(),
          'signature': base64Encode(bytes),
          'statementVersion': approval.statementVersion,
        },
      );
      final data = _asMap(response.data);
      if (data['state'] != 'signed') {
        throw const AuthException('Сервис не подтвердил принятие сметы.');
      }
      if (!mounted) return;
      setState(() => _signedAt = _asDate(data['signedAt']) ?? DateTime.now());
    } catch (error) {
      if (mounted) setState(() => _error = _readableError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Uint8List> _renderSignature() async {
    final box = _signatureKey.currentContext?.findRenderObject() as RenderBox?;
    final sourceSize = box?.size ?? const Size(640, 240);
    const targetSize = Size(840, 320);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(
        targetSize.width / sourceSize.width,
        targetSize.height / sourceSize.height,
      );
    _SignaturePainter(strokes: _strokes).paint(canvas, sourceSize);
    final image = await recorder.endRecording().toImage(
      targetSize.width.round(),
      targetSize.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}

class _ApprovalForm extends StatelessWidget {
  const _ApprovalForm({
    required this.approval,
    required this.nameController,
    required this.phoneController,
    required this.signatureKey,
    required this.strokes,
    required this.signatureRevision,
    required this.consentAccepted,
    required this.saving,
    required this.error,
    required this.onConsentChanged,
    required this.onOpenAgreement,
    required this.onStartStroke,
    required this.onAppendStroke,
    required this.onClear,
    required this.onSign,
  });

  final _PublicApproval approval;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final GlobalKey signatureKey;
  final List<List<Offset>> strokes;
  final Listenable signatureRevision;
  final bool consentAccepted;
  final bool saving;
  final String? error;
  final ValueChanged<bool> onConsentChanged;
  final VoidCallback onOpenAgreement;
  final ValueChanged<Offset> onStartStroke;
  final ValueChanged<Offset> onAppendStroke;
  final VoidCallback? onClear;
  final VoidCallback onSign;

  @override
  Widget build(BuildContext context) {
    return ResponsiveListView(
      maxWidth: 720,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.fact_check_outlined,
                color: AppColors.orange,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Подтверждение сметы',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${approval.masterName}${approval.masterSpecialization == null ? '' : ' · ${approval.masterSpecialization}'}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        SmetchikCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      approval.objectTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _VersionChip(version: approval.documentVersion),
                ],
              ),
              if (approval.objectAddress.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  approval.objectAddress,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 14),
              for (final line in approval.lines) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${formatQuantity(line.quantity)} ${line.unit} × ${formatMoney(line.unitPrice)}',
                              style: const TextStyle(
                                color: AppColors.textHint,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(line.total),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const Divider(height: 18),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.graphite,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Итого',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(approval.totalAmount),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Данные клиента'),
        const SizedBox(height: 8),
        TextField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          enabled: !saving,
          decoration: const InputDecoration(
            labelText: 'ФИО клиента',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: phoneController,
          enabled: !saving,
          keyboardType: TextInputType.phone,
          inputFormatters: [RussianPhoneInputFormatter()],
          decoration: InputDecoration(
            labelText: 'Телефон',
            hintText: approval.maskedPhone,
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            approval.statement,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
        ),
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: consentAccepted,
            onChanged: saving
                ? null
                : (value) => onConsentChanged(value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Принимаю ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                TextButton(
                  onPressed: onOpenAgreement,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.orangeDark,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'условия электронной подписи',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          consentAccepted
              ? 'Распишитесь в поле ниже'
              : 'Подтвердите согласие, чтобы поставить подпись',
          style: TextStyle(
            color: consentAccepted
                ? AppColors.textSecondary
                : AppColors.textHint,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: consentAccepted ? AppColors.orange : AppColors.border,
              width: consentAccepted ? 1.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 2.55,
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: consentAccepted && !saving
                    ? <Type, GestureRecognizerFactory>{
                        _SignatureStrokeRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              _SignatureStrokeRecognizer
                            >(_SignatureStrokeRecognizer.new, (recognizer) {
                              recognizer.onStart = onStartStroke;
                              recognizer.onUpdate = onAppendStroke;
                            }),
                      }
                    : const <Type, GestureRecognizerFactory>{},
                child: RepaintBoundary(
                  child: CustomPaint(
                    key: signatureKey,
                    painter: _SignaturePainter(
                      strokes: strokes,
                      repaint: signatureRevision,
                    ),
                    child: strokes.any((stroke) => stroke.length > 1)
                        ? const SizedBox.expand()
                        : Center(
                            child: Text(
                              consentAccepted
                                  ? 'Поставьте подпись'
                                  : 'Подпись станет доступна после согласия',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textHint,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: saving ? null : onClear,
          icon: const Icon(Icons.refresh),
          label: const Text('Очистить подпись'),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          _InlineError(message: error!),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: saving ? null : onSign,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.verified_outlined),
          label: Text(saving ? 'Фиксируем подпись...' : 'Принять смету'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Claims the pointer as soon as it touches the signature field, so a
/// vertical handwriting stroke cannot be interpreted as page scrolling.
class _SignatureStrokeRecognizer extends OneSequenceGestureRecognizer {
  ValueChanged<Offset>? onStart;
  ValueChanged<Offset>? onUpdate;
  int? _activePointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_activePointer != null) return;
    super.addAllowedPointer(event);
    _activePointer = event.pointer;
    resolve(GestureDisposition.accepted);
    onStart?.call(event.localPosition);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    if (event is PointerMoveEvent) {
      onUpdate?.call(event.localPosition);
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
      _activePointer = null;
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _activePointer = null;
  }

  @override
  String get debugDescription => 'signature stroke';
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.version});

  final int version;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.orangeLight,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'Версия $version',
        style: const TextStyle(
          color: AppColors.orangeDark,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SignedApproval extends StatelessWidget {
  const _SignedApproval({this.signedAt});

  final DateTime? signedAt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: AppColors.success,
                size: 42,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Смета принята',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              signedAt == null
                  ? 'Подпись уже зафиксирована в документе.'
                  : 'Подпись зафиксирована ${formatDateTime(signedAt!)}. Мастер получит финальный PDF.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnavailableApproval extends StatelessWidget {
  const _UnavailableApproval({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.link_off_outlined,
                color: AppColors.orange,
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Ссылка недоступна',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({required this.strokes, super.repaint});

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.graphite
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}

class _PublicApproval {
  const _PublicApproval({
    required this.isSigned,
    this.signedAt,
    this.expiresAt,
    this.statement = clientApprovalLinkStatement,
    this.statementVersion = clientApprovalLinkStatementVersion,
    this.objectTitle = '',
    this.objectAddress = '',
    this.documentVersion = 1,
    this.totalAmount = 0,
    this.clientName = '',
    this.clientPhone = '',
    this.maskedPhone = 'номер клиента',
    this.masterName = 'Мастер',
    this.masterSpecialization,
    this.lines = const [],
  });

  final bool isSigned;
  final DateTime? signedAt;
  final DateTime? expiresAt;
  final String statement;
  final String statementVersion;
  final String objectTitle;
  final String objectAddress;
  final int documentVersion;
  final double totalAmount;
  final String clientName;
  final String clientPhone;
  final String maskedPhone;
  final String masterName;
  final String? masterSpecialization;
  final List<_PublicApprovalLine> lines;

  factory _PublicApproval.fromMap(Map<String, dynamic> map) {
    final state = map['state'] as String?;
    if (state == 'signed') {
      return _PublicApproval(
        isSigned: true,
        signedAt: _asDate(map['signedAt']),
      );
    }
    final document = _asMap(map['document']);
    final client = _asMap(document['client']);
    final master = _asMap(document['master']);
    final rows = document['lines'] is List
        ? document['lines'] as List
        : const [];
    return _PublicApproval(
      isSigned: false,
      expiresAt: _asDate(map['expiresAt']),
      statement: (map['statement'] as String?) ?? clientApprovalLinkStatement,
      statementVersion:
          (map['statementVersion'] as String?) ??
          clientApprovalLinkStatementVersion,
      objectTitle: (document['object_title'] as String?) ?? '',
      objectAddress: (client['object_address'] as String?) ?? '',
      documentVersion: asIntOrNull(document['version']) ?? 1,
      totalAmount: asDouble(document['total_amount']),
      clientName: (client['name'] as String?) ?? '',
      clientPhone: (client['phone'] as String?) ?? '',
      maskedPhone: (client['phone_masked'] as String?) ?? 'номер клиента',
      masterName: (master['full_name'] as String?) ?? 'Мастер',
      masterSpecialization: master['specialization'] as String?,
      lines: rows
          .map((row) => _PublicApprovalLine.fromMap(_asMap(row)))
          .toList(),
    );
  }
}

class _PublicApprovalLine {
  const _PublicApprovalLine({
    required this.title,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  final String title;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double total;

  factory _PublicApprovalLine.fromMap(Map<String, dynamic> map) {
    return _PublicApprovalLine(
      title: (map['title'] as String?) ?? '',
      unit: (map['unit'] as String?) ?? 'шт',
      quantity: asDouble(map['quantity']),
      unitPrice: asDouble(map['unit_price']),
      total: asDouble(map['line_total']),
    );
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

DateTime? _asDate(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}

String _readableError(Object? error) {
  final raw = error?.toString() ?? '';
  if (raw.contains('Срок действия ссылки')) {
    return 'Срок действия ссылки закончился. Попросите мастера создать новую.';
  }
  if (raw.contains('уже принята')) return 'Эта смета уже была принята.';
  if (raw.contains('недоступна')) return 'Эта ссылка больше недоступна.';
  return 'Не удалось открыть смету. Проверьте интернет или попросите мастера создать новую ссылку.';
}
