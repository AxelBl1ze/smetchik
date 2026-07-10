import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../shared/address_autocomplete_field.dart';
import '../../shared/russian_phone_input_formatter.dart';
import '../../shared/ui.dart';
import '../../shared/upgrade_sheet.dart';

class ClientFormScreen extends ConsumerStatefulWidget {
  const ClientFormScreen({super.key, this.clientId});

  final String? clientId;

  @override
  ConsumerState<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends ConsumerState<ClientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  bool _hydrated = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsProvider);
    clients.whenData((items) {
      if (!_hydrated && widget.clientId != null) {
        final client = items
            .where((item) => item.id == widget.clientId)
            .firstOrNull;
        if (client != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate(client));
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clientId == null ? 'Новый клиент' : 'Клиент'),
      ),
      body: Form(
        key: _formKey,
        child: ResponsiveListView(
          maxWidth: 720,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Имя клиента'),
              validator: (value) {
                if (value == null || value.trim().length < 2) {
                  return 'Введите имя';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: const [RussianPhoneInputFormatter()],
              decoration: const InputDecoration(labelText: 'Телефон'),
            ),
            const SizedBox(height: 12),
            AddressAutocompleteField(
              controller: _address,
              labelText: 'Адрес объекта',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Комментарии'),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
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
            ),
          ],
        ),
      ),
    );
  }

  void _hydrate(ClientModel client) {
    if (!mounted || _hydrated) return;
    setState(() {
      _hydrated = true;
      _name.text = client.name;
      _phone.text = RussianPhoneInputFormatter.format(client.phone ?? '');
      _address.text = client.objectAddress ?? '';
      _notes.text = client.notes ?? '';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .saveClient(
            id: widget.clientId,
            name: _name.text,
            phone: _phone.text,
            objectAddress: _address.text,
            notes: _notes.text,
          );
      ref.invalidate(clientsProvider);
      if (!mounted) return;
      context.go('/clients');
    } catch (error) {
      if (!mounted) return;
      if (error.toString().contains('Лимит базового тарифа')) {
        showUpgradeSheet(
          context: context,
          message: error.toString().replaceFirst('Exception: ', ''),
          onOpenPlans: () => context.go('/settings'),
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
