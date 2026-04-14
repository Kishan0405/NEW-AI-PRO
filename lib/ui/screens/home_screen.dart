import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ai_vision_pro/features/camera/camera_provider.dart';
import 'package:ai_vision_pro/features/detection/detection_provider.dart';
import 'package:ai_vision_pro/features/tts/tts_provider.dart';
import 'package:ai_vision_pro/features/vibration/vibration_provider.dart';
import 'package:ai_vision_pro/features/voice_command/voice_command_provider.dart';
import 'package:ai_vision_pro/features/accessibility/accessibility_provider.dart';
import 'package:ai_vision_pro/core/services/permission_service.dart';
import 'package:ai_vision_pro/ui/screens/camera_preview_screen.dart';
import 'package:ai_vision_pro/ui/screens/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _hasCameraPermission = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _isLoading = true);
    _hasCameraPermission = await PermissionService().hasCameraPermission();
    await PermissionService().hasMicrophonePermission();
    setState(() => _isLoading = false);
  }

  Future<void> _requestPermissions() async {
    final cameraGranted = await PermissionService().requestCameraPermission();
    await PermissionService().requestMicrophonePermission();
    setState(() { _hasCameraPermission = cameraGranted; });
    if (cameraGranted) _initializeServices();
  }

  Future<void> _initializeServices() async {
    final ttsProvider = context.read<TTSProvider>();
    final vibrationProvider = context.read<VibrationProvider>();
    final voiceCommandProvider = context.read<VoiceCommandProvider>();
    
    await ttsProvider.initialize();
    await vibrationProvider.initialize();
    await voiceCommandProvider.initialize();
    
    if (context.read<AccessibilityProvider>().isVoiceGuidanceEnabled) {
      ttsProvider.speak('AI Vision Pro ready. Tap start to begin scanning.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accessibilityProvider = context.watch<AccessibilityProvider>();
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF0F0F13), // Deep Gemini Dark
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Semantics(
          label: 'AI Vision Pro',
          child: const Text('AI VISION PRO', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Glowing Ambient Background (Gemini Vibe)
          Positioned(
            top: -100, left: -100,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue.withValues(alpha: 0.2)),
            ),
          ),
          Positioned(
            bottom: -50, right: -50,
            child: Container(
              width: 350, height: 350,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.purple.withValues(alpha: 0.15)),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Container(color: Colors.transparent),
          ),
          
          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : !_hasCameraPermission
                    ? _buildPermissionRequired()
                    : _buildMainContent(accessibilityProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography, size: 80, color: Colors.white54),
            const SizedBox(height: 24),
            const Text('Camera permission is required.', style: TextStyle(fontSize: 18, color: Colors.white)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _requestPermissions,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Grant Camera Permission'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(AccessibilityProvider accessibilityProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Glassmorphic Hero Card
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
                ),
                child: Column(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.blueAccent, Colors.purpleAccent],
                      ).createShader(bounds),
                      child: const Icon(Icons.auto_awesome, size: 48, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'AI VISION PRO',
                      style: TextStyle(
                        fontSize: 28 * accessibilityProvider.textScaleFactor,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your smart environmental guide',
                      style: TextStyle(
                        fontSize: 14 * accessibilityProvider.textScaleFactor,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const Spacer(),
          
          _buildGlassButton(
            icon: Icons.camera_alt_outlined,
            label: 'Start Scanning',
            color: Colors.blueAccent,
            onPressed: () => _startScanning(),
          ),
          const SizedBox(height: 16),
          _buildGlassButton(
            icon: Icons.document_scanner_outlined,
            label: 'Read Text (OCR)',
            color: Colors.orangeAccent,
            onPressed: () => _toggleOcr(),
          ),
          const SizedBox(height: 16),
          _buildGlassButton(
            icon: Icons.mic_none_outlined,
            label: 'Voice Commands',
            color: Colors.purpleAccent,
            onPressed: () => _startVoiceCommands(),
          ),
          const SizedBox(height: 16),
          _buildEmergencyButton(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildGlassButton({required IconData icon, required String label, required Color color, required VoidCallback onPressed}) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 32, color: color),
                  const SizedBox(width: 20),
                  Text(
                    label,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9)),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmergencyButton() {
    return Semantics(
      label: 'Emergency alert button. Long press to activate.',
      button: true,
      child: GestureDetector(
        onLongPress: _triggerEmergency,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5), width: 2),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 32, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Text('EMERGENCY ALERT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Handlers remain largely the same ---
  Future<void> _startScanning() async {
    final vibrationProvider = context.read<VibrationProvider>();
    vibrationProvider.vibrateForButtonPress();
    final cameraProvider = context.read<CameraProvider>();
    final detectionProvider = context.read<DetectionProvider>();
    final ttsProvider = context.read<TTSProvider>();
    
    if (!cameraProvider.isInitialized) await cameraProvider.initializeCamera();
    
    detectionProvider.onSpeakText = (text) { ttsProvider.speak(text, interrupt: false); };
    cameraProvider.onImageAvailable = (image) { 
      if (!detectionProvider.isProcessing) {
        detectionProvider.processImage(image);
      }
    };
    
    await cameraProvider.startStream();
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraPreviewScreen()));
  }

  Future<void> _toggleOcr() async {
    context.read<VibrationProvider>().vibrateForButtonPress();
    final detectionProvider = context.read<DetectionProvider>();
    final ttsProvider = context.read<TTSProvider>();
    detectionProvider.toggleOcr();
    if (detectionProvider.isOcrEnabled) ttsProvider.speak('Text reading enabled.');
    else ttsProvider.speak('Text reading disabled.');
  }

  Future<void> _startVoiceCommands() async {
    context.read<VibrationProvider>().vibrateForButtonPress();
    final voiceCommandProvider = context.read<VoiceCommandProvider>();
    if (!voiceCommandProvider.isInitialized) await voiceCommandProvider.initialize();
    await voiceCommandProvider.startListening();
    context.read<TTSProvider>().speak('Listening for commands.');
  }

  Future<void> _triggerEmergency() async {
    context.read<VibrationProvider>().vibrateForEmergency();
    context.read<TTSProvider>().speak('Emergency alert activated.');
  }
}