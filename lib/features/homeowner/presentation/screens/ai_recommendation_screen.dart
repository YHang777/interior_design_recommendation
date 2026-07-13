import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiRecommendationScreen extends ConsumerWidget {
  const AiRecommendationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.psychology, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('AI Recommendations', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Get AI-powered design ideas', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
