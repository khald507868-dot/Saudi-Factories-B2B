import 'package:flutter/material.dart';

import '../core/currency.dart';
import '../core/i18n.dart';
import '../core/theme.dart';

Future<void> showSFCurrencyPicker(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CurrencyPicker(),
    );

class SFCurrencyButton extends StatelessWidget {
  const SFCurrencyButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => showSFCurrencyPicker(context),
    style: TextButton.styleFrom(
      foregroundColor: SFColors.darkGreen,
      backgroundColor: SFColors.surfaceAlt,
      side: const BorderSide(color: SFColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      minimumSize: const Size(54, 36),
      padding: const EdgeInsets.symmetric(horizontal: 10),
    ),
    child: Text(
      SFCurrency.instance.code,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      semanticsLabel: context.t('currency_pick'),
    ),
  );
}

class _CurrencyPicker extends StatefulWidget {
  const _CurrencyPicker();
  @override
  State<_CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<_CurrencyPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final entries = SFCurrency.currencies
        .where(
          (entry) => '${entry.code} ${entry.ar} ${entry.en}'
              .toLowerCase()
              .contains(_query.trim().toLowerCase()),
        )
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .75,
      maxChildSize: .92,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    i18n.t('currency_pick'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: i18n.t('currency_search'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              i18n.t('currency_note'),
              style: const TextStyle(color: SFColors.muted2),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return ListTile(
                  leading: SizedBox(width: 42, child: Text(entry.code)),
                  title: Text(i18n.lang == 'ar' ? entry.ar : entry.en),
                  trailing: SFCurrency.instance.code == entry.code
                      ? const Icon(Icons.check, color: SFColors.midGreen)
                      : null,
                  onTap: () async {
                    await SFCurrency.instance.setCurrency(entry.code);
                    if (context.mounted) Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
