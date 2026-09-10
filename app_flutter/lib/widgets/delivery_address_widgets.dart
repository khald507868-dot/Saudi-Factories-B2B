import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../pages/delivery_address_page.dart';
import '../pages/delivery_location_page.dart';
import '../services/delivery_address_service.dart';
import '../services/delivery_location_service.dart';
import 'common.dart';

/// عنوان التوصيل المختار يفتح قائمة العناوين من أعلى الرئيسية.
class DeliveryAddressHeader extends StatefulWidget {
  const DeliveryAddressHeader({super.key, this.service});

  final DeliveryAddressService? service;

  @override
  State<DeliveryAddressHeader> createState() => _DeliveryAddressHeaderState();
}

class _DeliveryAddressHeaderState extends State<DeliveryAddressHeader> {
  DeliveryAddressService get _service =>
      widget.service ?? DeliveryAddressService.instance;

  @override
  void initState() {
    super.initState();
    _service.start();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _service,
    builder: (context, _) {
      final selected = _service.selected;
      return SizedBox(
        width: double.infinity,
        child: Semantics(
          button: true,
          label:
              '${context.t('delivery_choose')}. '
              '${selected?.label ?? ''} ${selected?.addressLine ?? ''}',
          child: InkWell(
            key: const ValueKey('delivery-address-trigger'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => showDeliveryAddresses(context, service: _service),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 19,
                        color: SFColors.midGreen,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          selected?.label ?? context.t('delivery_choose'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                            color: SFColors.darkGreen,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: SFColors.darkGreen,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    selected?.addressLine ?? context.t('delivery_empty'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      fontWeight: FontWeight.w400,
                      color: SFColors.muted2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<void> showDeliveryAddresses(
  BuildContext context, {
  DeliveryAddressService? service,
}) async {
  final addresses = service ?? DeliveryAddressService.instance;
  addresses.start();
  // تعكس إعادة الفتح أي تغيير أجراه الحساب من جهاز آخر.
  if (!addresses.isLoading) addresses.reload();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SFColors.white,
    clipBehavior: Clip.antiAlias,
    constraints: const BoxConstraints(maxWidth: 430),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => DeliveryAddressSheet(service: addresses),
  );
}

class DeliveryAddressSheet extends StatefulWidget {
  const DeliveryAddressSheet({super.key, required this.service});

  final DeliveryAddressService service;

  @override
  State<DeliveryAddressSheet> createState() => _DeliveryAddressSheetState();
}

class _DeliveryAddressSheetState extends State<DeliveryAddressSheet> {
  bool _busy = false;

  Future<void> _edit([DeliveryAddress? address]) async {
    if (_busy) return;
    final scope = widget.service.userId;
    setState(() => _busy = true);
    try {
      DeliveryAddress? saved;
      if (address != null) {
        saved = await Navigator.of(context).push<DeliveryAddress>(
          MaterialPageRoute(
            builder: (_) =>
                DeliveryAddressPage(existing: address, service: widget.service),
          ),
        );
      } else {
        final location = await Navigator.of(context).push<DeliveryLocation>(
          MaterialPageRoute(builder: (_) => const DeliveryLocationPage()),
        );
        if (!mounted || location == null) return;
        if (scope != widget.service.userId) return;
        saved = await Navigator.of(context).push<DeliveryAddress>(
          MaterialPageRoute(
            builder: (_) => DeliveryAddressPage(
              location: location,
              service: widget.service,
            ),
          ),
        );
      }
      if (mounted &&
          saved != null &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(DeliveryAddress address) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.select(address.id);
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) showSFMessage(context, context.t('delivery_sync_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final service = widget.service;
      return SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.t('delivery_choose'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (service.isGuest)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    context.t('delivery_local_hint'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: SFColors.muted2,
                    ),
                  ),
                ),
              if (service.isLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (service.error != null)
                Expanded(
                  child: SFStateView(
                    message: context.t('delivery_load_failed'),
                    icon: Icons.cloud_off_outlined,
                    onRetry: service.reload,
                  ),
                )
              else if (service.addresses.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.add_location_alt_outlined,
                            size: 42,
                            color: SFColors.midGreen,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.t('delivery_empty'),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: service.addresses.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final address = service.addresses[index];
                      final selected = service.selected?.id == address.id;
                      return ListTile(
                        key: ValueKey('delivery-address-${address.id}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        onTap: _busy ? null : () => _select(address),
                        selected: selected,
                        selectedTileColor: SFColors.surfaceAlt,
                        leading: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.location_on_outlined,
                          color: selected
                              ? SFColors.midGreen
                              : SFColors.darkGreen,
                          semanticLabel: selected
                              ? context.t('delivery_selected')
                              : null,
                        ),
                        title: Text(
                          address.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            address.addressLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: _busy ? null : () => _edit(address),
                          child: Text(context.t('delivery_edit')),
                        ),
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey('delivery-add-address'),
                    onPressed: _busy || service.isLoading
                        ? null
                        : () => _edit(),
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_circle_outline),
                    label: Text(context.t('delivery_add')),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      backgroundColor: SFColors.surfaceAlt,
                      side: const BorderSide(color: SFColors.border),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
