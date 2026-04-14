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
  CameraImage? _currentFrame;

  @override
  void initState() {
    super.initState();
    _setupDetectionCallback();
    _startVoiceCommandListener();
    _setupFrameCapture();
  }

  void _setupDetectionCallback() {
    final detectionProvider = context.read<DetectionProvider>();
    final ttsProvider = context.read<TTSProvider>();
    final vibrationProvider = context.read<VibrationProvider>();
    
    detectionProvider.onSpeakText = (text) async {
      if (context.read<AccessibilityProvider>().isVoiceGuidanceEnabled) {
        await ttsProvider.speak(text, interrupt: false);
        
        if (detectionProvider.currentDetections.isNotEmpty && context.read<AccessibilityProvider>().isHapticFeedbackEnabled) {
          final firstObj = detectionProvider.currentDetections.first;
          final area = firstObj.boundingBox != null 
              ? firstObj.boundingBox!.width * firstObj.boundingBox!.height 
              : 0.0;
              
          final isPriority = detectionProvider.getObstaclePriority(firstObj.label) == ObstaclePriority.critical;
          
          vibrationProvider.vibrateForObject(
            isPriority: isPriority, 
            spatialLocation: firstObj.spatialLocation,
            area: area,
          );
        }
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
        case VoiceCommand.describeSurroundings: 
          await detectionProvider.describeSurroundings(
            useAdvancedAI: true,
            currentFrame: _currentFrame,
          ); 
          break;
        case VoiceCommand.emergency: _triggerEmergency(); break;
        default: break;
      }
    };
  }

  void _setupFrameCapture() {
    final cameraProvider = context.read<CameraProvider>();
    final detectionProvider = context.read<DetectionProvider>();
    
    cameraProvider.onImageAvailable = (CameraImage image) {
      _currentFrame = image;
      detectionProvider.processImage(image);
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
          Positioned.fill(child: CustomPaint(painter: DetectionOverlayPainter(detections: detectionProvider.currentDetections, edgeDetectionEnabled: detectionProvider.isEdgeDetectionEnabled))),
          
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    margin: const EdgeInsets.only(right: 8),
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: detectionProvider.isEdgeDetectionEnabled ? Colors.greenAccent.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edges, size: 20, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(detectionProvider.isEdgeDetectionEnabled ? 'EDGES ON' : 'EDGES OFF', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  ),
                ],
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
                () => context.read<DetectionProvider>().describeSurroundings(
                  useAdvancedAI: true,
                  currentFrame: _currentFrame,
                ), 
                isLarge: true
              ),
              _buildControlIcon(Icons.edges, 'Edges', () => context.read<DetectionProvider>().toggleEdgeDetection()),
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
    final topDetections = detectionProvider.currentDetections.take(3).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Active Detections', style: TextStyle(fontSize: 14, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...topDetections.map((d) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(d.label.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    Text('${(d.confidence * 100).toInt()}%', style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              )),
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

class DetectionOverlayPainter extends CustomPainter {
  final List<AppDetectedObject> detections;
  final bool edgeDetectionEnabled;
  
  DetectionOverlayPainter({required this.detections, this.edgeDetectionEnabled = false});
  
  @override
  void paint(Canvas canvas, Size size) {
    // Enhanced contour visualization when edge detection is enabled
    if (edgeDetectionEnabled) {
      final edgePaint = Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.8)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      
      final glowPaint = Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      
      for (final detection in detections) {
        if (detection.boundingBox != null) {
          final rect = Rect.fromLTWH(
            detection.boundingBox!.left * size.width,
            detection.boundingBox!.top * size.height,
            detection.boundingBox!.width * size.width,
            detection.boundingBox!.height * size.height,
          );
          
          // Draw glowing fill
          final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
          canvas.drawRRect(rRect, glowPaint);
          
          // Draw edge-highlighted contour
          canvas.drawRRect(rRect, edgePaint);
          
          // Add corner markers for enhanced visibility
          _drawCornerMarkers(canvas, rect, edgePaint);
        }
      }
    } else {
      // Standard bounding box rendering
      final boxPaint = Paint()
        ..color = Colors.blueAccent.withValues(alpha: 0.6)
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;
      
      final fillPaint = Paint()
        ..color = Colors.blueAccent.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;
      
      for (final detection in detections) {
        if (detection.boundingBox != null) {
          final rect = Rect.fromLTWH(
            detection.boundingBox!.left * size.width,
            detection.boundingBox!.top * size.height,
            detection.boundingBox!.width * size.width,
            detection.boundingBox!.height * size.height,
          );
          
          // Rounded Glowing Bounding Boxes
          final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
          canvas.drawRRect(rRect, fillPaint);
          canvas.drawRRect(rRect, boxPaint);
        }
      }
    }
  }
  
  void _drawCornerMarkers(Canvas canvas, Rect rect, Paint paint) {
    const markerLength = 20.0;
    
    // Top-left corner
    canvas.drawLine(
      Offset(rect.left, rect.top + markerLength),
      Offset(rect.left, rect.top),
      paint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.left + markerLength, rect.top),
      paint,
    );
    
    // Top-right corner
    canvas.drawLine(
      Offset(rect.right - markerLength, rect.top),
      Offset(rect.right, rect.top),
      paint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.top),
      Offset(rect.right, rect.top + markerLength),
      paint,
    );
    
    // Bottom-left corner
    canvas.drawLine(
      Offset(rect.left, rect.bottom - markerLength),
      Offset(rect.left, rect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.left + markerLength, rect.bottom),
      paint,
    );
    
    // Bottom-right corner
    canvas.drawLine(
      Offset(rect.right - markerLength, rect.bottom),
      Offset(rect.right, rect.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.bottom - markerLength),
      Offset(rect.right, rect.bottom),
      paint,
    );
  }
  
  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) => 
      oldDelegate.detections != detections || 
      oldDelegate.edgeDetectionEnabled != edgeDetectionEnabled;
}
