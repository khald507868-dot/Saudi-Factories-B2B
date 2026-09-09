// ============================================================
//  السلة — مقابل app-cart.html
//
//  الكتابة متفائلة مع مصالحة من الخادم: زرّا − و + يعيدان
//  الرسم فوراً، ثم يُرسَل تعديل واحد بعد 400 مللي لدفعة
//  الضغطات. وإن رفض الخادم، يُعاد التحميل منه — فهو المرجع.
//
//  الحذف غير مؤجَّل: لا رجعة فيه فيُنفَّذ فوراً.
//
//  المجموع يُحسب في الخادم عند إنشاء الطلب؛ ما يظهر هنا عرض
//  فقط. الدفع يدوي بقرار المالك — لا بوابة دفع في التطبيق.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/currency.dart';
import '../core/i18n.dart';
import '../core/pricing.dart';
import '../core/theme.dart';
import '../core/uuid.dart';
import '../services/auth_service.dart';
import '../services/commerce_service.dart';
import '../widgets/common.dart';
import '../widgets/price_text.dart';
import 'auth_page.dart';
import 'shell.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => CartPageState();
}

class CartPageState extends State<CartPage> {
  final String? _sessionUser = AuthService.instance.user?.id;

  Future<void> refresh() => _refresh();
  List<CartItem> _items = [];
  bool _loading = true;
  bool _ordering = false;
  Object? _error;
  String? _checkoutIdempotencyKey;

  /// تعديلات كمية بانتظار الإرسال — تُدفع قبل إنشاء الطلب.
  final Map<int, int> _pending = {};
  Timer? _debounce;
  Future<bool>? _flushInFlight;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_flush());
    super.dispose();
  }

  Future<void> _load() async {
    if (!AuthService.instance.isSignedIn) {
      setState(() {
        _items = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final items = await SFCommerce.loadCart();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  SFOrderEstimate get _estimate => SFOrderEstimate(
    _items.fold<double>(
      0,
      (sum, i) => sum + SFCurrency.instance.lineAmount(i.unitPrice, i.quantity),
    ),
  );

  Future<void> _refresh() async {
    _debounce?.cancel();
    if (await _flush() && mounted) await _load();
  }

  void _changeQuantity(CartItem item, int delta) {
    _setQuantity(item, item.quantity + delta);
  }

  void _setQuantity(CartItem item, int next) {
    if (_ordering || next < 1 || next > 100000) return;

    setState(() {
      _items = _items
          .map((i) => i.id == item.id ? i.copyWith(quantity: next) : i)
          .toList();
      _pending[item.id] = next;
      _checkoutIdempotencyKey = null;
    });

    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_flush()),
    );
  }

  /// يرسل التعديلات المؤجّلة؛ عند الرفض يُعاد التحميل من الخادم.
  Future<bool> _flush() {
    final running = _flushInFlight;
    if (running != null) {
      return running.then((ok) => ok ? _flush() : false);
    }
    if (_pending.isEmpty) return Future<bool>.value(true);

    final batch = Map<int, int>.from(_pending);
    _pending.clear();

    final operation = _sendQuantityBatch(batch);
    late final Future<bool> tracked;
    tracked = operation.whenComplete(() {
      if (identical(_flushInFlight, tracked)) _flushInFlight = null;
    });
    _flushInFlight = tracked;
    return tracked.then((ok) => ok ? _flush() : false);
  }

  Future<bool> _sendQuantityBatch(Map<int, int> batch) async {
    if (AuthService.instance.user?.id != _sessionUser) return false;
    try {
      for (final entry in batch.entries) {
        if (AuthService.instance.user?.id != _sessionUser) return false;
        await SFCommerce.setQuantity(entry.key, entry.value);
      }
      if (mounted) AppShell.of(context)?.refreshCounters();
      return true;
    } catch (e) {
      _pending.clear();
      if (mounted) {
        showSFError(context, e);
        await _load();
      }
      return false;
    }
  }

  Future<void> _remove(CartItem item) async {
    if (_ordering) return;
    _pending.remove(item.id);
    _checkoutIdempotencyKey = null;
    setState(() => _items = _items.where((i) => i.id != item.id).toList());
    try {
      final running = _flushInFlight;
      if (running != null) await running;
      await SFCommerce.removeItem(item.id);
      if (mounted) AppShell.of(context)?.refreshCounters();
    } catch (e) {
      if (!mounted) return;
      showSFError(context, e);
      await _load();
    }
  }

  Future<void> _checkout() async {
    if (_items.isEmpty) return;

    // الخادم يرفض خلط مصنعين في طلب واحد، فنتحقّق قبل الإرسال.
    final factoryIds = _items.map((i) => i.factoryId).toSet();
    if (factoryIds.length > 1) {
      showSFError(context, Exception(context.t('cart_one_factory')));
      return;
    }
    final factoryId = factoryIds.first;
    if (factoryId == null) return;

    setState(() => _ordering = true);
    try {
      // تُدفع التعديلات المؤجّلة أولاً حتى لا يُبنى الطلب على
      // كمية لم يرها الخادم بعد.
      _debounce?.cancel();
      if (!await _flush()) return;
      final idempotencyKey = _checkoutIdempotencyKey ??= newUuidV4();
      await SFCommerce.createOrder(factoryId, idempotencyKey: idempotencyKey);
      _checkoutIdempotencyKey = null;
      if (!mounted) return;
      showSFMessage(context, context.t('cart_order_sent'));
      await _load();
      if (mounted) AppShell.of(context)?.refreshCounters();
    } catch (e) {
      if (!mounted) return;
      showSFError(context, e);
    } finally {
      if (mounted) setState(() => _ordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    if (!AuthService.instance.isSignedIn) {
      return Scaffold(
        backgroundColor: SFColors.pageBg,
        appBar: SFTopBar(title: i18n.t('cart_page_heading')),
        body: SFStateView(
          message: i18n.t('login_required_action'),
          icon: Icons.lock_outline,
          retryLabel: context.t('splash_login_btn'),
          onRetry: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AuthPage(accountType: 'individual'),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(title: i18n.t('cart_page_heading')),
      body: _buildBody(i18n),
      bottomNavigationBar: _items.isEmpty || _loading || _error != null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: SFColors.white,
                  border: Border(top: BorderSide(color: SFColors.border)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            i18n.t('cart_total_label'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: SFPriceText(
                            SFCurrency.instance.format(_estimate.total),
                            textAlign:
                                Directionality.of(context) == TextDirection.rtl
                                ? TextAlign.left
                                : TextAlign.right,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: SFColors.midGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _ordering ? null : _checkout,
                      child: _ordering
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: SFColors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(i18n.t('cart_checkout_btn')),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBody(I18n i18n) {
    if (_loading) {
      return SFStateView(message: i18n.t('fx_loading'), loading: true);
    }
    if (_error != null) {
      return SFStateView(
        message: i18n.t('fx_failed'),
        icon: Icons.cloud_off,
        onRetry: _load,
      );
    }
    if (_items.isEmpty) {
      return SFStateView(
        message: i18n.t('cart_empty_title'),
        icon: Icons.shopping_cart_outlined,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: SFColors.midGreen,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == _items.length) return _buildSummary(i18n);
          final item = _items[i];
          return _CartRow(
            key: ValueKey(item.id),
            item: item,
            enabled: !_ordering,
            onIncrement: () => _changeQuantity(item, 1),
            onDecrement: () => _changeQuantity(item, -1),
            onQuantityChanged: (value) => _setQuantity(item, value),
            onRemove: () => _remove(item),
          );
        },
      ),
    );
  }

  Widget _buildSummary(I18n i18n) {
    final estimate = _estimate;
    final entries = {
      'order_subtotal': estimate.subtotal,
      'order_shipping': estimate.shipping,
      'order_payment_fee': estimate.paymentFee,
      'order_vat': estimate.vat,
      'cart_total_label': estimate.total,
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              i18n.t('app_order_details'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 16),
            for (final entry in entries.entries) ...[
              if (entry.key == 'cart_total_label') const Divider(height: 20),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        i18n.t(entry.key),
                        style: TextStyle(
                          fontSize: 13,
                          color: entry.key == 'cart_total_label'
                              ? SFColors.darkGreen
                              : SFColors.muted2,
                          fontWeight: entry.key == 'cart_total_label'
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: SFPriceText(
                        SFCurrency.instance.format(entry.value),
                        textAlign:
                            Directionality.of(context) == TextDirection.rtl
                            ? TextAlign.left
                            : TextAlign.right,
                        style: TextStyle(
                          fontSize: entry.key == 'cart_total_label' ? 16 : 13,
                          fontWeight: FontWeight.w700,
                          color: entry.key == 'cart_total_label'
                              ? SFColors.midGreen
                              : SFColors.darkGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Text(
              i18n.t('order_estimate_note'),
              style: const TextStyle(color: SFColors.muted2, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: SFColors.softGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    i18n.t('app_order_manual_payment'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: SFColors.muted2,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            if (_items.map((item) => item.factoryId).toSet().length > 1) ...[
              const SizedBox(height: 12),
              Text(
                i18n.t('cart_one_factory'),
                style: const TextStyle(color: SFColors.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CartRow extends StatefulWidget {
  const _CartRow({
    super.key,
    required this.item,
    required this.enabled,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onQuantityChanged,
  });

  final CartItem item;
  final bool enabled;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final ValueChanged<int> onQuantityChanged;

  @override
  State<_CartRow> createState() => _CartRowState();
}

class _CartRowState extends State<_CartRow> {
  late final TextEditingController _quantity = TextEditingController(
    text: '${widget.item.quantity}',
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_commitOnBlur);
  }

  void _commitOnBlur() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final number = int.tryParse(_quantity.text);
    if (number == null || number < 1 || number > 100000) {
      _quantity.text = '${widget.item.quantity}';
      return;
    }
    widget.onQuantityChanged(number);
  }

  @override
  void didUpdateWidget(covariant _CartRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.quantity != widget.item.quantity) {
      _quantity.text = '${widget.item.quantity}';
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_commitOnBlur);
    _focus.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SFColors.white,
        border: Border.all(color: SFColors.border),
        borderRadius: BorderRadius.circular(SFMetrics.radius),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SFImage(url: item.image, width: 64, height: 64, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    if (item.factoryName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.factoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SFColors.muted2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SFPriceText(
                          SFCurrency.instance.format(item.unitPrice),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SFColors.midGreen,
                          ),
                        ),
                        Text(
                          context.t('cart_per_unit'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: SFColors.muted2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.t('cart_remove'),
                onPressed: widget.enabled ? widget.onRemove : null,
                icon: const Icon(
                  Icons.delete_outline,
                  color: SFColors.danger,
                  size: 20,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const Divider(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final quantity = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('prod_quantity'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: SFColors.muted2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(
                      color: SFColors.pageBg,
                      border: Border.all(color: SFColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _QtyButton(
                          icon: Icons.remove,
                          onTap: widget.enabled && item.quantity > 1
                              ? widget.onDecrement
                              : null,
                        ),
                        SizedBox(
                          width: 62,
                          child: Semantics(
                            label: context.t('prod_quantity'),
                            child: TextField(
                              controller: _quantity,
                              focusNode: _focus,
                              enabled: widget.enabled,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              decoration: const InputDecoration(
                                isDense: true,
                                filled: false,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                              ),
                              onChanged: (text) {
                                final value = int.tryParse(text);
                                if (value != null &&
                                    value > 0 &&
                                    value <= 100000) {
                                  widget.onQuantityChanged(value);
                                }
                              },
                              onSubmitted: (_) => _commit(),
                            ),
                          ),
                        ),
                        _QtyButton(
                          icon: Icons.add,
                          onTap: widget.enabled && item.quantity < 100000
                              ? widget.onIncrement
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final amount = Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    context.t('cart_total_label'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: SFColors.muted2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SFPriceText(
                    SFCurrency.instance.format(
                      SFCurrency.instance.lineAmount(
                        item.unitPrice,
                        item.quantity,
                      ),
                    ),
                    textAlign: Directionality.of(context) == TextDirection.rtl
                        ? TextAlign.left
                        : TextAlign.right,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: SFColors.midGreen,
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < 300) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    quantity,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.t('cart_total_label'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: SFColors.muted2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: SFPriceText(
                            SFCurrency.instance.format(
                              SFCurrency.instance.lineAmount(
                                item.unitPrice,
                                item.quantity,
                              ),
                            ),
                            textAlign:
                                Directionality.of(context) == TextDirection.rtl
                                ? TextAlign.left
                                : TextAlign.right,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: SFColors.midGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  quantity,
                  const SizedBox(width: 12),
                  Expanded(child: amount),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      color: SFColors.midGreen,
      disabledColor: SFColors.muted,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.standard,
    );
  }
}
