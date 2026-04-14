import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:ai_vision_pro/features/camera/camera_provider.dart';
import 'package:ai_vision_pro/features/detection/detection_provider.dart';
import 'package:ai_vision_pro/features/tts/tts_provider.dart';
import 'package:ai_vision_pro/features/vibration/vibration_provider.dart';
import 'package:ai_vision_pro/features/voice_command/voice_command_provider.dart';
import 'package:ai_vision_pro/features/accessibility/accessibility_provider.dart';

class CameraPreviewScreen extends StatefulWidget {
  const CameraPreviewScreen({super.key});

  @override
  State<CameraPreviewScreen> createState() => _CameraPreviewScreenState();
}

class _CameraPreviewScreenState extends State<CameraPreviewScreen> {
  @override
  void initState() {
    super.initState();
    _setupDetectionCallback();
    _startVoiceCommandListener();
  }

  void _setupDetectionCallback() {
    final detectionProvider = context.read<DetectionProvider>();
    final ttsProvider = context.read<TTSProvider>();
    
    // TTS-only callback — vibration is handled separately via onNewDetection
    // (set in home_screen._startScanning) to avoid duplicate wiring.
    detectionProvider.onSpeakText = (text) async {
      if (context.read<AccessibilityProvider>().isVoiceGuidanceEnabled) {
        await ttsProvider.speak(text, interrupt: false);
      }
    };
  }

  void _startVoiceCommandListener() {
    final voiceCommandProvider = context.read<VoiceCommandProvider>();
    final detectionProvider = context.read<DetectionProvider>();
    
    voiceCommandProvider.onVoiceCommand = (command) async {
      switch (command) {
        case VoiceCommand.stopScanning: await _stopScanning(); break;
        case VoiceCommand.readText: detectionProvider.toggleOcr(); break;
        case VoiceCommand.describeSurroundings: await detectionProvider.describeSurroundings(); break;
        case VoiceCommand.emergency: _triggerEmergency(); break;
        default: break;
      }
    };
  }

  Future<void> _stopScanning() async {
    await context.read<CameraProvider>().stopStream();
    if (mounted) Navigator.pop(context);
  }

  void _triggerEmergency() {
    context.read<VibrationProvider>().vibrateForEmergency();
  }

  @override
  Widget build(BuildContext context) {
    final cameraProvider = context.watch<CameraProvider>();
    final detectionProvider = context.watch<DetectionProvider>();
    final accessibilityProvider = context.watch<AccessibilityProvider>();
    
    if (!cameraProvider.isInitialized || cameraProvider.controller == null) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.white)));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(cameraProvider.controller!)),
          Positioned.fill(
            child: CustomPaint(
              painter: DetectionOverlayPainter(
                detections: detectionProvider.currentDetections,
                imageWidth: detectionProvider.lastImageWidth.toDouble(),
                imageHeight: detectionProvider.lastImageHeight.toDouble(),
              ),
            ),
          ),
          
          Positioned(top: 0, left: 0, right: 0, child: _buildTopGlassBar(accessibilityProvider, detectionProvider)),
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomGlassControls()),
          
          if (detectionProvider.currentDetections.isNotEmpty)
            Positioned(top: 120, left: 20, right: 20, child: _buildGlassDetectionIndicator(detectionProvider)),
        ],
      ),
    );
  }

  Widget _buildTopGlassBar(AccessibilityProvider accessibilityProvider, DetectionProvider detectionProvider) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.only(top: 60, bottom: 20, left: 20, right: 20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: detectionProvider.isOcrEnabled ? Colors.orangeAccent.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.text_fields, size: 20, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(detectionProvider.isOcrEnabled ? 'OCR ACTIVE' : 'OCR OFF', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 32, color: Colors.white),
                onPressed: () => _stopScanning(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomGlassControls() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.only(top: 24, bottom: 40),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildControlIcon(Icons.text_fields, 'Read', () => context.read<DetectionProvider>().toggleOcr()),
              _buildControlIcon(
                Icons.visibility, 
                'Describe', 
                () => context.read<DetectionProvider>().describeSurroundings(), 
                isLarge: true
              ),
              _buildControlIcon(Icons.flash_on, 'Flash', () => context.read<CameraProvider>().toggleFlash()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlIcon(IconData icon, String label, VoidCallback onPressed, {bool isLarge = false}) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(isLarge ? 24 : 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, size: isLarge ? 36 : 24, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildGlassDetectionIndicator(DetectionProvider detectionProvider) {
    final topDetections = detectionProvider.currentDetections.take(5).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Active Detections', style: TextStyle(fontSize: 14, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${detectionProvider.currentDetections.length}', style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...topDetections.map((d) {
                final confPercent = (d.confidence * 100).toInt();
                final confColor = confPercent >= 80
                    ? Colors.greenAccent
                    : confPercent >= 60
                        ? Colors.yellowAccent
                        : Colors.orangeAccent;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: confColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(d.label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text('$confPercent%', style: TextStyle(color: confColor, fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    context.read<CameraProvider>().stopStream();
    super.dispose();
  }
}

/// Paints bounding boxes from ML Kit Object Detection onto the camera preview.
///
/// ML Kit returns bounding boxes in absolute pixel coordinates relative to the
/// camera image size. We scale those to screen coordinates using the ratio of
/// screen size to camera image size.
class DetectionOverlayPainter extends CustomPainter {
  final List<AppDetectedObject> detections;
  final double imageWidth;
  final double imageHeight;

  DetectionOverlayPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth <= 0 || imageHeight <= 0) return;

    // Scale factors: map from camera-image coordinates → screen coordinates
    final double scaleX = size.width / imageWidth;
    final double scaleY = size.height / imageHeight;

    final boxPaint = Paint()..color = Colors.blueAccent.withValues(alpha: 0.6)..strokeWidth = 3.0..style = PaintingStyle.stroke;
    final fillPaint = Paint()..color = Colors.blueAccent.withValues(alpha: 0.1)..style = PaintingStyle.fill;
    final labelBgPaint = Paint()..color = Colors.blueAccent.withValues(alpha: 0.7)..style = PaintingStyle.fill;
    
    for (final detection in detections) {
      if (detection.boundingBox != null) {
        final rect = Rect.fromLTWH(
          detection.boundingBox!.left * scaleX,
          detection.boundingBox!.top * scaleY,
          detection.boundingBox!.width * scaleX,
          detection.boundingBox!.height * scaleY,
        );
        
        // Rounded glowing bounding boxes
        final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
        canvas.drawRRect(rRect, fillPaint);
        canvas.drawRRect(rRect, boxPaint);

        // Draw label text above the bounding box
        final labelText = '${detection.label} ${(detection.confidence * 100).toInt()}%';
        final textPainter = TextPainter(
          text: TextSpan(
            text: labelText,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final labelRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, rect.top - 22, textPainter.width + 12, 20),
          const Radius.circular(6),
        );
        canvas.drawRRect(labelRect, labelBgPaint);
        textPainter.paint(canvas, Offset(rect.left + 6, rect.top - 20));
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) =>
      oldDelegate.detections != detections ||
      oldDelegate.imageWidth != imageWidth ||
      oldDelegate.imageHeight != imageHeight;
}