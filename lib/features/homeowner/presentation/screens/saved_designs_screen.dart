import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SavedDesignsScreen extends ConsumerWidget {
  const SavedDesignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bookmark, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('Saved Designs', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Your saved room designs', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
