import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/uuid.dart';
import '../services/delivery_address_service.dart';
import '../services/delivery_location_service.dart';
import '../widgets/common.dart';
import 'delivery_location_page.dart';

/// تفاصيل العنوان بعد تأكيد النقطة على الخريطة، أو عند تعديل عنوان محفوظ.
class DeliveryAddressPage extends StatefulWidget {
  const DeliveryAddressPage({
    super.key,
    required this.service,
    this.location,
    this.existing,
  }) : assert(location != null || existing != null);

  final DeliveryAddressService service;
  final DeliveryLocation? location;
  final DeliveryAddress? existing;

  @override
  State<DeliveryAddressPage> createState() => _DeliveryAddressPageState();
}

class _DeliveryAddressPageState extends State<DeliveryAddressPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _address;
  late final TextEditingController _building;
  late final TextEditingController _floor;
  late final TextEditingController _apartment;
  late final TextEditingController _notes;
  late final String _id;
  late final String? _userId;
  late DeliveryLocation _location;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _userId = widget.service.userId;
    _id = existing?.id ?? newUuidV4();
    _location =
        widget.location ??
        DeliveryLocation(
          latitude: existing!.latitude,
          longitude: existing.longitude,
          addressLine: existing.addressLine,
          title: existing.label,
        );
    _label = TextEditingController(text: existing?.label ?? '');
    _address = TextEditingController(
      text: existing?.addressLine ?? _location.addressLine,
    );
    _building = TextEditingController(text: existing?.building ?? '');
    _floor = TextEditingController(text: existing?.floor ?? '');
    _apartment = TextEditingController(text: existing?.apartment ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    widget.service.addListener(_accountChanged);
  }

  void _accountChanged() {
    if (mounted && !_sameAccount) setState(() {});
  }

  @override
  void dispose() {
    widget.service.removeListener(_accountChanged);
    for (final controller in [
      _label,
      _address,
      _building,
      _floor,
      _apartment,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _sameAccount => widget.service.userId == _userId;

  Future<void> _changeLocation() async {
    final location = await Navigator.of(context).push<DeliveryLocation>(
      MaterialPageRoute(
        builder: (_) => DeliveryLocationPage(initialLocation: _location),
      ),
    );
    if (!mounted || location == null) return;
    setState(() {
      _location = location;
      // لا نحتفظ بعنوان الشارع القديم عند نقل الدبوس إلى موقع جديد.
      _address.text = location.addressLine;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (!_sameAccount) {
      setState(() => _error = context.t('delivery_sync_failed'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final address = DeliveryAddress(
        id: _id,
        label: _label.text.trim(),
        addressLine: _address.text.trim(),
        latitude: _location.latitude,
        longitude: _location.longitude,
        building: _building.text.trim(),
        floor: _floor.text.trim(),
        apartment: _apartment.text.trim(),
        notes: _notes.text.trim(),
      );
      await widget.service.save(address);
      if (!mounted) return;
      setState(() => _busy = false);
      // يصبح الرجوع مسموحاً بعد تحديث PopScope في إطار الرسم التالي.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop(address);
    } catch (error) {
      if (!mounted) return;
      final key =
          error is DeliveryAddressException &&
              error.code == 'delivery_address_limit'
          ? 'delivery_limit'
          : 'delivery_save_failed';
      setState(() {
        _busy = false;
        _error = context.t(key);
      });
    }
  }

  Future<void> _delete() async {
    if (_busy || widget.existing == null || !_sameAccount) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.t('delivery_delete')),
        content: Text(context.t('delivery_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.t('msg_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: SFColors.danger),
            child: Text(context.t('delivery_delete')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || !_sameAccount) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.remove(_id);
      if (!mounted) return;
      setState(() => _busy = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.t('delivery_sync_failed');
        });
      }
    }
  }

  Widget _field(
    String key,
    TextEditingController controller, {
    bool required = false,
    int maxLength = 60,
    int lines = 1,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      enabled: !_busy,
      minLines: lines,
      maxLines: lines,
      maxLength: maxLength,
      textInputAction: lines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      decoration: InputDecoration(
        labelText: context.t(key),
        hintText: hint == null ? null : context.t(hint),
        counterText: '',
      ),
      validator: (value) {
        final text = (value ?? '').trim();
        if (required && text.isEmpty) return context.t('delivery_required');
        if (text.runes.length > maxLength) {
          return context
              .t('delivery_max_length')
              .replaceAll('{count}', '$maxLength');
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: SFTopBar(title: context.t('delivery_details'), showBack: true),
      body: !_sameAccount
          ? SFStateView(message: context.t('delivery_sync_failed'))
          : SafeArea(
              top: false,
              child: Form(
                key: _form,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: SFColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: SFColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  color: SFColors.midGreen,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    context.t('delivery_location'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_location.latitude.toStringAsFixed(5)}, '
                              '${_location.longitude.toStringAsFixed(5)}',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontSize: 12,
                                color: SFColors.muted2,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _busy ? null : _changeLocation,
                              icon: const Icon(
                                Icons.edit_location_alt_outlined,
                                size: 18,
                              ),
                              label: Text(
                                context.t('delivery_change_location'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _field(
                        'delivery_label',
                        _label,
                        required: true,
                        hint: 'delivery_label_hint',
                      ),
                      _field(
                        'delivery_address',
                        _address,
                        required: true,
                        maxLength: 500,
                        lines: 3,
                      ),
                      _field('delivery_building', _building, maxLength: 80),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _field(
                              'delivery_floor',
                              _floor,
                              maxLength: 40,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              'delivery_apartment',
                              _apartment,
                              maxLength: 40,
                            ),
                          ),
                        ],
                      ),
                      _field(
                        'delivery_notes',
                        _notes,
                        maxLength: 500,
                        lines: 2,
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: SFColors.danger),
                          ),
                        ),
                      FilledButton(
                        key: const ValueKey('delivery-save-address'),
                        onPressed: _busy ? null : _save,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 50),
                        ),
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(context.t('delivery_save')),
                      ),
                      if (widget.existing != null) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _busy ? null : _delete,
                          style: TextButton.styleFrom(
                            foregroundColor: SFColors.danger,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(context.t('delivery_delete')),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
    ),
  );
}
