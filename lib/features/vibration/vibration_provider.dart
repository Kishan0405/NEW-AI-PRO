import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// Provider for haptic feedback
class VibrationProvider extends ChangeNotifier {
  bool _isVibrationEnabled = true;
  bool _hasVibrator = false;
  String? _error;

  // Getters
  bool get isVibrationEnabled => _isVibrationEnabled;
  bool get hasVibrator => _hasVibrator;
  bool get hasError => _error != null;
  String? get error => _error;

  /// Initialize vibration service
  Future<void> initialize() async {
    try {
      _hasVibrator = await Vibration.hasVibrator();
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to initialize vibration: $e';
      _hasVibrator = false;
      notifyListeners();
    }
  }

  /// Vibrate with pattern for object detection including spatial awareness
  Future<void> vibrateForObject({bool isPriority = false, String spatialLocation = 'center', double? area}) async {
    if (!_isVibrationEnabled || !_hasVibrator) return;
    
    try {
      if (area != null) {
        // Distance-based vibration mapping
        if (area > 100000) {
          // Extremely close: Continuous pulse
          await Vibration.cancel();
          await Vibration.vibrate(pattern: [0, 500, 50, 500], intensities: [0, 255, 0, 255], repeat: 0);
          Future.delayed(const Duration(milliseconds: 600), () => Vibration.cancel());
        } else if (area > 30000) {
          // Medium distance: Steady double pulse
          await Vibration.vibrate(pattern: [0, 150, 100, 150], intensities: [0, 180, 0, 180]);
        } else {
          // Far: Light single tap
          await Vibration.vibrate(duration: 50, amplitude: 100);
        }
        return;
      }

      // Fallback to priority/location based logic if area is not provided
      if (isPriority) {
        if (spatialLocation.contains('left')) {
          await Vibration.vibrate(pattern: [0, 100, 50, 100], intensities: [0, 255, 0, 100]);
        } else if (spatialLocation.contains('right')) {
          await Vibration.vibrate(pattern: [0, 50, 50, 200], intensities: [0, 100, 0, 255]);
        } else {
          await Vibration.vibrate(duration: 200, amplitude: 255);
        }
      } else {
        await Vibration.vibrate(duration: 50, amplitude: 128);
      }
    } catch (e) {
      debugPrint('Vibration error: $e');
    }
  }

  /// Vibrate for a clear path (positive feedback)
  Future<void> vibrateForClearPath() async {
    if (!_isVibrationEnabled || !_hasVibrator) return;
    
    try {
      // Gentle double tap
      await Vibration.vibrate(pattern: [0, 50, 50, 50], intensities: [0, 80, 0, 80]);
    } catch (e) {
      debugPrint('Clear path vibration error: $e');
    }
  }

  /// Vibrate for obstacle warning (critical)
  Future<void> vibrateForWarning() async {
    if (!_isVibrationEnabled || !_hasVibrator) return;
    
    try {
      // Pattern: strong-strong pause strong-strong
      await Vibration.vibrate(
        pattern: [0, 200, 100, 200, 200, 200],
        intensities: [255, 255, 0, 255, 255, 255],
        repeat: -1,
      );
      
      // Stop after 1 second
      Future.delayed(const Duration(milliseconds: 1000), () {
        Vibration.cancel();
      });
    } catch (e) {
      debugPrint('Warning vibration error: $e');
    }
  }

  /// Vibrate for button press feedback
  Future<void> vibrateForButtonPress() async {
    if (!_isVibrationEnabled || !_hasVibrator) return;
    
    try {
      await Vibration.vibrate(
        duration: 30,
        amplitude: 100,
      );
    } catch (e) {
      debugPrint('Button vibration error: $e');
    }
  }

  /// Vibrate for emergency alert
  Future<void> vibrateForEmergency() async {
    if (!_isVibrationEnabled || !_hasVibrator) return;
    
    try {
      // Continuous strong vibration
      await Vibration.vibrate(
        pattern: [0, 500, 200, 500],
        intensities: [255, 255, 0, 255],
        repeat: 0,
      );
      
      // Stop after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        Vibration.cancel();
      });
    } catch (e) {
      debugPrint('Emergency vibration error: $e');
    }
  }

  /// Stop all vibration
  Future<void> stopVibration() async {
    try {
      await Vibration.cancel();
    } catch (e) {
      debugPrint('Stop vibration error: $e');
    }
  }

  /// Toggle vibration
  void toggleVibration() {
    _isVibrationEnabled = !_isVibrationEnabled;
    notifyListeners();
  }

  /// Enable vibration
  void enableVibration() {
    _isVibrationEnabled = true;
    notifyListeners();
  }

  /// Disable vibration
  void disableVibration() {
    _isVibrationEnabled = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stopVibration();
    super.dispose();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
