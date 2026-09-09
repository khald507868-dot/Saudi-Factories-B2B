import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../core/currency.dart';
import '../services/orders_service.dart';
import '../widgets/common.dart';
import '../widgets/price_text.dart';
import 'invoice_page.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({
    super.key,
    this.initialView = OrderView.all,
    this.invoicesOnly = false,
  });

  final OrderView initialView;
  final bool invoicesOnly;

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  List<SFOrder> _orders = [];
  Set<int> _ownedFactories = {};
  final Set<String> _confirming = {};
  late OrderView _view;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        SFOrders.load(invoicesOnly: widget.invoicesOnly),
        // فشل التحقق من الملكية يخفي إجراء الدفع، ولا يخفي سجل الطلبات.
        SFOrders.ownedFactoryIds().catchError((_) => <int>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = results[0] as List<SFOrder>;
        _ownedFactories = results[1] as Set<int>;
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

  Future<void> _confirm(SFOrder order) async {
    if (_confirming.contains(order.id)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.t('order_mark_paid')),
        content: Text(context.t('order_mark_paid_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.t('msg_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.t('order_mark_paid')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _confirming.add(order.id));
    try {
      await SFOrders.confirmPayment(order.id);
      if (!mounted) return;
      showSFMessage(context, context.t('order_mark_paid_done'));
      // الخادم هو مصدر الحالة بعد الإجراء، حتى لو تغيّر الطلب في جلسة ثانية.
      await _load();
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _confirming.remove(order.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _orders.where((order) => order.matches(_view)).toList();
    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(
        title: context.t(
          widget.invoicesOnly ? 'row_invoices' : 'dash_my_orders',
        ),
        showBack: true,
      ),
      body: _loading
          ? SFStateView(message: context.t('fx_loading'), loading: true)
          : _error != null
          ? SFStateView(
              message: context.t('app_load_error'),
              icon: Icons.wifi_off_outlined,
              onRetry: _load,
              retryLabel: context.t('app_retry'),
            )
          : Column(
              children: [
                if (!widget.invoicesOnly)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        for (final view in OrderView.values)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: ChoiceChip(
                              label: Text(
                                context.t(switch (view) {
                                  OrderView.all => 'app_orders_all',
                                  OrderView.paid => 'app_order_paid',
                                  OrderView.unpaid => 'dash_orders_unpaid',
                                }),
                              ),
                              selected: _view == view,
                              onSelected: (_) => setState(() => _view = view),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (visible.isEmpty)
                          SFStateView(
                            message: context.t(
                              widget.invoicesOnly
                                  ? 'inv_empty'
                                  : 'app_orders_empty',
                            ),
                            icon: widget.invoicesOnly
                                ? Icons.receipt_long_outlined
                                : Icons.inventory_2_outlined,
                          ),
                        for (final order in visible) _card(order),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _card(SFOrder order) {
    final canConfirm = order.canConfirmPayment(
      _ownedFactories,
      isAdmin: AuthService.instance.profile?.isAdmin == true,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.factoryName.isEmpty ? '—' : order.factoryName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OrderStatusBadge(order: order),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${context.t('order_number')}: ${order.shortId}',
              style: const TextStyle(fontSize: 12, color: SFColors.muted2),
            ),
            if (order.createdAt != null)
              Text(
                DateFormat.yMd(context.i18n.dateLocale)
                    .format(order.createdAt!.toLocal()),
                style: const TextStyle(fontSize: 12, color: SFColors.muted2),
              ),
            const Divider(height: 24),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(item.name)),
                    const SizedBox(width: 8),
                    Text('×${item.quantityLabel}'),
                    const SizedBox(width: 12),
                    Flexible(
                      child: SFPriceText(
                        SFCurrency.formatSar(item.lineTotal),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            OrderAmounts(order: order, useStoredCurrency: true),
            if (order.isUnpaid && !canConfirm) ...[
              const SizedBox(height: 12),
              Text(
                context.t('app_order_manual_payment'),
                style: const TextStyle(color: SFColors.muted2, fontSize: 12),
              ),
            ],
            if (canConfirm) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _confirming.contains(order.id)
                      ? null
                      : () => _confirm(order),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(context.t('order_mark_paid')),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InvoicePage(orderId: order.id),
                  ),
                ),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(
                  context.t(
                    order.hasInvoice ? 'app_invoice_open' : 'app_order_details',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
