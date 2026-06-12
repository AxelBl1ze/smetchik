import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_theme.dart';
import '../../core/auth_controller.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/russian_phone_input_formatter.dart';
import '../../shared/specialization_field.dart';
import '../../shared/ui.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _spec = TextEditingController();
  final _nameFocus = FocusNode();
  String _currency = 'RUB';
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
                  Row(
                    children: [
                      _AvatarButton(
                        initials: value?.initials ?? 'СМ',
                        imageUrl: ref
                            .read(repositoryProvider)
                            .logoPublicUrl(value?.logoPath),
                        busy: _saving,
                        onTap: _pickAvatar,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ProfileNameField(
                          controller: _name,
                          focusNode: _nameFocus,
                          editing: _editingName,
                          onEdit: _startNameEditing,
                          onSubmitted: _finishNameEditing,
                        ),
                      ),
                      const _TariffBadge(),
                    ],
                  ),
                  const SizedBox(height: 14),
                  estimates.when(
                    data: (items) => _ProfileStats(estimates: items),
                    loading: () => const _ProfileStatsSkeleton(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SmetchikCard(
              child: Column(
                children: [
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
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(
                      labelText: 'Валюта',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'RUB',
                        child: Text('₽ Российский рубль'),
                      ),
                      DropdownMenuItem(value: 'USD', child: Text('\$ Доллар')),
                      DropdownMenuItem(value: 'EUR', child: Text('€ Евро')),
                    ],
                    onChanged: (value) =>
                        setState(() => _currency = value ?? 'RUB'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 560;
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
      maxWidth: 1024,
      imageQuality: 88,
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

  void _hydrate(ProfileModel profile) {
    if (!mounted || _hydrated) return;
    _hydrated = true;
    _name.text = profile.fullName;
    _phone.text = RussianPhoneInputFormatter.format(profile.phone ?? '');
    _spec.text = profile.specialization ?? '';
    _currency = profile.currency;
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
            currency: _currency,
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

class _TariffBadge extends StatelessWidget {
  const _TariffBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, color: AppColors.orange, size: 16),
          SizedBox(width: 5),
          Text(
            'Базовый',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ProfileStats extends StatelessWidget {
  const _ProfileStats({required this.estimates});

  final List<EstimateModel> estimates;

  @override
  Widget build(BuildContext context) {
    final received = estimates
        .where((estimate) => estimate.status == 'completed')
        .fold<double>(0, (sum, estimate) => sum + estimate.totalAmount);
    final active = estimates
        .where((estimate) => estimate.status == 'approved')
        .fold<double>(0, (sum, estimate) => sum + estimate.totalAmount);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
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
    return const Row(
      children: [
        Expanded(
          child: _ProfileStatCard(
            icon: Icons.receipt_long_outlined,
            label: 'Смет создано',
            value: '—',
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _ProfileStatCard(
            icon: Icons.payments_outlined,
            label: 'Получено',
            value: '—',
          ),
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
