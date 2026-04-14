import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class NvidiaAIService {
  static const String _apiKey = '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';
  static const String _baseUrl = 'https://integrate.api.nvidia.com/v1';
  static const String _visionModel = 'nvidia/nemotron-4-340b-v1-vl';

  /// Analyzes an image file using NVIDIA NIM Vision-Language model
  Future<String> analyzeImage(File imageFile, {String prompt = 'Describe the objects and spatial layout in this scene for a blind person.'}) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _visionModel,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,$base64Image'}
                }
              ]
            }
          ],
          'max_tokens': 1024,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] ?? 'No analysis available.';
      } else {
        debugPrint('NVIDIA API Error: ${response.statusCode} - ${response.body}');
        return 'I encountered an error connecting to the NVIDIA brain. Error code: ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('NVIDIA Service Exception: $e');
      return 'Failed to analyze scene: $e';
    }
  }

  /// Chat with NVIDIA NIM for general reasoning
  Future<String> chat(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'nvidia/nemotron-3-super-120b-a12b',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] ?? '';
      }
      return '';
    } catch (e) {
      return 'Chat error: $e';
    }
  }
}
