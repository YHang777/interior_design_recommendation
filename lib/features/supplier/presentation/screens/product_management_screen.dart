import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProductManagementScreen extends ConsumerWidget {
  const ProductManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Product Management', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Manage your inventory', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
