import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:qr_flutter/qr_flutter.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/currency.dart';
import '../services/orders_service.dart';
import '../widgets/common.dart';
import '../widgets/price_text.dart';

class InvoicePage extends StatefulWidget {
  const InvoicePage({super.key, required this.orderId});

  final String orderId;

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  SFOrder? _order;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await SFOrders.get(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _copyReference() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.orderId));
      if (mounted) showSFMessage(context, context.t('app_reference_copied'));
    } catch (error) {
      if (mounted) showSFError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(
        title: context.t(
          order?.hasInvoice == true ? 'app_invoice_title' : 'app_order_details',
        ),
        showBack: true,
      ),
      body: _loading
          ? SFStateView(message: context.t('fx_loading'), loading: true)
          : _error != null
          ? SFStateView(
              message: context.t('app_load_error'),
              onRetry: _load,
              retryLabel: context.t('app_retry'),
            )
          : order == null
          ? SFStateView(
              message: context.t('inv_not_found'),
              icon: Icons.receipt_long_outlined,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.factoryName.isEmpty ? '—' : order.factoryName,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OrderStatusBadge(order: order),
                          const SizedBox(height: 20),
                          Text(
                            context.t('order_number'),
                            style: const TextStyle(color: SFColors.muted2),
                          ),
                          SelectableText(
                            order.id,
                            textDirection: TextDirection.ltr,
                          ),
                          if (order.createdAt != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              context.t('inv_invoice_date'),
                              style: const TextStyle(color: SFColors.muted2),
                            ),
                            Text(
                              DateFormat.yMd(context.i18n.dateLocale)
                                  .add_Hm()
                                  .format(order.createdAt!.toLocal()),
                            ),
                          ],
                          const Divider(height: 32),
                          Text(
                            context.t('order_items_label'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          for (final item in order.items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(item.name),
                                        SFPriceText(
                                          '${item.quantityLabel} × ${_storedMoney(item.unitPrice, order.currency)}',
                                          style: const TextStyle(
                                            color: SFColors.muted2,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: SFPriceText(
                                      _storedMoney(
                                        item.lineTotal,
                                        order.currency,
                                      ),
                                      textAlign: TextAlign.end,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Divider(),
                          // الفاتورة تبقى بعملة الطلب المثبتة؛ تبديل عملة العرض لا يغيّرها.
                          OrderAmounts(order: order, useStoredCurrency: true),
                          const SizedBox(height: 24),
                          Center(
                            child: Column(
                              children: [
                                Text(
                                  context.t('app_order_reference_qr'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Semantics(
                                  label:
                                      '${context.t('app_order_reference_qr')}: ${order.id}',
                                  child: QrImageView(
                                    data: order.referencePayload,
                                    version: QrVersions.auto,
                                    size: 190,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _copyReference,
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(context.t('app_copy_order_reference')),
                  ),
                ],
              ),
            ),
    );
  }
}

String _storedMoney(double value, String currency) => currency == 'SAR'
    ? SFCurrency.formatSar(value)
    : '${value.toStringAsFixed(2)} $currency';

class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({super.key, required this.order});
  final SFOrder order;

  @override
  Widget build(BuildContext context) => SFStatusChip(
    status: order.isPaid
        ? 'approved'
        : order.isUnpaid
        ? 'pending'
        : 'rejected',
    label: context.t(order.statusKey),
  );
}

class OrderAmounts extends StatelessWidget {
  const OrderAmounts({
    super.key,
    required this.order,
    this.useStoredCurrency = false,
  });

  final SFOrder order;
  final bool useStoredCurrency;

  @override
  Widget build(BuildContext context) {
    String money(double amount) => useStoredCurrency
        ? _storedMoney(amount, order.currency)
        : SFCurrency.instance.format(amount);

    Widget line(String label, double amount, {bool total = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: total ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: SFPriceText(
              money(amount),
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: total ? FontWeight.w800 : FontWeight.w600,
                color: total ? SFColors.midGreen : SFColors.darkGreen,
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      children: [
        line(context.t('order_subtotal'), order.subtotal),
        if (order.shipping > 0)
          line(context.t('order_shipping'), order.shipping),
        if (order.paymentFee > 0)
          line(context.t('order_payment_fee'), order.paymentFee),
        line(
          '${context.t('inv_vat_rate')} (${(order.vatRate * 100).toStringAsFixed(1)}%)',
          order.vatAmount,
        ),
        line(context.t('cart_total_label'), order.total, total: true),
      ],
    );
  }
}
