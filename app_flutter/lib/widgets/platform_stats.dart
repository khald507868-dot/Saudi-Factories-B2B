import 'package:flutter/material.dart';

import '../core/currency.dart';
import '../core/i18n.dart';
import '../core/supabase_config.dart';
import '../core/theme.dart';
import 'price_text.dart';

class PlatformStats extends StatefulWidget {
  const PlatformStats({super.key});
  @override
  State<PlatformStats> createState() => _PlatformStatsState();
}

class _PlatformStatsState extends State<PlatformStats> {
  late final Future<dynamic> _stats = sb.rpc('get_public_stats');
  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: _stats,
    builder: (context, snapshot) {
      if (!snapshot.hasData || snapshot.hasError) {
        return const SizedBox.shrink();
      }
      final data = snapshot.data;
      final row = data is List ? (data.isEmpty ? null : data.first) : data;
      if (row is! Map) return const SizedBox.shrink();
      final entries = <String, String>{
        'stats_factories': '${row['factories_count'] ?? 0}',
        'stats_products': '${row['products_count'] ?? 0}',
        'stats_units_sold': '${row['units_sold'] ?? 0}',
        'stats_revenue': SFCurrency.formatSar(
          double.tryParse('${row['revenue']}') ?? 0,
        ),
      };
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final entry in entries.entries)
                    Container(
                      width: (constraints.maxWidth - 10) / 2,
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
          ),
        ),
      );
    },
  );
}
