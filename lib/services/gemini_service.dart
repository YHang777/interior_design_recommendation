import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiChatService {
  // Model and chat are optional; if the API key is missing, Gemini stays disabled.
  final GenerativeModel? _model;
  ChatSession? _chat;

  GeminiChatService({required String apiKey, String model = 'gemini-2.0-flash'})
      : _model = apiKey.isNotEmpty ? GenerativeModel(model: model, apiKey: apiKey) : null {
    if (_model != null) {
      _chat = _model.startChat();
    }
  }

  bool get isConfigured => _chat != null;

  Future<String> sendMessage(String text) async {
    if (_chat == null) {
      return 'AI assistant not configured. Please set GEMINI_API_KEY to enable chat.';
    }
    final response = await _chat!.sendMessage(Content.text(text));
    return response.text ?? 'No response from Gemini.';
  }
}