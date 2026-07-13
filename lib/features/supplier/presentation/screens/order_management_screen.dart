import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OrderManagementScreen extends ConsumerWidget {
  const OrderManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Order Management', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Track & manage orders', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
