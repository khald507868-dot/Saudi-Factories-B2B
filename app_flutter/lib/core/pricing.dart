// أسعار العرض تتبع شرائح الخادم؛ إنشاء الطلب لا يستقبل أي مبلغ من العميل.
class SFPriceTier {
  const SFPriceTier({required this.min, this.max, required this.price});

  final int min;
  final int? max;
  final double price;

  bool contains(int quantity) =>
      quantity >= min && (max == null || quantity <= max!);

  Map<String, dynamic> toJson() => {'min': min, 'max': max, 'price': price};

  static List<SFPriceTier> parseList(dynamic value) {
    if (value is! List) return [];
    final tiers = <SFPriceTier>[];
    for (final row in value) {
      if (row is! Map) continue;
      final min = int.tryParse('${row['min']}');
      final price = double.tryParse('${row['price']}');
      final maxText = '${row['max'] ?? ''}'.trim();
      final max = maxText.isEmpty ? null : int.tryParse(maxText);
      if (min == null ||
          min < 1 ||
          price == null ||
          !price.isFinite ||
          price <= 0 ||
          (maxText.isNotEmpty && (max == null || max < min))) {
        continue;
      }
      tiers.add(SFPriceTier(min: min, max: max, price: price));
    }
    tiers.sort((a, b) => a.min.compareTo(b.min));
    return tiers;
  }
}

class SFPriceCalculation {
  SFPriceCalculation._();

  static SFPriceTier? activeTier(List<SFPriceTier> tiers, int quantity) {
    SFPriceTier? best;
    for (final tier in tiers) {
      if (tier.contains(quantity) && (best == null || tier.min > best.min)) {
        best = tier;
      }
    }
    return best;
  }

  static double unitPrice(
    double basePrice,
    List<SFPriceTier> tiers,
    int quantity,
  ) => activeTier(tiers, quantity)?.price ?? basePrice;

  static double roundMoney(double value) =>
      (value * 100 + 0.0000001).round() / 100;
}

/// التوصيل والرسوم والضريبة مطابقة لهجرة الأسعار في Supabase.
/// هذه معاينة؛ الفاتورة النهائية تُقرأ من الطلب الذي أنشأه الخادم.
class SFOrderEstimate {
  SFOrderEstimate(double subtotal, {this.shipping = 30})
    : subtotal = SFPriceCalculation.roundMoney(subtotal);

  final double subtotal;
  final double shipping;
  double get paymentFee =>
      SFPriceCalculation.roundMoney((subtotal + shipping) * 0.01);
  double get vat =>
      SFPriceCalculation.roundMoney((subtotal + shipping + paymentFee) * 0.15);
  double get total =>
      SFPriceCalculation.roundMoney(subtotal + shipping + paymentFee + vat);
}
