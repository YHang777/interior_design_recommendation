import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SalesAnalyticsScreen extends ConsumerWidget {
  const SalesAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bar_chart, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Sales Analytics', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('View sales & trends', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
