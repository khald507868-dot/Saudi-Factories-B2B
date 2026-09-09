import 'dart:convert';

import '../core/supabase_config.dart';
import 'auth_service.dart';

enum OrderView { all, paid, unpaid }

double _amount(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

class SFOrderItem {
  SFOrderItem.fromRow(Map<String, dynamic> row)
    : name = '${row['product_name'] ?? ''}',
      unitPrice = _amount(row['unit_price']),
      quantity = _amount(row['quantity']),
      lineTotal = _amount(row['line_total']);

  final String name;
  final double unitPrice;
  final double quantity;
  // القيمة المثبتة وقت الطلب، لا سعر المنتج الحالي أو حاصل ضرب محلي.
  final double lineTotal;

  String get quantityLabel => quantity == quantity.roundToDouble()
      ? quantity.toInt().toString()
      : quantity.toString();
}

class SFOrder {
  SFOrder.fromRow(Map<String, dynamic> row)
    : id = '${row['id'] ?? ''}',
      buyerId = '${row['buyer_id'] ?? ''}',
      factoryId = (row['factory_id'] as num?)?.toInt() ?? 0,
      factoryName = row['factories'] is Map
          ? '${row['factories']['name'] ?? ''}'
          : '',
      status = '${row['status'] ?? 'pending'}',
      currency = '${row['currency'] ?? 'SAR'}',
      createdAt = DateTime.tryParse('${row['created_at'] ?? ''}'),
      subtotal = _amount(row['subtotal']),
      shipping = _amount(row['shipping']),
      paymentFee = _amount(row['payment_fee']),
      vatRate = _amount(row['vat_rate']),
      vatAmount = _amount(row['vat_amount']),
      total = _amount(row['total']),
      items = (row['order_items'] as List? ?? []).map((item) {
        return SFOrderItem.fromRow(Map<String, dynamic>.from(item as Map));
      }).toList();

  final String id;
  final String buyerId;
  final int factoryId;
  final String factoryName;
  final String status;
  final String currency;
  final DateTime? createdAt;
  final double subtotal;
  final double shipping;
  final double paymentFee;
  final double vatRate;
  final double vatAmount;
  final double total;
  final List<SFOrderItem> items;

  static const paidStatuses = {'paid', 'processing', 'shipped', 'completed'};
  static const unpaidStatuses = {'pending', 'awaiting_payment'};
  static const invoiceStatuses = {'paid', 'completed'};

  bool get isPaid => paidStatuses.contains(status);
  bool get isUnpaid => unpaidStatuses.contains(status);
  bool get hasInvoice => invoiceStatuses.contains(status);
  String get shortId => id.split('-').first.toUpperCase();
  String get statusKey => switch (status) {
    'paid' => 'app_order_paid',
    'processing' => 'app_order_processing',
    'shipped' => 'app_order_shipped',
    'completed' => 'app_order_completed',
    'cancelled' => 'app_order_cancelled',
    'payment_failed' => 'app_order_payment_failed',
    _ => 'app_order_pending',
  };

  bool canConfirmPayment(Set<int> ownedFactoryIds, {bool isAdmin = false}) =>
      isUnpaid && (isAdmin || ownedFactoryIds.contains(factoryId));

  bool matches(OrderView view) => switch (view) {
    OrderView.all => true,
    OrderView.paid => isPaid,
    OrderView.unpaid => isUnpaid,
  };

  // رمز مرجعي للطلب؛ لا يدّعي أنه رمز فاتورة ضريبية معتمد.
  String get referencePayload => jsonEncode({
    'type': 'order_reference',
    'order_id': id,
    'seller': factoryName,
    'created_at': createdAt?.toUtc().toIso8601String(),
    'currency': currency,
    'total': total.toStringAsFixed(2),
    'vat_amount': vatAmount.toStringAsFixed(2),
  });
}

class SFRevenueDay {
  const SFRevenueDay(this.day, this.total);
  final DateTime day;
  final double total;
}

class SFSellerStats {
  SFSellerStats.fromOrders(List<SFOrder> orders, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toLocal();
    final today = DateTime(current.year, current.month, current.day);
    for (var index = 13; index >= 0; index--) {
      final day = DateTime(today.year, today.month, today.day - index);
      var sum = 0.0;
      for (final order in orders) {
        final created = order.createdAt?.toLocal();
        if (order.isPaid &&
            created != null &&
            created.year == day.year &&
            created.month == day.month &&
            created.day == day.day) {
          sum += order.total;
        }
      }
      days.add(SFRevenueDay(day, sum));
    }
    for (final order in orders) {
      if (order.isPaid) {
        paidCount++;
        paidTotal += order.total;
      } else if (order.isUnpaid) {
        pendingTotal += order.total;
      }
    }
  }

  int paidCount = 0;
  double paidTotal = 0;
  double pendingTotal = 0;
  final List<SFRevenueDay> days = [];
}

class SFOrders {
  SFOrders._();

  static const _select =
      'id, buyer_id, factory_id, status, currency, '
      'subtotal, shipping, payment_fee, vat_rate, vat_amount, total, created_at, '
      'factories(name), order_items(product_name, unit_price, quantity, line_total)';

  static String get _uid {
    final id = AuthService.instance.user?.id;
    if (id == null) throw Exception('يجب تسجيل الدخول أولاً');
    return id;
  }

  static Future<List<SFOrder>> load({
    OrderView view = OrderView.all,
    bool invoicesOnly = false,
    Set<int>? factoryIds,
  }) async {
    _uid;
    if (factoryIds?.isEmpty == true) return [];
    final orders = <SFOrder>[];
    for (var start = 0; ; start += 500) {
      // RLS تعرض طلبات المشتري وطلبات مصانع البائع والمدير وفق صلاحياته.
      var query = sb.from('orders').select(_select);
      if (factoryIds != null) {
        query = query.inFilter('factory_id', factoryIds.toList());
      }
      if (invoicesOnly) {
        query = query.inFilter('status', SFOrder.invoiceStatuses.toList());
      } else if (view == OrderView.paid) {
        query = query.inFilter('status', SFOrder.paidStatuses.toList());
      } else if (view == OrderView.unpaid) {
        query = query.inFilter('status', SFOrder.unpaidStatuses.toList());
      }
      final rows = await query
          .order('created_at', ascending: false)
          .order('id')
          .range(start, start + 499);
      orders.addAll(rows.map(SFOrder.fromRow));
      if (rows.length < 500) return orders;
    }
  }

  static Future<SFOrder?> get(String id) async {
    _uid;
    final row = await sb
        .from('orders')
        .select(_select)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : SFOrder.fromRow(row);
  }

  static Future<Set<int>> ownedFactoryIds() async {
    final uid = _uid;
    final rows = await sb.from('factories').select('id').eq('owner_id', uid);
    return rows.map((row) => (row['id'] as num).toInt()).toSet();
  }

  static Future<void> confirmPayment(String orderId) async {
    _uid;
    // الخادم يتحقق من المالك والحالة؛ لا كتابة مباشرة لحالة الطلب أو مجاميعه.
    await sb.rpc('mark_order_paid', params: {'p_order_id': orderId});
  }
}
