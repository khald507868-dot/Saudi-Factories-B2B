import 'package:flutter/material.dart';

import '../core/currency.dart';
import '../core/i18n.dart';
import '../core/supabase_config.dart';
import '../core/theme.dart';
import 'common.dart';
import 'price_text.dart';

/// لا تُطلب أرقام المنصة إلا عند فتح نافذتها.
Future<void> showPlatformStats(BuildContext context) async {
  FocusScope.of(context).unfocus();
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
    builder: (context) => SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .85),
          child: SingleChildScrollView(
            key: const ValueKey('platform-stats-scroll'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.t('stats_title'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('platform-stats-close'),
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const PlatformStats(showTitle: false),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class PlatformStats extends StatefulWidget {
  const PlatformStats({super.key, this.showTitle = true});

  final bool showTitle;

  @override
  State<PlatformStats> createState() => _PlatformStatsState();
}

class _PlatformStatsState extends State<PlatformStats> {
  late Future<Map<String, String>> _stats = _load();

  Future<Map<String, String>> _load() async {
    final data = await sb.rpc('get_public_stats');
    final row = data is List ? (data.length == 1 ? data.single : null) : data;
    if (row is! Map) throw const FormatException('Invalid public stats row');

    num number(String key, {bool integer = false}) {
      final value = num.tryParse('${row[key]}');
      if (value == null ||
          !value.isFinite ||
          value < 0 ||
          (integer && value % 1 != 0)) {
        throw const FormatException('Invalid public stats value');
      }
      return value;
    }

    return {
      'stats_factories': number(
        'factories_count',
        integer: true,
      ).toInt().toString(),
      'stats_products': number(
        'products_count',
        integer: true,
      ).toInt().toString(),
      'stats_units_sold': number('units_sold').toString(),
      'stats_revenue': SFCurrency.formatSar(number('revenue').toDouble()),
    };
  }

  void _retry() => setState(() {
    _stats = _load();
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, String>>(
    future: _stats,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return SFStateView(message: context.t('fx_loading'), loading: true);
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return SFStateView(
          message: context.t('app_load_error'),
          icon: Icons.cloud_off_outlined,
          retryLabel: context.t('app_retry'),
          onRetry: _retry,
        );
      }
      final entries = snapshot.data!;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final singleColumn =
                constraints.maxWidth < 260 ||
                MediaQuery.textScalerOf(context).scale(12) > 18;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showTitle) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: SFColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(SFMetrics.radius),
                      border: Border.all(color: SFColors.border),
                    ),
                    child: Text(
                      context.t('stats_title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final entry in entries.entries)
                      Container(
                        width: singleColumn
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 10) / 2,
                        constraints: const BoxConstraints(minHeight: 80),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: SFColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(SFMetrics.radius),
                          border: Border.all(color: SFColors.border),
                        ),
                        child: Column(
                          children: [
                            Tooltip(
                              message: entry.value,
                              child: SFPriceText(
                                entry.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                  fontSize: 19,
                                  height: 1.3,
                                  color: SFColors.darkGreen,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.t(entry.key),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: SFColors.muted2,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    },
  );
}
