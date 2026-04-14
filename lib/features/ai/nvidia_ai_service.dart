import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

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

  /// Apply edge detection using Sobel operator on image bytes
  Future<Uint8List> applyEdgeDetection(Uint8List imageBytes, int width, int height) async {
    try {
      // Decode image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return imageBytes;
      
      // Convert to grayscale
      img.Image grayscale = img.grayscale(image);
      
      // Apply Sobel edge detection
      img.Image edges = img.sobel(grayscale);
      
      // Encode back to JPEG
      final encoded = img.encodeJpg(edges, quality: 85);
      return Uint8List.fromList(encoded);
    } catch (e) {
      debugPrint('Edge detection error: $e');
      return imageBytes;
    }
  }

  /// Apply Canny edge detection for better contour extraction
  Future<Uint8List> applyCannyEdgeDetection(Uint8List imageBytes, int width, int height) async {
    try {
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return imageBytes;
      
      // Convert to grayscale
      img.Image grayscale = img.grayscale(image);
      
      // Apply Gaussian blur first
      img.Image blurred = img.gaussianBlur(grayscale, radius: 2);
      
      // Apply Canny edge detection
      img.Image edges = img.canny(blurred);
      
      final encoded = img.encodeJpg(edges, quality: 85);
      return Uint8List.fromList(encoded);
    } catch (e) {
      debugPrint('Canny edge detection error: $e');
      return imageBytes;
    }
  }

  /// Detect contours and return contour information
  List<Map<String, dynamic>> detectContours(Uint8List imageBytes, int width, int height) {
    try {
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return [];
      
      // Convert to grayscale
      img.Image grayscale = img.grayscale(image);
      
      // Apply threshold
      img.Image thresholded = img.threshold(grayscale, threshold: 128);
      
      // Find contours would require more complex implementation
      // For now, return basic edge info
      return [{
        'width': width,
        'height': height,
        'hasEdges': true,
      }];
    } catch (e) {
      debugPrint('Contour detection error: $e');
      return [];
    }
  }

  /// Enhanced scene analysis with contour-aware prompting
  Future<String> analyzeSceneWithContours(File imageFile, List<String> detectedObjects) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      String contextPrompt = '';
      if (detectedObjects.isNotEmpty) {
        contextPrompt = 'ML detection found these objects: ${detectedObjects.join(', ')}. ';
      }
      
      final prompt = '${contextPrompt}Analyze the edges, contours, and spatial relationships in this image. Describe obstacles, pathways, and important navigation information for a blind person. Be specific about distances and positions.';
      
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
          'max_tokens': 1500,
          'temperature': 0.5,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] ?? 'No analysis available.';
      } else {
        debugPrint('NVIDIA API Error: ${response.statusCode} - ${response.body}');
        return 'Scene analysis unavailable. Error: ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('NVIDIA Scene Analysis Exception: $e');
      return 'Failed to analyze scene with contours: $e';
    }
  }
}
