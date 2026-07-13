import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MarketplaceScreen extends ConsumerWidget {
  const MarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.store, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Marketplace', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Browse furniture & materials', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
