import 'package:flutter/material.dart';

import 'orders_page.dart';

class InvoicesPage extends StatelessWidget {
  const InvoicesPage({super.key});

  @override
  Widget build(BuildContext context) => const OrdersPage(invoicesOnly: true);
}
