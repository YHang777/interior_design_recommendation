import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/chat_state_answers.dart';
import 'package:interior_design_recommendation/models/chat_session.dart';

void main() {
  group('matchStateQuestion', () {
    test('recognises each state topic', () {
      expect(matchStateQuestion("What's in my cart?")?.topic, ChatDataTopic.cart);
      expect(matchStateQuestion('How much is my basket?')?.topic,
          ChatDataTopic.cart);
      expect(matchStateQuestion('How much budget is left?')?.topic,
          ChatDataTopic.budget);
      expect(matchStateQuestion('Can I afford this sofa?')?.topic,
          ChatDataTopic.budget);
      expect(matchStateQuestion('Show my room plan')?.topic, ChatDataTopic.plan);
      expect(matchStateQuestion('How big is my floor plan?')?.topic,
          ChatDataTopic.plan);
      expect(matchStateQuestion("Where's my order?")?.topic,
          ChatDataTopic.orders);
      expect(matchStateQuestion('Track my package please')?.topic,
          ChatDataTopic.orders);
      expect(matchStateQuestion('What have I saved?')?.topic,
          ChatDataTopic.wishlist);
      expect(matchStateQuestion('Show my wishlist')?.topic,
          ChatDataTopic.wishlist);
    });

    test('ignores unrelated questions and the fit prompt', () {
      expect(matchStateQuestion('Suggest a sofa for a grey floor'), isNull);
      expect(matchStateQuestion('Does it fit my home?'), isNull);
      expect(matchStateQuestion('Hello there'), isNull);
      expect(matchStateQuestion(''), isNull);
    });

    test('short single-topic questions are pure', () {
      final match = matchStateQuestion("What's in my cart right now?");
      expect(match?.topic, ChatDataTopic.cart);
      expect(match?.isPure, isTrue);
    });

    test('longer state questions still match but are not pure', () {
      final match = matchStateQuestion(
          'Could you please tell me everything that is currently inside my shopping cart today?');
      expect(match?.topic, ChatDataTopic.cart);
      expect(match?.isPure, isFalse);
    });

    test('mixed advice + state questions are not pure', () {
      final match = matchStateQuestion('Suggest a sofa and also how much is my cart');
      expect(match, isNotNull);
      expect(match!.isPure, isFalse);
    });

    test('multi-topic questions pick the first rule in priority order', () {
      final match = matchStateQuestion('My cart and my budget');
      expect(match?.isPure, isFalse);
    });
  });

  group('cannedLine', () {
    test('gives one short warm line per topic', () {
      for (final topic in ChatDataTopic.values) {
        expect(cannedLine(topic), isNotEmpty);
        expect(cannedLine(topic).split(' ').length, lessThan(12));
      }
    });
  });
}
