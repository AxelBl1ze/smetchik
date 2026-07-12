import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../data/models.dart';
import '../../data/pdf_templates.dart';
import '../../data/repository.dart';
import '../../shared/russian_phone_input_formatter.dart';
import '../../shared/specialization_field.dart';
import '../../shared/ui.dart';
import '../../shared/upgrade_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _spec = TextEditingController();
  final _pdfPaymentTerms = TextEditingController();
  final _pdfFooterNote = TextEditingController();
  final _paymentQrLabel = TextEditingController();
  final _contactQrLabel = TextEditingController();
  final _nameFocus = FocusNode();
  String _pdfTemplate = PdfTemplate.brightAccent;
  String _pdfAccentColor = PdfAccentColor.orange;
  bool _pdfShowBrandHeader = true;
  bool _pdfShowSignatures = true;
  bool _pdfShowServiceMark = true;
  bool _hydrated = false;
  bool _saving = false;
  bool _editingName = false;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && _editingName && mounted) {
        setState(() => _editingName = false);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _spec.dispose();
    _pdfPaymentTerms.dispose();
    _pdfFooterNote.dispose();
    _paymentQrLabel.dispose();
    _contactQrLabel.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final estimates = ref.watch(estimatesProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;
    profile.whenData((value) {
      if (!_hydrated && value != null) {
        _hydrate(value);
      }
    });

    return Scaffold(
      appBar: isDesktop ? null : AppBar(title: null),
      body: profile.when(
        data: (value) => ResponsiveListView(
          maxWidth: 720,
          children: [
            SmetchikCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = _isNarrowLayout(constraints, 430);
                      final avatar = _AvatarButton(
                        initials: value?.initials ?? 'СМ',
                        imageUrl: ref
                            .read(repositoryProvider)
                            .logoPublicUrl(value?.logoPath),
                        busy: _saving,
                        onTap: _showAvatarSheet,
                      );
                      final name = _ProfileNameField(
                        controller: _name,
                        focusNode: _nameFocus,
                        editing: _editingName,
                        onEdit: _startNameEditing,
                        onSubmitted: _finishNameEditing,
                      );
                      final tariff = _TariffBadge(
                        plan:
                            value?.effectiveSubscriptionPlan ??
                            SubscriptionPlan.basic,
                        onTap: () => _showTariffSheet(value),
                      );

                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                avatar,
                                const SizedBox(width: 12),
                                Expanded(child: name),
                              ],
                            ),
                            const SizedBox(height: 12),
                            tariff,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          avatar,
                          const SizedBox(width: 12),
                          Expanded(child: name),
                          const SizedBox(width: 10),
                          tariff,
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SmetchikCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _CardTitle(
                    icon: Icons.badge_outlined,
                    title: 'Информация мастера',
                    subtitle: 'Телефон и специализация',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: const [RussianPhoneInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Телефон',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SpecializationField(controller: _spec),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SignatureSettingsCard(
              signatureUrl:
                  value?.signatureUrl ??
                  ref
                      .read(repositoryProvider)
                      .signaturePublicUrl(value?.signaturePath),
              busy: _saving,
              onTap: _showSignatureSheet,
            ),
            const SizedBox(height: 14),
            _QrSettingsCard(
              paymentQrUrl:
                  value?.paymentQrUrl ??
                  ref
                      .read(repositoryProvider)
                      .qrPublicUrl(value?.paymentQrPath),
              contactQrUrl:
                  value?.contactQrUrl ??
                  ref
                      .read(repositoryProvider)
                      .qrPublicUrl(value?.contactQrPath),
              paymentLabel: _paymentQrLabel,
              contactLabel: _contactQrLabel,
              busy: _saving,
              onPickPayment: () => _pickProfileQr(_ProfileQrKind.payment),
              onPickContact: () => _pickProfileQr(_ProfileQrKind.contact),
            ),
            const SizedBox(height: 14),
            estimates.when(
              data: (items) =>
                  SmetchikCard(child: _ProfileStats(estimates: items)),
              loading: () => const SmetchikCard(child: _ProfileStatsSkeleton()),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 14),
            estimates.when(
              data: (items) => _AdvancedStatsLauncherCard(
                profile: value,
                estimates: items,
                onOpen: () => _showAdvancedStatsSheet(value, items),
                onUpgrade: () => _showTariffSheet(value),
              ),
              loading: () => const _AdvancedStatsSkeleton(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 14),
            estimates.when(
              data: (items) => _SubscriptionCard(
                profile: value,
                estimates: items,
                busy: _saving,
                onTap: () => _showTariffSheet(value),
              ),
              loading: () => _SubscriptionCard(
                profile: value,
                estimates: const [],
                busy: true,
                onTap: () => _showTariffSheet(value),
              ),
              error: (_, _) => _SubscriptionCard(
                profile: value,
                estimates: const [],
                busy: _saving,
                onTap: () => _showTariffSheet(value),
              ),
            ),
            const SizedBox(height: 14),
            _SubscriptionTestPanel(
              profile: value,
              busy: _saving,
              onActivate: () => _activateMockPro(days: 30),
              onExtend: () => _activateMockPro(
                days: 30,
                message: 'Профи продлён тестово на 30 дней',
              ),
              onExpire: _expireMockSubscription,
              onBasic: _switchToBasicPlan,
            ),
            const SizedBox(height: 14),
            _PdfSettingsLauncherCard(
              profile: value,
              template: _pdfTemplate,
              accentColor: _pdfAccentColor,
              onOpen: () => _showPdfSettingsSheet(value),
              onUpgrade: () => _showTariffSheet(value),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    !constraints.maxWidth.isFinite ||
                    constraints.maxWidth < 560;
                final saveButton = FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Сохранить'),
                );
                final logoutButton = OutlinedButton.icon(
                  onPressed: () => ref.read(authControllerProvider).signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Выйти'),
                );

                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      saveButton,
                      const SizedBox(height: 10),
                      logoutButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: saveButton),
                    const SizedBox(width: 10),
                    Expanded(child: logoutButton),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            _LegalDocumentsCard(onTap: () => context.push('/legal')),
          ],
        ),
        loading: () => const LoadingPane(),
        error: (error, _) => ErrorPane(error: error),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    if (_saving) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // The avatar is shown at 64 px in the app and as a small mark in PDF.
      // Keeping a compact source avoids expensive image decoding on phones.
      maxWidth: 640,
      imageQuality: 82,
    );
    if (picked == null) return;

    setState(() => _saving = true);
    try {
      final bytes = await picked.readAsBytes();
      final mimeType = picked.mimeType ?? _guessImageMimeType(picked.name);
      await ref
          .read(repositoryProvider)
          .uploadProfileAvatar(bytes: bytes, contentType: mimeType);
      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Аватар обновлён')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showAvatarSheet() async {
    if (_saving) return;
    final pick = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AvatarPickerSheet(),
    );
    if (pick == true) {
      await _pickAvatar();
    }
  }

  Future<void> _showSignatureSheet() async {
    if (_saving) return;
    final bytes = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => const _SignaturePadSheet(),
    );
    if (bytes == null) return;

    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).uploadProfileSignature(bytes: bytes);
      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Роспись сохранена')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickProfileQr(_ProfileQrKind kind) async {
    if (_saving) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1400,
      imageQuality: 92,
    );
    if (picked == null) return;

    setState(() => _saving = true);
    try {
      final bytes = await picked.readAsBytes();
      final mimeType = picked.mimeType ?? _guessImageMimeType(picked.name);
      await ref
          .read(repositoryProvider)
          .uploadProfileQr(
            kind: kind.storageKey,
            bytes: bytes,
            contentType: mimeType,
          );
      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kind == _ProfileQrKind.payment
                ? 'QR оплаты обновлён'
                : 'QR для связи обновлён',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showAdvancedStatsSheet(
    ProfileModel? profile,
    List<EstimateModel> estimates,
  ) async {
    if (profile?.hasActivePro != true) {
      await _showTariffSheet(profile);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SettingsFeatureSheet(
        maxWidth: 760,
        onClose: () => Navigator.of(sheetContext).pop(),
        child: _AdvancedStatsCard(
          profile: profile,
          estimates: estimates,
          onUpgrade: () {
            Navigator.of(sheetContext).pop();
            _showTariffSheet(profile);
          },
        ),
      ),
    );
  }

  Future<void> _showPdfSettingsSheet(ProfileModel? profile) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          void update(VoidCallback change) {
            setState(change);
            setSheetState(() {});
          }

          return _SettingsFeatureSheet(
            maxWidth: 820,
            onClose: () => Navigator.of(sheetContext).pop(),
            child: _PdfSettingsCard(
              profile: profile,
              busy: _saving,
              showBrandHeader: _pdfShowBrandHeader,
              showSignatures: _pdfShowSignatures,
              showServiceMark: _pdfShowServiceMark,
              template: _pdfTemplate,
              accentColor: _pdfAccentColor,
              paymentTerms: _pdfPaymentTerms,
              footerNote: _pdfFooterNote,
              onTemplateChanged: (next) => update(() => _pdfTemplate = next),
              onAccentColorChanged: (next) =>
                  update(() => _pdfAccentColor = next),
              onShowBrandHeaderChanged: (next) =>
                  update(() => _pdfShowBrandHeader = next),
              onShowSignaturesChanged: (next) =>
                  update(() => _pdfShowSignatures = next),
              onShowServiceMarkChanged: (next) =>
                  update(() => _pdfShowServiceMark = next),
              onSave: _savePdfSettings,
              onUpgrade: () {
                Navigator.of(sheetContext).pop();
                _showTariffSheet(profile);
              },
            ),
          );
        },
      ),
    );
  }

  String _guessImageMimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  void _startNameEditing() {
    setState(() => _editingName = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nameFocus.requestFocus();
      _name.selection = TextSelection.collapsed(offset: _name.text.length);
    });
  }

  void _finishNameEditing() {
    if (!_editingName) return;
    setState(() => _editingName = false);
  }

  Future<void> _showTariffSheet(ProfileModel? profile) async {
    if (_saving) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TariffSheet(
        currentPlan:
            profile?.effectiveSubscriptionPlan ?? SubscriptionPlan.basic,
        onSelect: (plan) {
          Navigator.of(sheetContext).pop();
          _changePlan(plan);
        },
      ),
    );
  }

  Future<void> _changePlan(String plan) async {
    if (SubscriptionPlan.normalize(plan) == SubscriptionPlan.pro) {
      await _showMockCheckoutSheet();
      return;
    }
    await _switchToBasicPlan();
  }

  Future<void> _showMockCheckoutSheet() async {
    if (_saving) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _MockCheckoutSheet(
        onPay: () {
          Navigator.of(sheetContext).pop();
          _activateMockPro(
            days: 30,
            message: 'Оплата прошла в тестовом режиме. Профи включён.',
          );
        },
      ),
    );
  }

  Future<void> _activateMockPro({
    required int days,
    String message = 'Профи подключён тестово на 30 дней',
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).activateMockPro(days: days);
      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _switchToBasicPlan() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).switchToBasicPlan();
      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Включён Базовый тариф')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _expireMockSubscription() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).expireMockSubscription();
      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Срок Профи истёк для теста')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _hydrate(ProfileModel profile) {
    if (!mounted || _hydrated) return;
    _hydrated = true;
    _name.text = profile.fullName;
    _phone.text = RussianPhoneInputFormatter.format(profile.phone ?? '');
    _spec.text = profile.specialization ?? '';
    _pdfTemplate = profile.pdfTemplate;
    _pdfAccentColor = profile.pdfAccentColor;
    _pdfShowBrandHeader = profile.pdfShowBrandHeader;
    _pdfShowSignatures = profile.pdfShowSignatures;
    _pdfShowServiceMark = profile.pdfShowServiceMark;
    _pdfPaymentTerms.text = profile.pdfPaymentTerms ?? '';
    _pdfFooterNote.text = profile.pdfFooterNote ?? '';
    _paymentQrLabel.text = profile.paymentQrLabel ?? 'Оплата по QR';
    _contactQrLabel.text = profile.contactQrLabel ?? 'Связаться с мастером';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .saveProfile(
            fullName: _name.text,
            phone: _phone.text,
            specialization: normalizeSpecialization(_spec.text),
            paymentQrLabel: _paymentQrLabel.text,
            contactQrLabel: _contactQrLabel.text,
            currency: 'RUB',
          );
      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Профиль сохранён')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePdfSettings() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .savePdfSettings(
            showBrandHeader: _pdfShowBrandHeader,
            showSignatures: _pdfShowSignatures,
            showServiceMark: _pdfShowServiceMark,
            template: _pdfTemplate,
            accentColor: _pdfAccentColor,
            paymentTerms: _pdfPaymentTerms.text,
            footerNote: _pdfFooterNote.text,
          );
      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Настройки PDF сохранены')));
    } catch (error) {
      if (!mounted) return;
      if (error.toString().contains('Настройки PDF доступны')) {
        showUpgradeSheet(
          context: context,
          message: error.toString().replaceFirst('Exception: ', ''),
          onOpenPlans: () =>
              _showTariffSheet(ref.read(profileProvider).asData?.value),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ProfileNameField extends StatelessWidget {
  const _ProfileNameField({
    required this.controller,
    required this.focusNode,
    required this.editing,
    required this.onEdit,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    if (editing) {
      return TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        textInputAction: TextInputAction.done,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Имя пользователя',
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        onSubmitted: (_) => onSubmitted(),
      );
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, nameValue, _) {
        final title = nameValue.text.trim().isEmpty
            ? 'Имя пользователя'
            : nameValue.text.trim();
        return Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Редактировать имя',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        );
      },
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({
    required this.initials,
    required this.imageUrl,
    required this.busy,
    required this.onTap,
  });

  final String initials;
  final String? imageUrl;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: busy ? null : onTap,
          child: CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.orangeLight,
            foregroundColor: AppColors.orangeDark,
            backgroundImage: imageUrl == null ? null : NetworkImage(imageUrl!),
            child: imageUrl == null
                ? Text(
                    initials,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  )
                : null,
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.orange,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.edit, color: Colors.white, size: 13),
          ),
        ),
      ],
    );
  }
}

class _AvatarPickerSheet extends StatelessWidget {
  const _AvatarPickerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
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
                const _CardTitle(
                  icon: Icons.account_circle_outlined,
                  title: 'Аватар мастера',
                  subtitle: 'Фото будет показываться в профиле',
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Выбрать из галереи'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Отмена'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalDocumentsCard extends StatelessWidget {
  const _LegalDocumentsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.orangeLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.gavel_outlined,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Правовая информация',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Соглашение, конфиденциальность и подписка',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignatureSettingsCard extends StatelessWidget {
  const _SignatureSettingsCard({
    required this.signatureUrl,
    required this.busy,
    required this.onTap,
  });

  final String? signatureUrl;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasSignature = signatureUrl != null && signatureUrl!.isNotEmpty;
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(
            icon: Icons.draw_outlined,
            title: 'Роспись мастера',
            subtitle: 'Автоматически добавляется в PDF-сметы',
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 86,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: hasSignature
                ? Image.network(
                    signatureUrl!,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    errorBuilder: (context, error, stackTrace) => const Align(
                      alignment: Alignment.center,
                      child: Text(
                        'Роспись не удалось показать',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                : const Align(
                    alignment: Alignment.center,
                    child: Text(
                      'Пока пусто',
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : onTap,
            icon: Icon(hasSignature ? Icons.edit_outlined : Icons.gesture),
            label: Text(hasSignature ? 'Перерисовать' : 'Добавить роспись'),
          ),
        ],
      ),
    );
  }
}

enum _ProfileQrKind {
  payment('payment'),
  contact('contact');

  const _ProfileQrKind(this.storageKey);

  final String storageKey;
}

class _QrSettingsCard extends StatelessWidget {
  const _QrSettingsCard({
    required this.paymentQrUrl,
    required this.contactQrUrl,
    required this.paymentLabel,
    required this.contactLabel,
    required this.busy,
    required this.onPickPayment,
    required this.onPickContact,
  });

  final String? paymentQrUrl;
  final String? contactQrUrl;
  final TextEditingController paymentLabel;
  final TextEditingController contactLabel;
  final bool busy;
  final VoidCallback onPickPayment;
  final VoidCallback onPickContact;

  @override
  Widget build(BuildContext context) {
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(
            icon: Icons.qr_code_2_outlined,
            title: 'Оплата и связь',
            subtitle: 'QR для оплаты или быстрого контакта в PDF',
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = _isNarrowLayout(constraints, 580);
              final payment = _QrSettingTile(
                title: 'QR оплаты',
                subtitle: 'СБП, банк, ссылка на оплату',
                imageUrl: paymentQrUrl,
                label: paymentLabel,
                buttonLabel: paymentQrUrl?.isNotEmpty == true
                    ? 'Заменить QR'
                    : 'Загрузить QR',
                busy: busy,
                onPick: onPickPayment,
              );
              final contact = _QrSettingTile(
                title: 'QR для связи',
                subtitle: 'Telegram, WhatsApp, сайт или соцсеть',
                imageUrl: contactQrUrl,
                label: contactLabel,
                buttonLabel: contactQrUrl?.isNotEmpty == true
                    ? 'Заменить QR'
                    : 'Загрузить QR',
                busy: busy,
                onPick: onPickContact,
              );

              if (compact) {
                return Column(
                  children: [payment, const SizedBox(height: 10), contact],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: payment),
                  const SizedBox(width: 10),
                  Expanded(child: contact),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QrSettingTile extends StatelessWidget {
  const _QrSettingTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.label,
    required this.buttonLabel,
    required this.busy,
    required this.onPick,
  });

  final String title;
  final String subtitle;
  final String? imageUrl;
  final TextEditingController label;
  final String buttonLabel;
  final bool busy;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _QrPreviewBox(imageUrl: imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: label,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Подпись под QR',
              hintText: 'Например: Оплата по СБП',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : onPick,
            icon: Icon(hasImage ? Icons.sync : Icons.upload_file_outlined),
            label: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _QrPreviewBox extends StatelessWidget {
  const _QrPreviewBox({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Container(
      width: 74,
      height: 74,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: hasImage
          ? Image.network(
              imageUrl!,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.qr_code_2, color: AppColors.textHint),
            )
          : const Icon(Icons.qr_code_2, color: AppColors.textHint, size: 34),
    );
  }
}

class _SignaturePadSheet extends StatefulWidget {
  const _SignaturePadSheet();

  @override
  State<_SignaturePadSheet> createState() => _SignaturePadSheetState();
}

class _SignaturePadSheetState extends State<_SignaturePadSheet> {
  final _paintKey = GlobalKey();
  final List<List<Offset>> _strokes = [];
  final ValueNotifier<int> _signatureRevision = ValueNotifier(0);

  bool get _hasSignature => _strokes.any((stroke) => stroke.length > 1);

  @override
  void dispose() {
    _signatureRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: _CardTitle(
                        icon: Icons.draw_outlined,
                        title: 'Роспись для смет',
                        subtitle: 'Распишитесь пальцем, стилусом или мышью',
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: 2.6,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) =>
                            _startStroke(details.localPosition),
                        onPanUpdate: (details) =>
                            _appendPoint(details.localPosition),
                        child: RepaintBoundary(
                          child: CustomPaint(
                            key: _paintKey,
                            painter: _SignaturePainter(
                              strokes: _strokes,
                              repaint: _signatureRevision,
                            ),
                            child: _hasSignature
                                ? const SizedBox.expand()
                                : const Center(
                                    child: Text(
                                      'место для росписи',
                                      style: TextStyle(
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _hasSignature ? _clear : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Очистить'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _hasSignature ? _save : null,
                        icon: const Icon(Icons.check),
                        label: const Text('Сохранить'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startStroke(Offset point) {
    setState(() => _strokes.add([point]));
  }

  void _appendPoint(Offset point) {
    if (_strokes.isEmpty) return;
    _strokes.last.add(point);
    _signatureRevision.value++;
  }

  void _clear() {
    setState(_strokes.clear);
    _signatureRevision.value++;
  }

  Future<void> _save() async {
    final box = _paintKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? const Size(520, 200);
    final bytes = await _renderSignature(size);
    if (!mounted) return;
    Navigator.of(context).pop(bytes);
  }

  Future<Uint8List> _renderSignature(Size sourceSize) async {
    const targetSize = Size(720, 278);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(
      targetSize.width / sourceSize.width,
      targetSize.height / sourceSize.height,
    );
    _SignaturePainter(strokes: _strokes).paint(canvas, sourceSize);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      targetSize.width.round(),
      targetSize.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
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

class _SettingsFeatureSheet extends StatelessWidget {
  const _SettingsFeatureSheet({
    required this.child,
    required this.maxWidth,
    required this.onClose,
  });

  final Widget child;
  final double maxWidth;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              margin: const EdgeInsets.all(10),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.92,
              ),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 34,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 56, 12, 12),
                      child: child,
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.transparent,
                        child: IconButton(
                          tooltip: 'Закрыть',
                          onPressed: onClose,
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdvancedStatsCard extends StatelessWidget {
  const _AdvancedStatsCard({
    required this.profile,
    required this.estimates,
    required this.onUpgrade,
  });

  final ProfileModel? profile;
  final List<EstimateModel> estimates;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final hasPro = profile?.hasActivePro == true;
    if (!hasPro) {
      return SmetchikCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle(
              icon: Icons.insights_outlined,
              title: 'Рабочая статистика',
              subtitle: 'Доступна на тарифе Профи',
            ),
            const SizedBox(height: 12),
            const Text(
              'В Pro видно, какие сметы ждут действия, сколько денег в каждом этапе и где проседает воронка.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: onUpgrade,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.workspace_premium),
                label: const Text('Оформить Профи'),
              ),
            ),
          ],
        ),
      );
    }

    final stats = _AdvancedStatsData.fromEstimates(estimates);
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.insights_outlined,
            title: 'Рабочая статистика',
            subtitle: 'Действия, деньги и воронка смет',
          ),
          const SizedBox(height: 14),
          _NextActionsPanel(stats: stats),
          const SizedBox(height: 12),
          _MoneyPipelinePanel(stats: stats),
          const SizedBox(height: 12),
          _EstimateFunnelPanel(stats: stats),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => _StatsInsightRow(
              compact: _isNarrowLayout(constraints, 560),
              stats: stats,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedStatsSkeleton extends StatelessWidget {
  const _AdvancedStatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SmetchikCard(
      child: _CardTitle(
        icon: Icons.insights_outlined,
        title: 'Рабочая статистика',
        subtitle: 'Загружаем данные',
      ),
    );
  }
}

class _AdvancedStatsLauncherCard extends StatelessWidget {
  const _AdvancedStatsLauncherCard({
    required this.profile,
    required this.estimates,
    required this.onOpen,
    required this.onUpgrade,
  });

  final ProfileModel? profile;
  final List<EstimateModel> estimates;
  final VoidCallback onOpen;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final hasPro = profile?.hasActivePro == true;
    final stats = _AdvancedStatsData.fromEstimates(estimates);
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(
            icon: Icons.insights_outlined,
            title: 'Расширенная статистика',
            subtitle: 'Воронка, деньги по этапам и действия',
          ),
          const SizedBox(height: 12),
          if (hasPro)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SubscriptionChip(
                  icon: Icons.task_alt_outlined,
                  label: '${stats.activeActionCount} требуют внимания',
                ),
                _SubscriptionChip(
                  icon: Icons.trending_up_outlined,
                  label: '${stats.conversionPercent}% конверсия',
                ),
                _SubscriptionChip(
                  icon: Icons.payments_outlined,
                  label: formatMoney(stats.monthTotal),
                ),
              ],
            )
          else
            const _LockedFeatureBanner(
              text:
                  'В Pro видно, какие сметы ждут действия, сколько денег в работе и где проседает воронка.',
            ),
          const SizedBox(height: 12),
          hasPro
              ? FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_full),
                  label: const Text('Открыть статистику'),
                )
              : FilledButton.icon(
                  onPressed: onUpgrade,
                  icon: const Icon(Icons.workspace_premium),
                  label: const Text('Оформить Профи'),
                ),
        ],
      ),
    );
  }
}

class _AdvancedStatsData {
  const _AdvancedStatsData({
    required this.conversionPercent,
    required this.averageEstimate,
    required this.monthTotal,
    required this.monthCount,
    required this.topClientName,
    required this.topClientAmount,
    required this.draftCount,
    required this.sentCount,
    required this.acceptedCount,
    required this.inProgressCount,
    required this.completedCount,
    required this.declinedCount,
    required this.sentAmount,
    required this.acceptedAmount,
    required this.inProgressAmount,
    required this.completedAmount,
    required this.declinedAmount,
    required this.previousMonthTotal,
  });

  final int conversionPercent;
  final double averageEstimate;
  final double monthTotal;
  final int monthCount;
  final String topClientName;
  final double topClientAmount;
  final int draftCount;
  final int sentCount;
  final int acceptedCount;
  final int inProgressCount;
  final int completedCount;
  final int declinedCount;
  final double sentAmount;
  final double acceptedAmount;
  final double inProgressAmount;
  final double completedAmount;
  final double declinedAmount;
  final double previousMonthTotal;

  int get activeActionCount =>
      draftCount + sentCount + acceptedCount + inProgressCount;

  int get monthDeltaPercent {
    if (previousMonthTotal <= 0 && monthTotal <= 0) return 0;
    if (previousMonthTotal <= 0) return 100;
    return (((monthTotal - previousMonthTotal) / previousMonthTotal) * 100)
        .round();
  }

  factory _AdvancedStatsData.fromEstimates(List<EstimateModel> estimates) {
    final sentLike = estimates
        .where(
          (estimate) =>
              EstimateStatus.normalize(estimate.status) != EstimateStatus.draft,
        )
        .length;
    final won = estimates
        .where(
          (estimate) =>
              EstimateStatus.normalize(estimate.status) ==
                  EstimateStatus.accepted ||
              EstimateStatus.normalize(estimate.status) ==
                  EstimateStatus.inProgress ||
              EstimateStatus.normalize(estimate.status) ==
                  EstimateStatus.completed,
        )
        .length;
    final total = estimates.fold<double>(
      0,
      (sum, estimate) => sum + estimate.totalAmount,
    );
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final previousMonthStart = DateTime(now.year, now.month - 1);
    final monthItems = estimates
        .where((estimate) => !estimate.createdAt.isBefore(monthStart))
        .toList();
    final previousMonthItems = estimates
        .where(
          (estimate) =>
              !estimate.createdAt.isBefore(previousMonthStart) &&
              estimate.createdAt.isBefore(monthStart),
        )
        .toList();
    final monthTotal = monthItems.fold<double>(
      0,
      (sum, estimate) => sum + estimate.totalAmount,
    );
    final previousMonthTotal = previousMonthItems.fold<double>(
      0,
      (sum, estimate) => sum + estimate.totalAmount,
    );
    final byClient = <String, double>{};
    for (final estimate in estimates) {
      final name = estimate.client?.name.trim();
      if (name == null || name.isEmpty) continue;
      byClient[name] = (byClient[name] ?? 0) + estimate.totalAmount;
    }
    final topClient = byClient.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _AdvancedStatsData(
      conversionPercent: sentLike == 0 ? 0 : ((won / sentLike) * 100).round(),
      averageEstimate: estimates.isEmpty ? 0 : total / estimates.length,
      monthTotal: monthTotal,
      monthCount: monthItems.length,
      topClientName: topClient.isEmpty ? 'Нет данных' : topClient.first.key,
      topClientAmount: topClient.isEmpty ? 0 : topClient.first.value,
      draftCount: _count(estimates, EstimateStatus.draft),
      sentCount: _count(estimates, EstimateStatus.sent),
      acceptedCount: _count(estimates, EstimateStatus.accepted),
      inProgressCount: _count(estimates, EstimateStatus.inProgress),
      completedCount: _count(estimates, EstimateStatus.completed),
      declinedCount: _count(estimates, EstimateStatus.declined),
      sentAmount: _amount(estimates, EstimateStatus.sent),
      acceptedAmount: _amount(estimates, EstimateStatus.accepted),
      inProgressAmount: _amount(estimates, EstimateStatus.inProgress),
      completedAmount: _amount(estimates, EstimateStatus.completed),
      declinedAmount: _amount(estimates, EstimateStatus.declined),
      previousMonthTotal: previousMonthTotal,
    );
  }

  static int _count(List<EstimateModel> estimates, String status) {
    return estimates
        .where(
          (estimate) => EstimateStatus.normalize(estimate.status) == status,
        )
        .length;
  }

  static double _amount(List<EstimateModel> estimates, String status) {
    return estimates
        .where(
          (estimate) => EstimateStatus.normalize(estimate.status) == status,
        )
        .fold<double>(0, (sum, estimate) => sum + estimate.totalAmount);
  }
}

class _NextActionsPanel extends StatelessWidget {
  const _NextActionsPanel({required this.stats});

  final _AdvancedStatsData stats;

  @override
  Widget build(BuildContext context) {
    final hasActions = stats.activeActionCount > 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.task_alt_outlined,
                  color: AppColors.orange,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasActions
                          ? '${stats.activeActionCount} смет требуют внимания'
                          : 'Срочных действий нет',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      hasActions
                          ? 'Быстро видно, что отправить, напомнить или закрыть'
                          : 'Рабочая доска чистая, можно создавать новую смету',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = _isNarrowLayout(constraints, 540);
              final tiles = [
                _ActionStatusTile(
                  icon: Icons.edit_note_outlined,
                  label: 'Черновики',
                  value: stats.draftCount,
                  hint: 'дожать и отправить',
                  color: AppColors.textSecondary,
                  dark: true,
                ),
                _ActionStatusTile(
                  icon: Icons.mark_email_unread_outlined,
                  label: 'Ждут ответа',
                  value: stats.sentCount,
                  hint: 'напомнить клиенту',
                  color: AppColors.info,
                  dark: true,
                ),
                _ActionStatusTile(
                  icon: Icons.thumb_up_alt_outlined,
                  label: 'Приняты',
                  value: stats.acceptedCount,
                  hint: 'поставить в работу',
                  color: AppColors.orange,
                  dark: true,
                ),
                _ActionStatusTile(
                  icon: Icons.construction_outlined,
                  label: 'В работе',
                  value: stats.inProgressCount,
                  hint: 'закрыть после объекта',
                  color: AppColors.success,
                  dark: true,
                ),
              ];

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final tile in tiles) ...[
                      tile,
                      if (tile != tiles.last) const SizedBox(height: 8),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  for (final tile in tiles) ...[
                    Expanded(child: tile),
                    if (tile != tiles.last) const SizedBox(width: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MoneyPipelinePanel extends StatelessWidget {
  const _MoneyPipelinePanel({required this.stats});

  final _AdvancedStatsData stats;

  @override
  Widget build(BuildContext context) {
    final potential =
        stats.sentAmount + stats.acceptedAmount + stats.inProgressAmount;
    final total = [
      potential,
      stats.completedAmount,
      stats.declinedAmount,
    ].reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Деньги по этапам',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _PipelineMoneyRow(
            label: 'Возможная выручка',
            value: potential,
            total: total,
            color: AppColors.orange,
          ),
          _PipelineMoneyRow(
            label: 'Сейчас в работе',
            value: stats.inProgressAmount,
            total: total,
            color: AppColors.info,
          ),
          _PipelineMoneyRow(
            label: 'Уже получено',
            value: stats.completedAmount,
            total: total,
            color: AppColors.success,
          ),
          _PipelineMoneyRow(
            label: 'Отклонено',
            value: stats.declinedAmount,
            total: total,
            color: AppColors.danger,
          ),
        ],
      ),
    );
  }
}

class _EstimateFunnelPanel extends StatelessWidget {
  const _EstimateFunnelPanel({required this.stats});

  final _AdvancedStatsData stats;

  @override
  Widget build(BuildContext context) {
    final items = [
      _FunnelItem('Черновик', stats.draftCount, AppColors.textHint),
      _FunnelItem('Отправлена', stats.sentCount, AppColors.info),
      _FunnelItem('Принята', stats.acceptedCount, AppColors.orange),
      _FunnelItem('В работе', stats.inProgressCount, AppColors.graphite),
      _FunnelItem('Завершена', stats.completedCount, AppColors.success),
      _FunnelItem('Отклонена', stats.declinedCount, AppColors.danger),
    ];
    final maxCount = items.fold<int>(
      0,
      (previous, item) => item.count > previous ? item.count : previous,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Воронка смет',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          for (final item in items) ...[
            _FunnelRow(item: item, maxCount: maxCount),
            if (item != items.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _StatsInsightRow extends StatelessWidget {
  const _StatsInsightRow({required this.compact, required this.stats});

  final bool compact;
  final _AdvancedStatsData stats;

  @override
  Widget build(BuildContext context) {
    final delta = stats.monthDeltaPercent;
    final deltaPrefix = delta > 0 ? '+' : '';
    final tiles = [
      _AnalyticsTile(
        label: 'Конверсия',
        value: '${stats.conversionPercent}%',
        subtitle: 'принятые от отправленных',
        accent: stats.conversionPercent >= 50,
      ),
      _AnalyticsTile(
        label: 'Средний чек',
        value: formatMoney(stats.averageEstimate),
        subtitle: 'по всем сметам',
      ),
      _AnalyticsTile(
        label: 'Этот месяц',
        value: formatMoney(stats.monthTotal),
        subtitle: '${stats.monthCount} смет · $deltaPrefix$delta%',
        accent: delta >= 0 && stats.monthTotal > 0,
      ),
      _AnalyticsTile(
        label: 'Лучший клиент',
        value: stats.topClientName,
        subtitle: formatMoney(stats.topClientAmount),
      ),
    ];

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tile in tiles) ...[
            tile,
            if (tile != tiles.last) const SizedBox(height: 8),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - 8) / 2
            : 260.0;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _ActionStatusTile extends StatelessWidget {
  const _ActionStatusTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
    this.dark = false,
  });

  final IconData icon;
  final String label;
  final int value;
  final String hint;
  final Color color;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final baseColor = dark ? Colors.white : AppColors.graphite;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.08) : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dark ? Colors.white.withValues(alpha: 0.09) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: dark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: dark ? Colors.white : color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: baseColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: baseColor.withValues(alpha: dark ? 0.62 : 0.55),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: TextStyle(
              color: baseColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineMoneyRow extends StatelessWidget {
  const _PipelineMoneyRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final double value;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final progress = total <= 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                formatMoney(value),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              color: color,
              backgroundColor: AppColors.border,
            ),
          ),
        ],
      ),
    );
  }
}

class _FunnelItem {
  const _FunnelItem(this.label, this.count, this.color);

  final String label;
  final int count;
  final Color color;
}

class _FunnelRow extends StatelessWidget {
  const _FunnelRow({required this.item, required this.maxCount});

  final _FunnelItem item;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final progress = maxCount <= 0 ? 0.0 : item.count / maxCount;
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              color: item.color,
              backgroundColor: AppColors.border,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 24,
          child: Text(
            '${item.count}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _AnalyticsTile extends StatelessWidget {
  const _AnalyticsTile({
    required this.label,
    required this.value,
    required this.subtitle,
    this.accent = false,
  });

  final String label;
  final String value;
  final String subtitle;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent ? AppColors.success : AppColors.graphite,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textHint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PdfSettingsLauncherCard extends StatelessWidget {
  const _PdfSettingsLauncherCard({
    required this.profile,
    required this.template,
    required this.accentColor,
    required this.onOpen,
    required this.onUpgrade,
  });

  final ProfileModel? profile;
  final String template;
  final String accentColor;
  final VoidCallback onOpen;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final hasPro = profile?.hasActivePro == true;
    final config = SmetaTemplates.byId(template);
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Оформление PDF',
            subtitle: 'Шаблоны, цвета, подписи и предпросмотр',
          ),
          const SizedBox(height: 12),
          if (hasPro)
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _colorFromHex(accentColor),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.shortName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '${PdfAccentColor.label(accentColor)} · предпросмотр внутри редактора',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            const _LockedFeatureBanner(
              text:
                  'На Базовом тарифе PDF создаётся в стандартном стиле. В Pro можно выбрать оформление и скрыть отметку Сметчика.',
            ),
          const SizedBox(height: 12),
          hasPro
              ? FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.tune),
                  label: const Text('Редактировать PDF'),
                )
              : FilledButton.icon(
                  onPressed: onUpgrade,
                  icon: const Icon(Icons.workspace_premium),
                  label: const Text('Оформить Профи'),
                ),
        ],
      ),
    );
  }
}

class _PdfSettingsCard extends StatelessWidget {
  const _PdfSettingsCard({
    required this.profile,
    required this.busy,
    required this.showBrandHeader,
    required this.showSignatures,
    required this.showServiceMark,
    required this.template,
    required this.accentColor,
    required this.paymentTerms,
    required this.footerNote,
    required this.onTemplateChanged,
    required this.onAccentColorChanged,
    required this.onShowBrandHeaderChanged,
    required this.onShowSignaturesChanged,
    required this.onShowServiceMarkChanged,
    required this.onSave,
    required this.onUpgrade,
  });

  final ProfileModel? profile;
  final bool busy;
  final bool showBrandHeader;
  final bool showSignatures;
  final bool showServiceMark;
  final String template;
  final String accentColor;
  final TextEditingController paymentTerms;
  final TextEditingController footerNote;
  final ValueChanged<String> onTemplateChanged;
  final ValueChanged<String> onAccentColorChanged;
  final ValueChanged<bool> onShowBrandHeaderChanged;
  final ValueChanged<bool> onShowSignaturesChanged;
  final ValueChanged<bool> onShowServiceMarkChanged;
  final VoidCallback onSave;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final hasPro = profile?.hasActivePro == true;
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF сметы',
            subtitle: 'Оформление коммерческого предложения',
          ),
          const SizedBox(height: 12),
          if (!hasPro) ...[
            const _LockedFeatureBanner(
              text:
                  'На Базовом тарифе PDF создаётся в стандартном виде. В Pro можно выбрать стиль, цвет, шапку, подписи и блоки с условиями.',
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = _isNarrowLayout(constraints, 620);
              final controls = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PdfPresetPicker(
                    selectedTemplate: template,
                    selectedAccentColor: accentColor,
                    enabled: hasPro && !busy,
                    onSelected: (config) {
                      onTemplateChanged(config.id);
                      onAccentColorChanged(config.colors.accent);
                    },
                  ),
                  const SizedBox(height: 12),
                  _PdfColorPicker(
                    template: template,
                    selected: accentColor,
                    enabled: hasPro && !busy,
                    onChanged: onAccentColorChanged,
                  ),
                ],
              );
              final preview = ListenableBuilder(
                listenable: Listenable.merge([paymentTerms, footerNote]),
                builder: (context, _) => _PdfPreviewMock(
                  template: hasPro ? template : PdfTemplate.classic,
                  accentColor: hasPro ? accentColor : PdfAccentColor.orange,
                  showBrandHeader: !hasPro,
                  showSignatures: !hasPro || showSignatures,
                  showServiceMark: !hasPro,
                  paymentTerms: hasPro ? paymentTerms.text : '',
                  footerNote: hasPro ? footerNote.text : '',
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [preview, const SizedBox(height: 12), controls],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: preview),
                  const SizedBox(width: 12),
                  Expanded(child: controls),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _PdfSwitch(
            title: 'Бренд мастера в PDF',
            subtitle: 'В Pro в шапке используется имя и логотип мастера',
            value: hasPro ? true : showBrandHeader,
            enabled: false,
            onChanged: onShowBrandHeaderChanged,
          ),
          _PdfSwitch(
            title: 'Подписи сторон',
            subtitle: 'Линии для исполнителя и заказчика в конце PDF',
            value: showSignatures,
            enabled: hasPro && !busy,
            onChanged: onShowSignaturesChanged,
          ),
          _PdfSwitch(
            title: 'Отметка «Создано в Сметчике»',
            subtitle: 'В Базовом показывается всегда, в Pro убирается',
            value: !hasPro && showServiceMark,
            enabled: false,
            onChanged: onShowServiceMarkChanged,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: paymentTerms,
            enabled: hasPro && !busy,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Условия оплаты',
              hintText: 'Например: 50% предоплата, остаток после приёмки',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: footerNote,
            enabled: hasPro && !busy,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Примечание в PDF',
              hintText: 'Например: смета действует 7 дней',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: hasPro
                ? FilledButton.icon(
                    onPressed: busy ? null : onSave,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Сохранить PDF'),
                  )
                : FilledButton.icon(
                    onPressed: onUpgrade,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: const Icon(Icons.workspace_premium),
                    label: const Text('Оформить Профи'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PdfPresetPicker extends StatelessWidget {
  const _PdfPresetPicker({
    required this.selectedTemplate,
    required this.selectedAccentColor,
    required this.enabled,
    required this.onSelected,
  });

  final String selectedTemplate;
  final String selectedAccentColor;
  final bool enabled;
  final ValueChanged<SmetaTemplateConfig> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldCaption('Готовые оформления'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in SmetaTemplates.premiumValues)
              _PdfPresetChip(
                preset: preset,
                selected:
                    PdfTemplate.normalize(preset.id) ==
                        PdfTemplate.normalize(selectedTemplate) &&
                    PdfAccentColor.normalize(preset.colors.accent) ==
                        PdfAccentColor.normalize(selectedAccentColor),
                enabled: enabled,
                onTap: () => onSelected(preset),
              ),
          ],
        ),
      ],
    );
  }
}

class _PdfPresetChip extends StatelessWidget {
  const _PdfPresetChip({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final SmetaTemplateConfig preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _colorFromHex(preset.colors.accent);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 148,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? AppColors.orangeLight : AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.orange : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(preset.icon, color: Colors.white, size: 18),
                ),
                const Spacer(),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? AppColors.orange : AppColors.textHint,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preset.shortName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              preset.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfColorPicker extends StatelessWidget {
  const _PdfColorPicker({
    required this.template,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String template;
  final String selected;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final normalized = PdfAccentColor.normalize(selected);
    final colors = SmetaTemplates.accentChoicesFor(template);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldCaption('Акцентный цвет'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in colors)
              _PdfColorDot(
                value: color,
                selected: PdfAccentColor.normalize(color) == normalized,
                enabled: enabled,
                onTap: () => onChanged(color),
              ),
          ],
        ),
      ],
    );
  }
}

class _PdfColorDot extends StatelessWidget {
  const _PdfColorDot({
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String value;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(value);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.orangeLight : AppColors.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.orange : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: AppColors.border, blurRadius: 0),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Text(
              PdfAccentColor.label(value),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            if (selected) ...[
              const SizedBox(width: 5),
              const Icon(Icons.check, size: 15, color: AppColors.orange),
            ],
          ],
        ),
      ),
    );
  }
}

class _PdfPreviewMock extends StatelessWidget {
  const _PdfPreviewMock({
    required this.template,
    required this.accentColor,
    required this.showBrandHeader,
    required this.showSignatures,
    required this.showServiceMark,
    required this.paymentTerms,
    required this.footerNote,
  });

  final String template;
  final String accentColor;
  final bool showBrandHeader;
  final bool showSignatures;
  final bool showServiceMark;
  final String paymentTerms;
  final String footerNote;

  @override
  Widget build(BuildContext context) {
    final config = SmetaTemplates.byId(template);
    final accent = _colorFromHex(accentColor);
    final background = _colorFromHex(config.colors.background);
    final surface = _colorFromHex(config.colors.surface);
    final primaryText = _colorFromHex(config.colors.primaryText);
    final secondaryText = _colorFromHex(config.colors.secondaryText);
    final border = _colorFromHex(config.colors.border);
    final compact =
        config.id == PdfTemplate.storyFormat ||
        config.layout.tableStyle == 'compact';
    final totalTop = config.layout.totalsPosition == 'top';
    final boxedRows = config.layout.tableStyle == 'boxed';
    final gridRows =
        config.layout.tableStyle == 'grid' ||
        config.layout.tableStyle == 'detailed';
    final radius = switch (config.layout.cornerStyle) {
      'sharp' => 2.0,
      'pill' => 20.0,
      _ => 14.0,
    };
    final headerCentered = config.layout.headerAlign == 'center';
    final dark =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
    final headerBg = config.layout.dividerStyle == 'none' ? surface : accent;
    final headerTextColor =
        ThemeData.estimateBrightnessForColor(headerBg) == Brightness.dark
        ? Colors.white
        : primaryText;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FieldCaption('Предпросмотр PDF'),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 320),
            padding: EdgeInsets.all(compact ? 12 : 16),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(radius + 4),
              border: Border.all(color: border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: headerCentered
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                if (config.features.showCoverPage) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(radius),
                    ),
                    child: Text(
                      'Обложка КП · Алексей · 10.07',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: EdgeInsets.all(compact ? 10 : 14),
                  decoration: BoxDecoration(
                    color: headerBg,
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: border),
                  ),
                  child: headerCentered
                      ? Column(
                          children: [
                            _PreviewLogo(
                              accent: accent,
                              foreground: headerTextColor,
                              showBrandHeader: showBrandHeader,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              config.shortName,
                              style: TextStyle(
                                color: headerTextColor,
                                fontWeight: FontWeight.w900,
                                fontSize: compact ? 14 : 16,
                              ),
                            ),
                            Text(
                              'Коммерческое предложение',
                              style: TextStyle(
                                color: headerTextColor.withValues(alpha: 0.68),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            _PreviewLogo(
                              accent: accent,
                              foreground: headerTextColor,
                              showBrandHeader: showBrandHeader,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    showBrandHeader ? 'Сметчик' : 'Илья',
                                    style: TextStyle(
                                      color: headerTextColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: compact ? 14 : 16,
                                    ),
                                  ),
                                  Text(
                                    config.shortName,
                                    style: TextStyle(
                                      color: headerTextColor.withValues(
                                        alpha: 0.68,
                                      ),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '10.07',
                              style: TextStyle(
                                color: headerTextColor.withValues(alpha: 0.68),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                ),
                SizedBox(height: compact ? 10 : 14),
                Text(
                  'Ремонт ванной',
                  textAlign: headerCentered ? TextAlign.center : TextAlign.left,
                  style: TextStyle(
                    fontSize: compact ? 17 : 20,
                    fontWeight: FontWeight.w900,
                    color: primaryText,
                  ),
                ),
                const SizedBox(height: 6),
                if (totalTop) ...[
                  _PdfPreviewTotal(
                    accent: accent,
                    radius: radius,
                    dark: dark,
                    amount: '13 200 ₽',
                  ),
                  SizedBox(height: compact ? 10 : 14),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: headerCentered
                      ? WrapAlignment.center
                      : WrapAlignment.start,
                  children: [
                    _PdfPreviewPill(
                      label: 'Клиент',
                      value: 'Алексей',
                      surface: surface,
                      border: border,
                      textColor: primaryText,
                    ),
                    _PdfPreviewPill(
                      label: 'Срок',
                      value: '14 дней',
                      surface: surface,
                      border: border,
                      textColor: primaryText,
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 14),
                _PdfPreviewLine(
                  index: 1,
                  title: 'Разводка труб',
                  subtitle: '12 м × 750 ₽',
                  amount: '9 000 ₽',
                  accent: accent,
                  compact: compact,
                  boxed: boxedRows,
                  grid: gridRows,
                  surface: surface,
                  border: border,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                  radius: radius,
                ),
                _PdfPreviewLine(
                  index: 2,
                  title: 'Монтаж смесителя',
                  subtitle: '1 шт × 2 400 ₽',
                  amount: '2 400 ₽',
                  accent: accent,
                  compact: compact,
                  boxed: boxedRows,
                  grid: gridRows,
                  surface: surface,
                  border: border,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                  radius: radius,
                ),
                _PdfPreviewLine(
                  index: 3,
                  title: 'Герметизация',
                  subtitle: '1 компл. × 1 800 ₽',
                  amount: '1 800 ₽',
                  accent: accent,
                  compact: compact,
                  boxed: boxedRows,
                  grid: gridRows,
                  surface: surface,
                  border: border,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                  radius: radius,
                ),
                if (!totalTop) ...[
                  SizedBox(height: compact ? 10 : 14),
                  _PdfPreviewTotal(
                    accent: accent,
                    radius: radius,
                    dark: dark,
                    amount: '13 200 ₽',
                  ),
                ],
                if (paymentTerms.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _PdfPreviewNote(
                    title: 'Оплата',
                    text: paymentTerms.trim(),
                    accent: accent,
                    textColor: primaryText,
                  ),
                ],
                if (footerNote.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _PdfPreviewNote(
                    title: 'Примечание',
                    text: footerNote.trim(),
                    accent: accent,
                    textColor: primaryText,
                  ),
                ],
                if (showSignatures) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _PdfSignatureLine(
                          label: 'Исполнитель',
                          textColor: primaryText,
                          border: border,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PdfSignatureLine(
                          label: 'Заказчик',
                          textColor: primaryText,
                          border: border,
                        ),
                      ),
                    ],
                  ),
                ],
                if (config.features.showStampArea) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 84,
                      height: 42,
                      decoration: BoxDecoration(
                        border: Border.all(color: accent, width: 1.2),
                        borderRadius: BorderRadius.circular(radius),
                      ),
                      child: Center(
                        child: Text(
                          'место печати',
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (showServiceMark) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Создано в Сметчике',
                      style: TextStyle(
                        color: secondaryText.withValues(alpha: 0.72),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if (config.features.showWatermark) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'водяной знак: ${config.features.watermarkText}',
                      style: TextStyle(
                        color: secondaryText.withValues(alpha: 0.52),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldCaption extends StatelessWidget {
  const _FieldCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _PreviewLogo extends StatelessWidget {
  const _PreviewLogo({
    required this.accent,
    required this.foreground,
    required this.showBrandHeader,
  });

  final Color accent;
  final Color foreground;
  final bool showBrandHeader;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Icon(
        showBrandHeader ? Icons.receipt_long_outlined : Icons.person_outline,
        color: foreground,
        size: 19,
      ),
    );
  }
}

class _PdfPreviewTotal extends StatelessWidget {
  const _PdfPreviewTotal({
    required this.accent,
    required this.radius,
    required this.dark,
    required this.amount,
  });

  final Color accent;
  final double radius;
  final bool dark;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final foreground =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : AppColors.graphite;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: dark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Text(
            'Итого',
            style: TextStyle(
              color: foreground.withValues(alpha: 0.74),
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(
            amount,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _PdfPreviewPill extends StatelessWidget {
  const _PdfPreviewPill({
    required this.label,
    required this.value,
    required this.surface,
    required this.border,
    required this.textColor,
  });

  final String label;
  final String value;
  final Color surface;
  final Color border;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PdfPreviewLine extends StatelessWidget {
  const _PdfPreviewLine({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.accent,
    required this.compact,
    required this.boxed,
    required this.grid,
    required this.surface,
    required this.border,
    required this.primaryText,
    required this.secondaryText,
    required this.radius,
  });

  final int index;
  final String title;
  final String subtitle;
  final String amount;
  final Color accent;
  final bool compact;
  final bool boxed;
  final bool grid;
  final Color surface;
  final Color border;
  final Color primaryText;
  final Color secondaryText;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Container(
          width: 25,
          height: 25,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(radius > 8 ? 8 : radius),
          ),
          child: Center(
            child: Text(
              '$index',
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: primaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: secondaryText,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          amount,
          style: TextStyle(
            color: primaryText,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 6 : 8),
      padding: boxed || grid ? const EdgeInsets.all(8) : EdgeInsets.zero,
      decoration: boxed || grid
          ? BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: border),
            )
          : null,
      child: row,
    );
  }
}

class _PdfPreviewNote extends StatelessWidget {
  const _PdfPreviewNote({
    required this.title,
    required this.text,
    required this.accent,
    required this.textColor,
  });

  final String title;
  final String text;
  final Color accent;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfSignatureLine extends StatelessWidget {
  const _PdfSignatureLine({
    required this.label,
    required this.textColor,
    required this.border,
  });

  final String label;
  final Color textColor;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: border),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.62),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

Color _colorFromHex(String value) {
  final normalized = PdfAccentColor.normalize(value).replaceFirst('#', '');
  return Color(int.parse('FF$normalized', radix: 16));
}

class _PdfSwitch extends StatelessWidget {
  const _PdfSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
      ),
      subtitle: Text(subtitle),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _LockedFeatureBanner extends StatelessWidget {
  const _LockedFeatureBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.orangeLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.orangeDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.graphite,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.orangeLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.orangeDark, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.profile,
    required this.estimates,
    required this.busy,
    required this.onTap,
  });

  final ProfileModel? profile;
  final List<EstimateModel> estimates;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rawPlan = profile?.subscriptionPlan ?? SubscriptionPlan.basic;
    final displayPlan =
        profile?.effectiveSubscriptionPlan ?? SubscriptionPlan.basic;
    final expiredPro =
        SubscriptionPlan.normalize(rawPlan) == SubscriptionPlan.pro &&
        profile?.hasActivePro != true;
    final hasActivePro = profile?.hasActivePro == true;
    final isPaid = hasActivePro;
    final createdThisMonth = _createdThisMonth(estimates);
    final limit = profile?.monthlyEstimateLimit;
    final remaining = profile?.remainingMonthlyEstimates(createdThisMonth);
    final renewsAt = profile?.subscriptionRenewsAt;

    return SmetchikCard(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isPaid ? AppColors.graphite : AppColors.orangeLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isPaid
                  ? Icons.workspace_premium
                  : Icons.workspace_premium_outlined,
              color: isPaid ? AppColors.orange : AppColors.orangeDark,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Тариф ${SubscriptionPlan.label(displayPlan)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subscriptionSummary(
                    profile: profile,
                    createdThisMonth: createdThisMonth,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (!hasActivePro && limit != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: _LimitMeter(
                value: createdThisMonth,
                limit: limit,
                remaining: remaining ?? 0,
              ),
            ),
          if (hasActivePro && renewsAt != null)
            _SubscriptionChip(
              icon: Icons.event_available_outlined,
              label: 'до ${formatDate(renewsAt)}',
            ),
          if (expiredPro)
            const _SubscriptionChip(
              icon: Icons.schedule_outlined,
              label: 'Профи истёк',
            ),
          _SubscriptionChip(
            icon: Icons.account_balance_wallet_outlined,
            label: SubscriptionSource.label(
              profile?.subscriptionSource ?? SubscriptionSource.manual,
            ),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : onTap,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            icon: const Icon(Icons.tune),
            label: const Text('Тарифы'),
          ),
        ],
      ),
    );
  }
}

String _subscriptionSummary({
  required ProfileModel? profile,
  required int createdThisMonth,
}) {
  final current = profile;
  if (current == null) return 'Загрузка тарифа';
  if (current.hasActivePro) {
    return '${SubscriptionPlan.price(SubscriptionPlan.pro)} · безлимитные сметы';
  }
  final limit =
      current.monthlyEstimateLimit ?? ProfileModel.basicMonthlyEstimateLimit;
  final displayedCreated = createdThisMonth > limit ? limit : createdThisMonth;
  if (SubscriptionPlan.normalize(current.subscriptionPlan) ==
      SubscriptionPlan.pro) {
    return 'Профи неактивен · базовый лимит $displayedCreated/$limit';
  }
  return '${SubscriptionPlan.price(SubscriptionPlan.basic)} · $displayedCreated/$limit смет в этом месяце';
}

class _LimitMeter extends StatelessWidget {
  const _LimitMeter({
    required this.value,
    required this.limit,
    required this.remaining,
  });

  final int value;
  final int limit;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final progress = limit == 0 ? 1.0 : (value / limit).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: progress,
            color: remaining == 0 ? AppColors.danger : AppColors.orange,
            backgroundColor: AppColors.border,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          remaining == 0 ? 'лимит исчерпан' : 'осталось $remaining',
          style: TextStyle(
            color: remaining == 0 ? AppColors.danger : AppColors.textHint,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SubscriptionChip extends StatelessWidget {
  const _SubscriptionChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionTestPanel extends StatelessWidget {
  const _SubscriptionTestPanel({
    required this.profile,
    required this.busy,
    required this.onActivate,
    required this.onExtend,
    required this.onExpire,
    required this.onBasic,
  });

  final ProfileModel? profile;
  final bool busy;
  final VoidCallback onActivate;
  final VoidCallback onExtend;
  final VoidCallback onExpire;
  final VoidCallback onBasic;

  @override
  Widget build(BuildContext context) {
    final hasActivePro = profile?.hasActivePro == true;
    return SmetchikCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.science_outlined, color: AppColors.orangeDark),
              SizedBox(width: 8),
              Text(
                'Тест оплаты',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Пока без эквайринга: эти кнопки меняют подписку как будто платёж прошёл.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : (hasActivePro ? onExtend : onActivate),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                icon: const Icon(Icons.workspace_premium),
                label: Text(
                  hasActivePro ? 'Продлить Профи' : 'Оплатить тестово',
                ),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onExpire,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.schedule_outlined),
                label: const Text('Истечь срок'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onBasic,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Базовый'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TariffBadge extends StatelessWidget {
  const _TariffBadge({required this.plan, required this.onTap});

  final String plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.graphite,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.workspace_premium,
              color: AppColors.orange,
              size: 16,
            ),
            const SizedBox(width: 5),
            Text(
              SubscriptionPlan.label(plan),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TariffSheet extends StatelessWidget {
  const _TariffSheet({required this.currentPlan, required this.onSelect});

  final String currentPlan;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Тарифы',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Выберите план под объём работы',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                for (final plan in SubscriptionPlan.values) ...[
                  _TariffPlanCard(
                    plan: plan,
                    selected:
                        SubscriptionPlan.normalize(currentPlan) ==
                        SubscriptionPlan.normalize(plan),
                    onSelect: () => onSelect(plan),
                  ),
                  if (plan != SubscriptionPlan.values.last)
                    const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MockCheckoutSheet extends StatelessWidget {
  const _MockCheckoutSheet({required this.onPay});

  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.graphite,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.workspace_premium,
                        color: AppColors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Профи',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Тестовая оплата для проверки MVP',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      SubscriptionPlan.price(SubscriptionPlan.pro),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'После оплаты включится',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      for (final feature in SubscriptionPlan.features(
                        SubscriptionPlan.pro,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: AppColors.success,
                                size: 17,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  feature,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const _MockPaymentMethod(
                  icon: Icons.credit_card,
                  title: 'Банковская карта',
                  subtitle: 'Будущий web-платёж через провайдера',
                  selected: true,
                ),
                const SizedBox(height: 8),
                const _MockPaymentMethod(
                  icon: Icons.android,
                  title: 'Google Play',
                  subtitle: 'Для Android-подписки после публикации',
                ),
                const SizedBox(height: 8),
                const _MockPaymentMethod(
                  icon: Icons.phone_iphone,
                  title: 'App Store',
                  subtitle: 'Для будущей нативной iOS-версии',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Сейчас деньги не списываются. Кнопка ниже только меняет статус подписки, чтобы можно было проверить ограничения и истечение срока.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onPay,
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text('Оплатить тестово'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Позже'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MockPaymentMethod extends StatelessWidget {
  const _MockPaymentMethod({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? AppColors.orangeLight : AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppColors.orange : AppColors.border,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: selected ? AppColors.orange : AppColors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: selected ? Colors.white : AppColors.orangeDark,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? AppColors.orange : AppColors.textHint,
          ),
        ],
      ),
    );
  }
}

class _TariffPlanCard extends StatelessWidget {
  const _TariffPlanCard({
    required this.plan,
    required this.selected,
    required this.onSelect,
  });

  final String plan;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final normalized = SubscriptionPlan.normalize(plan);
    final accent = normalized != SubscriptionPlan.basic;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.orangeLight : AppColors.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.orange : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent ? AppColors.graphite : AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    accent
                        ? Icons.workspace_premium
                        : Icons.workspace_premium_outlined,
                    color: accent ? AppColors.orange : AppColors.orangeDark,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        SubscriptionPlan.label(plan),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        SubscriptionPlan.caption(plan),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  SubscriptionPlan.price(plan),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final feature in SubscriptionPlan.features(plan)) ...[
              _TariffFeature(text: feature),
              if (feature != SubscriptionPlan.features(plan).last)
                const SizedBox(height: 6),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: selected
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check),
                      label: const Text('Выбран'),
                    )
                  : FilledButton(
                      onPressed: onSelect,
                      child: const Text('Выбрать'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TariffFeature extends StatelessWidget {
  const _TariffFeature({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: AppColors.success, size: 16),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

bool _isNarrowLayout(BoxConstraints constraints, double breakpoint) {
  return !constraints.maxWidth.isFinite || constraints.maxWidth < breakpoint;
}

int _createdThisMonth(List<EstimateModel> estimates) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month);
  return estimates
      .where((estimate) => !estimate.createdAt.isBefore(start))
      .length;
}

class _ProfileStats extends StatelessWidget {
  const _ProfileStats({required this.estimates});

  final List<EstimateModel> estimates;

  @override
  Widget build(BuildContext context) {
    final received = estimates
        .where((estimate) => EstimateStatus.isCompleted(estimate.status))
        .fold<double>(0, (sum, estimate) => sum + estimate.totalAmount);
    final active = estimates
        .where((estimate) => EstimateStatus.isActiveWork(estimate.status))
        .fold<double>(0, (sum, estimate) => sum + estimate.totalAmount);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = _isNarrowLayout(constraints, 520);
        final cards = [
          _ProfileStatCard(
            icon: Icons.receipt_long_outlined,
            label: 'Смет создано',
            value: '${estimates.length}',
          ),
          _ProfileStatCard(
            icon: Icons.payments_outlined,
            label: 'Получено',
            value: formatMoney(received),
            accent: true,
          ),
          _ProfileStatCard(
            icon: Icons.handyman_outlined,
            label: 'В работе',
            value: formatMoney(active),
          ),
        ];

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[
                card,
                if (card != cards.last) const SizedBox(height: 8),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (final card in cards) ...[
              Expanded(child: card),
              if (card != cards.last) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }
}

class _ProfileStatsSkeleton extends StatelessWidget {
  const _ProfileStatsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileStatCard(
          icon: Icons.receipt_long_outlined,
          label: 'Смет создано',
          value: '—',
        ),
        SizedBox(height: 8),
        _ProfileStatCard(
          icon: Icons.payments_outlined,
          label: 'Получено',
          value: '—',
        ),
        SizedBox(height: 8),
        _ProfileStatCard(
          icon: Icons.handyman_outlined,
          label: 'В работе',
          value: '—',
        ),
      ],
    );
  }
}

class _ProfileStatCard extends StatelessWidget {
  const _ProfileStatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent ? AppColors.success : AppColors.orangeDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent ? AppColors.success : AppColors.graphite,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
