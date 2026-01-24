import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../models/conversation.dart';

class AiStudioProvider extends ChangeNotifier {
  // State
  String _inputText = '';
  String _translatedText = '';
  String _scriptText = '';
  
  bool _isTranslating = false;
  bool _isGeneratingScript = false;
  
  // Dedicated conversations to keep context isolated if needed
  // Or we can use one-shot requests.
  int? _translationConvId;
  int? _scriptConvId;

  // Getters
  String get inputText => _inputText;
  String get translatedText => _translatedText;
  String get scriptText => _scriptText;
  bool get isTranslating => _isTranslating;
  bool get isGeneratingScript => _isGeneratingScript;

  // Setters
  void setInputText(String text) {
    _inputText = text;
    notifyListeners();
  }

  void setTranslatedText(String text) {
    _translatedText = text;
    notifyListeners();
  }

  // Actions
  Future<void> translate() async {
    if (_inputText.isEmpty) return;
    
    _isTranslating = true;
    _translatedText = ''; // Clear previous
    notifyListeners();

    try {
      if (_translationConvId == null) {
        final conv = await ChatService.createConversation();
        _translationConvId = conv.id;
      }

      final prompt = """
SYSTEM INSTRUCTION: You are a professional subtitle translator.
Your task is to translate the following subtitle text to Vietnamese.

STRICT OUTPUT RULES:
1. Output ONLY the translated text.
2. Maintain the original SRT timestamps and numbering EXACTLY if present.
3. Do NOT add any notes, explanations, or conversational filler.
4. If the input is plain text, translate line-by-line.

INPUT TEXT:
$_inputText
""";

      final stream = ChatService.sendMessage(_translationConvId!, prompt);
      
      await for (final chunk in stream) {
         _parseAndAppend(chunk, (text) {
           _translatedText += text;
           notifyListeners();
         });
      }
    } catch (e) {
      debugPrint("Translation error: $e");
    } finally {
      _isTranslating = false;
      notifyListeners();
    }
  }

  Future<void> generateReviewScript() async {
    // We can use the translated text (if available) or the original input
    final sourceText = _translatedText.isNotEmpty ? _translatedText : _inputText;
    if (sourceText.isEmpty) return;

    _isGeneratingScript = true;
    _scriptText = '';
    notifyListeners();

    try {
      if (_scriptConvId == null) {
        final conv = await ChatService.createConversation();
        _scriptConvId = conv.id;
      }

      final prompt = """
SYSTEM INSTRUCTION: You are an expert movie reviewer and script writer.
Your goal is to write a YouTube review script based on the provided subtitle content.

STRICT OUTPUT RULES:
1. Output ONLY the script content.
2. Do NOT include any introductory phrases like "Here is the script" or "Sure".
3. Do NOT include any concluding remarks.
4. Structure the script with clear sections (Intro, Plot Summary, Analysis, Conclusion).

SUBTITLE CONTENT FOR CONTEXT:
$sourceText
""";

      final stream = ChatService.sendMessage(_scriptConvId!, prompt);

      await for (final chunk in stream) {
         _parseAndAppend(chunk, (text) {
           _scriptText += text;
           notifyListeners();
         });
      }
    } catch (e) {
      debugPrint("Script generation error: $e");
    } finally {
      _isGeneratingScript = false;
      notifyListeners();
    }
  }

  // Helper to parse SSE stream from ChatService
  void _parseAndAppend(String chunk, Function(String) onContent) {
    final lines = chunk.split('\n');
    for (final line in lines) {
      String? jsonStr;
      if (line.startsWith('data: ')) {
        jsonStr = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        jsonStr = line.substring(5).trim();
      }

      if (jsonStr != null && jsonStr != '[DONE]') {
        try {
          // crude json decode
          // In a real app, use dart:convert
          // But here we need to be careful with partial chunks? 
          // ChatService stream usually yields complete chunks or lines.
          // Let's assume valid JSON for now or try/catch.
          // import 'dart:convert'; removed
          final data = jsonDecode(jsonStr);
          if (data['message'] != null) {
            final content = data['message']['content'] as String? ?? '';
            if (content.isNotEmpty) {
              onContent(content);
            }
          }
        } catch (_) {}
      }
    }
  }
}
