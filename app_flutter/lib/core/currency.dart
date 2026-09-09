import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SFCurrencyInfo {
  const SFCurrencyInfo(
    this.code,
    this.rate,
    this.ar,
    this.en,
    this.symbol,
    this.decimals,
  );
  final String code;
  final double rate;
  final String ar;
  final String en;
  final String symbol;
  final int decimals;
}

/// نفس أسعار العرض المرجعية في currency.js؛ الطلبات والفواتير تبقى بالريال.
class SFCurrency extends ChangeNotifier {
  SFCurrency._();
  static final instance = SFCurrency._();
  static const currencies = <SFCurrencyInfo>[
    SFCurrencyInfo('SAR', 1, 'ريال سعودي', 'Saudi Riyal', '﷼', 2),
    SFCurrencyInfo('USD', .2667, 'دولار أمريكي', 'US Dollar', '\$', 2),
    SFCurrencyInfo('EUR', .2453, 'يورو', 'Euro', '€', 2),
    SFCurrencyInfo('GBP', .2088, 'جنيه إسترليني', 'British Pound', '£', 2),
    SFCurrencyInfo('AED', .9793, 'درهم إماراتي', 'UAE Dirham', 'د.إ', 2),
    SFCurrencyInfo('KWD', .0817, 'دينار كويتي', 'Kuwaiti Dinar', 'د.ك', 3),
    SFCurrencyInfo('QAR', .9709, 'ريال قطري', 'Qatari Riyal', 'ر.ق', 2),
    SFCurrencyInfo('BHD', .1005, 'دينار بحريني', 'Bahraini Dinar', 'د.ب', 3),
    SFCurrencyInfo('OMR', .1027, 'ريال عُماني', 'Omani Rial', 'ر.ع', 3),
    SFCurrencyInfo('EGP', 12.95, 'جنيه مصري', 'Egyptian Pound', 'ج.م', 2),
    SFCurrencyInfo('JOD', .1891, 'دينار أردني', 'Jordanian Dinar', 'د.أ', 3),
    SFCurrencyInfo('TRY', 10.92, 'ليرة تركية', 'Turkish Lira', '₺', 2),
    SFCurrencyInfo('CNY', 1.897, 'يوان صيني', 'Chinese Yuan', '¥', 2),
    SFCurrencyInfo('INR', 23.52, 'روبية هندية', 'Indian Rupee', '₹', 2),
    SFCurrencyInfo('PKR', 74.85, 'روبية باكستانية', 'Pakistani Rupee', '₨', 0),
    SFCurrencyInfo('BDT', 32.28, 'تاكا بنغلاديشي', 'Bangladeshi Taka', '৳', 0),
    SFCurrencyInfo(
      'IDR',
      4355,
      'روبية إندونيسية',
      'Indonesian Rupiah',
      'Rp',
      0,
    ),
    SFCurrencyInfo('MYR', 1.124, 'رنغيت ماليزي', 'Malaysian Ringgit', 'RM', 2),
    SFCurrencyInfo('JPY', 39.45, 'ين ياباني', 'Japanese Yen', '¥', 0),
    SFCurrencyInfo('KRW', 361.2, 'وون كوري', 'South Korean Won', '₩', 0),
    SFCurrencyInfo('CHF', .2131, 'فرنك سويسري', 'Swiss Franc', 'Fr', 2),
    SFCurrencyInfo('CAD', .3648, 'دولار كندي', 'Canadian Dollar', 'C\$', 2),
    SFCurrencyInfo(
      'AUD',
      .4021,
      'دولار أسترالي',
      'Australian Dollar',
      'A\$',
      2,
    ),
    SFCurrencyInfo('RUB', 21.34, 'روبل روسي', 'Russian Ruble', '₽', 2),
    SFCurrencyInfo(
      'ZAR',
      4.712,
      'راند جنوب أفريقي',
      'South African Rand',
      'R',
      2,
    ),
    SFCurrencyInfo('NGN', 398.6, 'نايرا نيجيري', 'Nigerian Naira', '₦', 0),
    SFCurrencyInfo('MAD', 2.451, 'درهم مغربي', 'Moroccan Dirham', 'د.م', 2),
    SFCurrencyInfo('TND', .8194, 'دينار تونسي', 'Tunisian Dinar', 'د.ت', 3),
    SFCurrencyInfo(
      'SGD',
      .3417,
      'دولار سنغافوري',
      'Singapore Dollar',
      'S\$',
      2,
    ),
    SFCurrencyInfo('BRL', 1.428, 'ريال برازيلي', 'Brazilian Real', 'R\$', 2),
  ];

  SFCurrencyInfo _current = currencies.first;
  String get code => _current.code;
  SFCurrencyInfo get current => _current;
  double get rate => _current.rate;
  int get decimals => _current.decimals;
  bool get isForeign => code != 'SAR';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('sf_currency');
      _current = currencies.firstWhere(
        (item) => item.code == saved,
        orElse: () => currencies.first,
      );
      notifyListeners();
    } catch (_) {
      // تعذّر التخزين لا يمنع عرض الأسعار بالريال.
    }
  }

  Future<void> setCurrency(String code) async {
    final matches = currencies.where((item) => item.code == code);
    if (matches.isEmpty || this.code == code) return;
    _current = matches.first;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sf_currency', code);
    } catch (_) {
      // الاختيار يظل فعّالاً للجلسة إذا تعذّر حفظه.
    }
  }

  double convert(double sar) => sar * rate;
  double roundConverted(double sar) =>
      double.parse(convert(sar).toStringAsFixed(decimals));

  /// مجموع العرض يساوي سعر الوحدة الظاهر مضروباً في الكمية، كما في الويب.
  double lineAmount(double sarUnit, int quantity) =>
      roundConverted(sarUnit) * quantity / rate;

  String format(double sar, {bool withSymbol = true}) {
    if (!sar.isFinite) return '—';
    final number = NumberFormat.decimalPatternDigits(
      locale: 'en',
      decimalDigits: decimals,
    ).format(convert(sar));
    return withSymbol ? '$number ${_current.symbol}' : number;
  }

  static String formatSar(double sar) =>
      '${NumberFormat.decimalPatternDigits(locale: 'en', decimalDigits: 2).format(sar)} ﷼';
}
