import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:ai_vision_pro/features/ai/nvidia_ai_service.dart';
import 'dart:async';

class AppDetectedObject {
  final String label;
  final double confidence;
  final Rect? boundingBox;
  final DateTime detectedAt;
  final DistanceLevel distanceLevel;
  final String spatialLocation;

  AppDetectedObject({
    required this.label,
    required this.confidence,
    this.boundingBox,
    required this.detectedAt,
    required this.distanceLevel,
    this.spatialLocation = 'center',
  });

  String get distanceDescription {
    switch (distanceLevel) {
      case DistanceLevel.close: return 'close';
      case DistanceLevel.medium: return 'at medium distance';
      case DistanceLevel.far: return 'far away';
    }
  }
}

enum DistanceLevel { close, medium, far }
enum ObstaclePriority { critical, high, medium, low }

class DetectionProvider extends ChangeNotifier {
  // ── ML Kit Object Detector (bounding boxes + spatial tracking) ──
  final ObjectDetector _objectDetector = ObjectDetector(
    options: ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    ),
  );

  // ── ML Kit Image Labeler (400+ specific labels — the core engine) ──
  // Use a LOW threshold here so we catch everything; we smart-filter later.
  final ImageLabeler _imageLabeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.40),
  );

  final TextRecognizer _textRecognizer = TextRecognizer();

  bool _isProcessing = false;
  bool _isDetectionEnabled = true;
  bool _isOcrEnabled = false;
  String? _error;

  final Map<String, DateTime> _lastAnnouncedObjects = {};
  final Set<String> _recentlyAnnouncedObjects = {};

  // Faster frame processing for more responsive detection (300ms gap)
  static const Duration _processingInterval = Duration(milliseconds: 300);
  DateTime? _lastProcessingTime;

  List<AppDetectedObject> _currentDetections = [];
  List<AppDetectedObject> _ocrResults = [];

  /// Store last camera image dimensions for bounding box scaling
  int _lastImageWidth = 0;
  int _lastImageHeight = 0;

  Function(List<AppDetectedObject>)? onNewDetection;
  Function(String)? onSpeakText;

  final OnDeviceAIService _onDeviceAI = OnDeviceAIService();

  // ──────────────────────────────────────────────────────────────────
  // LABEL REFINEMENT MAP
  // ML Kit often returns generic labels like "Electronic device" or
  // "Gadget". This map upgrades generic labels to specific, useful
  // names that a blind user would actually want to hear.
  // ──────────────────────────────────────────────────────────────────
  static const Map<String, String> _labelRefinements = {
    // Electronics
    'electronic device': 'Electronic Device',
    'gadget': 'Electronic Device',
    'personal computer': 'Computer',
    'desktop computer': 'Desktop Computer',
    'computer monitor': 'Monitor',
    'display': 'Monitor Screen',
    'screen': 'Screen',
    'output device': 'Monitor',
    'input device': 'Keyboard or Mouse',
    'computer keyboard': 'Keyboard',
    'peripheral': 'Computer Accessory',
    'netbook': 'Laptop',
    'tablet computer': 'Tablet',
    'tablet': 'Tablet',
    'mobile phone': 'Mobile Phone',
    'smartphone': 'Mobile Phone',
    'portable communications device': 'Mobile Phone',
    'communication device': 'Mobile Phone',
    'telephony': 'Phone',
    'telephone': 'Phone',
    'feature phone': 'Phone',
    'computer hardware': 'Computer Hardware',
    'computer component': 'Computer Component',

    // Cables & Wires
    'wire': 'Wire',
    'cable': 'Cable',
    'electrical wiring': 'Electrical Wire',
    'power cord': 'Power Cable',
    'electrical supply': 'Power Cable',
    'networking cables': 'Network Cable',
    'usb cable': 'USB Cable',
    'data transfer cable': 'Data Cable',
    'charger': 'Charger',
    'electronic engineering': 'Circuit Board',

    // Money (Indian context)
    'banknote': 'Rupee Note',
    'money': 'Money',
    'cash': 'Cash',
    'currency': 'Currency Note',
    'paper': 'Paper',
    'coin': 'Coin',
    'paper product': 'Paper',

    // Furniture
    'furniture': 'Furniture',
    'table': 'Table',
    'desk': 'Desk',
    'chair': 'Chair',
    'office chair': 'Office Chair',
    'couch': 'Sofa',
    'sofa bed': 'Sofa',
    'bed': 'Bed',
    'shelf': 'Shelf',
    'bookcase': 'Bookshelf',
    'cupboard': 'Cupboard',
    'cabinetry': 'Cabinet',
    'cabinet': 'Cabinet',
    'drawer': 'Drawer',
    'chest of drawers': 'Drawer Chest',
    'nightstand': 'Bedside Table',

    // Common objects
    'bottle': 'Bottle',
    'water bottle': 'Water Bottle',
    'drinking water': 'Water Bottle',
    'glass': 'Glass',
    'drinkware': 'Glass',
    'cup': 'Cup',
    'mug': 'Mug',
    'tableware': 'Tableware',
    'serveware': 'Serving Dish',
    'plate': 'Plate',
    'bowl': 'Bowl',
    'cutlery': 'Cutlery',
    'fork': 'Fork',
    'kitchen knife': 'Knife',
    'spoon': 'Spoon',
    'kitchen utensil': 'Kitchen Utensil',
    'cookware and bakeware': 'Cooking Pot',

    // Bags & Accessories
    'bag': 'Bag',
    'handbag': 'Handbag',
    'backpack': 'Backpack',
    'luggage and bags': 'Luggage',
    'suitcase': 'Suitcase',
    'wallet': 'Wallet',
    'fashion accessory': 'Accessory',

    // Clothing
    'clothing': 'Clothing',
    'jacket': 'Jacket',
    'shirt': 'Shirt',
    'jeans': 'Jeans',
    'outerwear': 'Jacket',
    'footwear': 'Shoes',
    'shoe': 'Shoe',
    'sandal': 'Sandal',
    'boot': 'Boot',
    'hat': 'Hat',
    'glasses': 'Glasses',
    'sunglasses': 'Sunglasses',
    'goggles': 'Goggles',
    'watch': 'Watch',
    'wrist': 'Watch',

    // People & Body
    'person': 'Person',
    'human face': 'Face',
    'face': 'Face',
    'human body': 'Person',
    'human head': 'Person',
    'head': 'Person',
    'hand': 'Hand',
    'finger': 'Hand',
    'arm': 'Arm',
    'human leg': 'Person',
    'people': 'People',
    'man': 'Person',
    'woman': 'Person',
    'child': 'Child',
    'girl': 'Girl',
    'boy': 'Boy',
    'beard': 'Person with Beard',
    'smile': 'Smiling Face',
    'selfie': 'Person',
    'human ear': 'Person',

    // Vehicles
    'vehicle': 'Vehicle',
    'car': 'Car',
    'motor vehicle': 'Vehicle',
    'land vehicle': 'Vehicle',
    'automobile': 'Car',
    'truck': 'Truck',
    'bus': 'Bus',
    'motorcycle': 'Motorcycle',
    'bicycle': 'Bicycle',
    'wheel': 'Wheel',
    'tire': 'Tire',
    'vehicle door': 'Car Door',
    'bumper': 'Car Bumper',
    'auto part': 'Vehicle Part',
    'automotive design': 'Vehicle',
    'automotive exterior': 'Vehicle',

    // Building & Room
    'door': 'Door',
    'window': 'Window',
    'building': 'Building',
    'house': 'House',
    'wall': 'Wall',
    'floor': 'Floor',
    'ceiling': 'Ceiling',
    'stairs': 'Stairs',
    'room': 'Room',
    'interior design': 'Room Interior',
    'property': 'Building',
    'architecture': 'Building',
    'wood': 'Wooden Surface',
    'hardwood': 'Wooden Floor',
    'flooring': 'Floor',
    'fixture': 'Light Fixture',
    'light': 'Light',
    'lamp': 'Lamp',
    'lighting': 'Light',
    'ceiling fixture': 'Ceiling Light',
    'curtain': 'Curtain',
    'window blind': 'Window Blind',
    'tile': 'Tile',
    'door handle': 'Door Handle',
    'handle': 'Handle',

    // Kitchen & Appliance
    'kitchen': 'Kitchen',
    'kitchen appliance': 'Kitchen Appliance',
    'home appliance': 'Home Appliance',
    'small appliance': 'Small Appliance',
    'refrigerator': 'Refrigerator',
    'microwave oven': 'Microwave',
    'toaster': 'Toaster',
    'oven': 'Oven',
    'blender': 'Blender',
    'mixer': 'Mixer',
    'sink': 'Sink',
    'tap': 'Tap',
    'plumbing fixture': 'Tap',
    'stove': 'Stove',
    'gas stove': 'Gas Stove',
    'countertop': 'Kitchen Counter',
    'kitchen sink': 'Kitchen Sink',

    // Stationery & Office
    'book': 'Book',
    'publication': 'Book',
    'text': 'Printed Text',
    'font': 'Printed Text',
    'document': 'Document',
    'notebook': 'Notebook',
    'pen': 'Pen',
    'pencil': 'Pencil',
    'writing implement': 'Pen',
    'office supplies': 'Office Supplies',
    'scissors': 'Scissors',
    'ruler': 'Ruler',
    'sticky note': 'Sticky Note',

    // Nature & Animals
    'plant': 'Plant',
    'houseplant': 'Indoor Plant',
    'potted plant': 'Potted Plant',
    'flower': 'Flower',
    'tree': 'Tree',
    'leaf': 'Leaf',
    'grass': 'Grass',
    'garden': 'Garden',
    'dog': 'Dog',
    'cat': 'Cat',
    'bird': 'Bird',
    'animal': 'Animal',
    'pet': 'Pet',
    'mammal': 'Animal',

    // Food & Drink
    'food': 'Food',
    'fruit': 'Fruit',
    'vegetable': 'Vegetable',
    'dish': 'Food Dish',
    'meal': 'Meal',
    'cuisine': 'Food',
    'fast food': 'Fast Food',
    'snack': 'Snack',
    'baked goods': 'Baked Food',
    'bread': 'Bread',
    'ingredient': 'Food Item',
    'produce': 'Fresh Produce',
    'natural foods': 'Fresh Food',
    'staple food': 'Staple Food',
    'dairy': 'Dairy Product',
    'drink': 'Drink',
    'juice': 'Juice',
    'beverage': 'Beverage',
    'coffee': 'Coffee',
    'tea': 'Tea',
    'alcohol': 'Alcoholic Drink',
    'wine': 'Wine',
    'beer': 'Beer',
    'soft drink': 'Soft Drink',
    'carbonated soft drinks': 'Soft Drink',

    // Sports & Outdoor
    'ball': 'Ball',
    'sports equipment': 'Sports Equipment',
    'bicycle wheel': 'Bicycle Wheel',

    // Bathroom
    'bathroom': 'Bathroom',
    'toilet': 'Toilet',
    'bathtub': 'Bathtub',
    'soap': 'Soap',
    'towel': 'Towel',
    'mirror': 'Mirror',
    'bathroom accessory': 'Bathroom Item',

    // Miscellaneous
    'toy': 'Toy',
    'teddy bear': 'Teddy Bear',
    'stuffed toy': 'Stuffed Toy',
    'clock': 'Clock',
    'alarm clock': 'Alarm Clock',
    'vase': 'Vase',
    'umbrella': 'Umbrella',
    'fan': 'Fan',
    'ceiling fan': 'Ceiling Fan',
    'mechanical fan': 'Fan',
    'air conditioning': 'Air Conditioner',
    'remote control': 'Remote Control',
    'musical instrument': 'Musical Instrument',
    'guitar': 'Guitar',
    'piano': 'Piano',
    'drum': 'Drum',
    'headphones': 'Headphones',
    'audio equipment': 'Speaker',
    'speaker': 'Speaker',
    'earphone': 'Earphones',
    'microphone': 'Microphone',
    'flashlight': 'Flashlight',
    'tool': 'Tool',
    'wrench': 'Wrench',
    'screwdriver': 'Screwdriver',
    'hammer': 'Hammer',
    'box': 'Box',
    'packaging': 'Package',
    'envelope': 'Envelope',
    'plastic bag': 'Plastic Bag',
    'plastic': 'Plastic Item',
    'metal': 'Metal Object',
    'pillow': 'Pillow',
    'blanket': 'Blanket',
    'textile': 'Cloth',
    'fabric': 'Cloth',
    'linens': 'Bed Sheet',
    'carpet': 'Carpet',
    'mat': 'Mat',
    'rug': 'Rug',
    'flag': 'Flag',
    'sign': 'Sign Board',
    'poster': 'Poster',
    'picture frame': 'Photo Frame',
    'painting': 'Painting',
    'art': 'Artwork',
    'photograph': 'Photograph',
    'snapshot': 'Photo',
    'photo': 'Photo',
    'map': 'Map',
    'calendar': 'Calendar',
    'key': 'Key',
    'lock': 'Lock',
    'padlock': 'Padlock',
    'ring': 'Ring',
    'necklace': 'Necklace',
    'jewellery': 'Jewellery',
    'basket': 'Basket',
    'bucket': 'Bucket',
    'trash can': 'Dustbin',
    'waste container': 'Dustbin',
    'waste containment': 'Dustbin',

    // Generic ML Kit noise labels to SUPPRESS — these add no value
    'rectangle': '',
    'line': '',
    'parallel': '',
    'pattern': '',
    'symmetry': '',
    'circle': '',
    'triangle': '',
    'material property': '',
    'colorfulness': '',
    'tints and shades': '',
    'electric blue': '',
    'magenta': '',
    'event': '',
    'leisure': '',
    'fun': '',
    'happy': '',
    'cool': '',
    'comfort': '',
    'darkness': '',
    'midnight': '',
    'space': '',
    'sky': '',
    'cloud': '',
    'horizon': '',
    'landscape': '',
    'number': '',
    'logo': '',
    'brand': '',
    'graphics': '',
    'graphic design': '',
    'visual arts': '',
    'illustration': '',
    'animation': '',
    'fictional character': '',
    'science': '',
    'technology': '',
    'engineering': '',
    'machine': '',
    'service': '',
    'automotive tire': '',
  };

  // Labels to skip entirely (abstract / noise from ML Kit)
  static const Set<String> _suppressedLabels = {
    'rectangle', 'line', 'parallel', 'pattern', 'symmetry', 'circle',
    'triangle', 'material property', 'colorfulness', 'tints and shades',
    'electric blue', 'magenta', 'event', 'leisure', 'fun', 'happy', 'cool',
    'comfort', 'darkness', 'midnight', 'space', 'number', 'logo', 'brand',
    'graphics', 'graphic design', 'visual arts', 'illustration', 'animation',
    'fictional character', 'science', 'technology', 'engineering', 'machine',
    'service', 'automotive tire', 'sky', 'cloud', 'horizon', 'landscape',
    'font', 'snapshot', 'photography', 'stock photography',
  };

  static const List<String> _priorityObjects = [
    'person', 'people', 'human', 'face', 'child',
    'vehicle', 'car', 'truck', 'bus', 'motorcycle', 'bicycle',
    'door', 'gate', 'entrance',
    'stairs', 'step', 'ladder',
    'chair', 'table', 'desk', 'computer', 'pc', 'monitor',
    'laptop', 'mobile phone', 'phone',
    'obstacle', 'wire', 'cable',
    'knife', 'scissors',
  ];

  bool get isProcessing => _isProcessing;
  bool get isDetectionEnabled => _isDetectionEnabled;
  bool get isOcrEnabled => _isOcrEnabled;
  bool get hasError => _error != null;
  String? get error => _error;
  List<AppDetectedObject> get currentDetections => _currentDetections;
  List<AppDetectedObject> get ocrResults => _ocrResults;
  int get lastImageWidth => _lastImageWidth;
  int get lastImageHeight => _lastImageHeight;

  /// Refine a raw ML Kit label into a user-friendly, specific name.
  /// Returns empty string for labels that should be suppressed.
  String _refineLabel(String rawLabel) {
    final lower = rawLabel.toLowerCase().trim();

    // 1. Check suppression list first
    if (_suppressedLabels.contains(lower)) return '';

    // 2. Check refinement map
    if (_labelRefinements.containsKey(lower)) {
      return _labelRefinements[lower]!;
    }

    // 3. Capitalize first letter of each word for unknown labels
    return rawLabel
        .split(' ')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }

  Future<void> processImage(CameraImage image) async {
    if (!_isDetectionEnabled || _isProcessing) return;

    final now = DateTime.now();
    if (_lastProcessingTime != null) {
      final elapsed = now.difference(_lastProcessingTime!);
      if (elapsed < _processingInterval) return;
    }
    _lastProcessingTime = now;

    try {
      _isProcessing = true;

      // Store image dimensions for bounding box scaling on the UI side
      _lastImageWidth = image.width;
      _lastImageHeight = image.height;

      final inputImage = _convertCameraImageToInputImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      // ════════════════════════════════════════════════════════
      // Run BOTH detectors in parallel for max speed
      // ════════════════════════════════════════════════════════
      final results = await Future.wait([
        _objectDetector.processImage(inputImage),
        _imageLabeler.processImage(inputImage),
      ]);

      final List<DetectedObject> objects = results[0] as List<DetectedObject>;
      final List<ImageLabel> imageLabels = results[1] as List<ImageLabel>;

      final List<AppDetectedObject> newDetections = <AppDetectedObject>[];
      final Set<String> addedLabels = {}; // track to deduplicate

      // ── STEP 1: Image Labeling first (400+ specific labels) ──
      // This is the PRIMARY source for accurate names like "Laptop",
      // "Computer Keyboard", "Banknote", "Wire", etc.
      for (final ImageLabel label in imageLabels) {
        if (label.confidence < 0.45) continue; // Accept 45%+ (filtered further below)

        final refined = _refineLabel(label.label);
        if (refined.isEmpty) continue; // Suppressed noise label

        final lowerRefined = refined.toLowerCase();
        if (addedLabels.contains(lowerRefined)) continue;

        addedLabels.add(lowerRefined);
        newDetections.add(AppDetectedObject(
          label: refined,
          confidence: label.confidence,
          boundingBox: null, // Image labeling has no bounding boxes
          detectedAt: DateTime.now(),
          distanceLevel: DistanceLevel.medium,
          spatialLocation: 'in the scene',
        ));
      }

      // ── STEP 2: Object Detection (bounding boxes + spatial info) ──
      // This gives us WHERE objects are and HOW FAR, and may add a few
      // extra labels. We merge & upgrade existing labels with spatial data.
      for (final DetectedObject obj in objects) {
        final spatialLoc = _getSpatialLocation(obj.boundingBox, image.width.toDouble());
        final distanceLevel = _estimateDistance(obj.boundingBox);

        if (obj.labels.isNotEmpty) {
          final sortedLabels = List.of(obj.labels)
            ..sort((a, b) => b.confidence.compareTo(a.confidence));
          final bestLabel = sortedLabels.first;

          if (bestLabel.confidence >= 0.40) {
            final refined = _refineLabel(bestLabel.text);
            if (refined.isEmpty) continue;

            final lowerRefined = refined.toLowerCase();

            // Check if Image Labeling already found this — if so, UPGRADE it
            // with bounding box + spatial info instead of adding a duplicate.
            final existingIdx = newDetections.indexWhere(
                (d) => d.label.toLowerCase() == lowerRefined);

            if (existingIdx >= 0) {
              // Upgrade: replace the label-only entry with one that has spatial data
              final existing = newDetections[existingIdx];
              newDetections[existingIdx] = AppDetectedObject(
                label: existing.label,
                confidence: existing.confidence > bestLabel.confidence
                    ? existing.confidence
                    : bestLabel.confidence,
                boundingBox: obj.boundingBox,
                detectedAt: DateTime.now(),
                distanceLevel: distanceLevel,
                spatialLocation: spatialLoc,
              );
            } else if (!addedLabels.contains(lowerRefined)) {
              addedLabels.add(lowerRefined);
              newDetections.add(AppDetectedObject(
                label: refined,
                confidence: bestLabel.confidence,
                boundingBox: obj.boundingBox,
                detectedAt: DateTime.now(),
                distanceLevel: distanceLevel,
                spatialLocation: spatialLoc,
              ));
            }
          }
        } else {
          // Unlabeled spatial detection — report as obstacle for safety
          if (!addedLabels.contains('obstacle')) {
            addedLabels.add('obstacle');
            newDetections.add(AppDetectedObject(
              label: 'Obstacle',
              confidence: 0.50,
              boundingBox: obj.boundingBox,
              detectedAt: DateTime.now(),
              distanceLevel: distanceLevel,
              spatialLocation: spatialLoc,
            ));
          }
        }
      }

      // ── STEP 3: Sort by confidence (highest first) ──
      newDetections.sort((a, b) => b.confidence.compareTo(a.confidence));

      // ── STEP 4: Cap at top 8 to avoid UI clutter & TTS overload ──
      if (newDetections.length > 8) {
        _currentDetections = newDetections.sublist(0, 8);
      } else {
        _currentDetections = newDetections;
      }

      if (onNewDetection != null) onNewDetection!(_currentDetections);
      await _handleSmartAnnouncement(_currentDetections);

      if (_isOcrEnabled) {
        await _processOcr(inputImage);
      }
    } catch (e) {
      _error = 'Detection error: $e';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  String _getSpatialLocation(Rect boundingBox, double imageWidth) {
    final centerX = boundingBox.center.dx;
    final third = imageWidth / 3;
    if (centerX < third) return 'on your left';
    else if (centerX < 2 * third) return 'in front of you';
    else return 'on your right';
  }

  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final imageRotation = InputImageRotationValue.fromRawValue(0) ?? InputImageRotation.rotation0deg;
      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
    } catch (e) {
      debugPrint('Error converting image: $e');
    }
    return null;
  }

  Future<void> _processOcr(InputImage inputImage) async {
    try {
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      _ocrResults.clear();
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          if (line.text.trim().isNotEmpty) {
            _ocrResults.add(AppDetectedObject(
              label: line.text.trim(),
              confidence: 1.0,
              boundingBox: line.boundingBox,
              detectedAt: DateTime.now(),
              distanceLevel: DistanceLevel.medium,
            ));
          }
        }
      }
      if (_ocrResults.isNotEmpty && onSpeakText != null) {
        final textToRead = _ocrResults.map((r) => r.label).join('. ');
        onSpeakText!('Text detected: $textToRead');
      }
    } catch (e) {
      debugPrint('OCR error: $e');
    }
  }

  DistanceLevel _estimateDistance(Rect? boundingBox) {
    if (boundingBox == null) return DistanceLevel.medium;
    final area = boundingBox.width * boundingBox.height;
    if (area > 100000) return DistanceLevel.close;
    else if (area > 30000) return DistanceLevel.medium;
    else return DistanceLevel.far;
  }

  Future<void> _handleSmartAnnouncement(List<AppDetectedObject> detections) async {
    if (onSpeakText == null || detections.isEmpty) return;

    final priorityDetections = <AppDetectedObject>[];
    final regularDetections = <AppDetectedObject>[];

    for (final detection in detections) {
      if (_isPriorityObject(detection.label)) {
        priorityDetections.add(detection);
      } else {
        regularDetections.add(detection);
      }
    }

    priorityDetections.sort((a, b) => b.confidence.compareTo(a.confidence));
    regularDetections.sort((a, b) => b.confidence.compareTo(a.confidence));

    // Announce up to 2 priority objects
    for (final detection in priorityDetections.take(2)) {
      if (_shouldAnnounce(detection.label)) {
        await _announceObject(detection);
        return;
      }
    }

    // If no priority objects, announce the top regular detection
    if (priorityDetections.isEmpty) {
      for (final detection in regularDetections.take(1)) {
        if (_shouldAnnounce(detection.label)) {
          await _announceObject(detection);
          return;
        }
      }
    }
  }

  bool _shouldAnnounce(String label) {
    final now = DateTime.now();
    if (_recentlyAnnouncedObjects.contains(label)) return false;
    final lastAnnounced = _lastAnnouncedObjects[label];
    if (lastAnnounced != null) {
      final elapsed = now.difference(lastAnnounced);
      final minInterval = _isPriorityObject(label)
          ? const Duration(seconds: 3)
          : const Duration(seconds: 5);
      if (elapsed < minInterval) return false;
    }
    return true;
  }

  /// Announce detected object with its label, position, and distance
  Future<void> _announceObject(AppDetectedObject detection) async {
    final now = DateTime.now();
    _lastAnnouncedObjects[detection.label] = now;
    _recentlyAnnouncedObjects.add(detection.label);

    Future.delayed(const Duration(seconds: 5), () {
      _recentlyAnnouncedObjects.remove(detection.label);
    });

    final message = '${detection.label} ${detection.spatialLocation}, ${detection.distanceDescription}';
    if (onSpeakText != null) onSpeakText!(message);
  }

  bool _isPriorityObject(String label) {
    final lowerLabel = label.toLowerCase();
    return _priorityObjects.any((priority) => lowerLabel.contains(priority));
  }

  ObstaclePriority getObstaclePriority(String label) {
    final lowerLabel = label.toLowerCase();
    if (lowerLabel.contains('person') || lowerLabel.contains('vehicle') || lowerLabel.contains('car')) {
      return ObstaclePriority.critical;
    }
    if (lowerLabel.contains('door') || lowerLabel.contains('stairs') || lowerLabel.contains('wire') || lowerLabel.contains('cable')) {
      return ObstaclePriority.high;
    }
    if (lowerLabel.contains('chair') || lowerLabel.contains('table') || lowerLabel.contains('pc') ||
        lowerLabel.contains('computer') || lowerLabel.contains('laptop') || lowerLabel.contains('phone')) {
      return ObstaclePriority.medium;
    }
    return ObstaclePriority.low;
  }

  void toggleDetection() {
    _isDetectionEnabled = !_isDetectionEnabled;
    notifyListeners();
  }

  void toggleOcr() {
    _isOcrEnabled = !_isOcrEnabled;
    notifyListeners();
  }

  void clearRecentAnnouncements() {
    _recentlyAnnouncedObjects.clear();
    _lastAnnouncedObjects.clear();
  }

  /// Describe surroundings using on-device detections only (no cloud API)
  Future<void> describeSurroundings() async {
    clearRecentAnnouncements();

    if (_currentDetections.isEmpty) {
      if (onSpeakText != null) onSpeakText!('No objects detected currently');
      return;
    }

    final labels = _currentDetections.map((d) => d.label).toList();
    final description = _onDeviceAI.describeScene(labels);
    if (onSpeakText != null) onSpeakText!(description);
  }

  @override
  void dispose() {
    _objectDetector.close();
    _imageLabeler.close();
    _textRecognizer.close();
    super.dispose();
  }
}