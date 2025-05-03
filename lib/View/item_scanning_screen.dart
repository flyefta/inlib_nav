import 'dart:async';
import 'dart:io'; // Για Platform checks
import 'dart:ui' as ui;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import 'package:inlib_nav/View/Painters/text_overlay_painter.dart';
import 'package:inlib_nav/Services/camera_service.dart';

class ItemScanningScreen extends StatefulWidget {
  final String targetCorridorLabel;
  final String targetBookLoc;
  final int targetShelf;

  const ItemScanningScreen({
    super.key,
    required this.targetCorridorLabel,
    required this.targetBookLoc,
    required this.targetShelf,
  });

  @override
  State<ItemScanningScreen> createState() => _ItemScanningScreenState();
}

class _ItemScanningScreenState extends State<ItemScanningScreen> {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  bool _isProcessingOcr = false;
  bool _targetCorridorFound = false;
  bool _instructionSpokenForThisDetection = false;
  Rect? _targetBoundingBox;
  String? _lastDetectedIncorrectCorridorLabel;
  Size? _imageSize;

  late FlutterTts flutterTts;

  Timer? _notFoundTimer;
  bool _notFoundMessageSpoken = false;
  final int _notFoundTimeoutSeconds = 15;

  ui.Image? _correctIcon;
  ui.Image? _wrongIcon;
  bool _iconsLoaded = false;

  final RegExp _corridorRegex = RegExp(
    r'ΔΙΑΔΡΟΜΟΣ\s*(\d+)',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    flutterTts = FlutterTts();
    _initializeTts();
    _loadIcons();
    final cameraService = context.read<CameraService>();
    _initializeCameraSystem(cameraService);
    _startNotFoundTimer();
  }

  Future<void> _initializeCameraSystem(CameraService cameraService) async {
    bool granted = await cameraService.requestPermission();
    if (granted && mounted) {
      await cameraService.initializeController(
        resolutionPreset: ResolutionPreset.high,
        onImageAvailable: _processCameraImage,
      );
    } else if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Η άδεια κάμερας είναι απαραίτητη.')),
      );
    }
  }

  Future<void> _initializeTts() async {
    await flutterTts.setLanguage("el-GR");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
    flutterTts.setErrorHandler((msg) {
      debugPrint("TTS Error: $msg");
    });
  }

  Future<void> _loadIcons() async {
    try {
      final ByteData correctByteData = await rootBundle.load(
        'assets/images/correct_way.png',
      );
      final ByteData wrongByteData = await rootBundle.load(
        'assets/images/wrong_way.png',
      );
      final ui.Codec correctCodec = await ui.instantiateImageCodec(
        correctByteData.buffer.asUint8List(),
      );
      final ui.Codec wrongCodec = await ui.instantiateImageCodec(
        wrongByteData.buffer.asUint8List(),
      );
      final ui.FrameInfo correctFrameInfo = await correctCodec.getNextFrame();
      final ui.FrameInfo wrongFrameInfo = await wrongCodec.getNextFrame();
      if (mounted) {
        setState(() {
          _correctIcon = correctFrameInfo.image;
          _wrongIcon = wrongFrameInfo.image;
          _iconsLoaded = true;
        });
      }
    } catch (e) {
      debugPrint("Error loading icons: $e");
      if (mounted) {
        setState(() {
          _iconsLoaded = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _notFoundTimer?.cancel();
    flutterTts.stop();
    _textRecognizer.close();
    _correctIcon?.dispose();
    _wrongIcon?.dispose();
    super.dispose();
  }

  void _startNotFoundTimer() {
    _notFoundTimer?.cancel();
    _notFoundMessageSpoken = false;
    _notFoundTimer = Timer(Duration(seconds: _notFoundTimeoutSeconds), () {
      if (mounted && !_targetCorridorFound && !_notFoundMessageSpoken) {
        _speak(
          "Ο διάδρομος ${widget.targetCorridorLabel} δεν εντοπίστηκε. Απευθυνθείτε στο προσωπικό της βιβλιοθήκης.",
        );
        if (mounted) {
          setState(() {
            _notFoundMessageSpoken = true;
          });
        }
      }
    });
  }

  void _cancelNotFoundTimer() {
    _notFoundTimer?.cancel();
    _notFoundMessageSpoken = false;
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final cameraService = Provider.of<CameraService>(context, listen: false);
    if (_isProcessingOcr ||
        !mounted ||
        !cameraService.isInitialized ||
        !_iconsLoaded) {
      return;
    }
    _isProcessingOcr = true;

    final sensorOrientation = cameraService.sensorOrientation;
    if (sensorOrientation == null) {
      _isProcessingOcr = false;
      return;
    }

    // Χρήση της *διορθωμένης* μεθόδου
    final inputImage = _inputImageFromCameraImage(image, sensorOrientation);

    if (inputImage != null) {
      if (mounted) {
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      }
      try {
        final RecognizedText recognizedText = await _textRecognizer
            .processImage(inputImage);
        if (mounted) {
          _updateRecognitionResults(recognizedText);
        }
      } catch (e) {
        debugPrint("ML Kit Error: $e");
      } finally {
        if (mounted) {
          _isProcessingOcr = false;
        }
      }
    } else {
      if (mounted) {
        _isProcessingOcr = false;
      }
    }
  }

  void _updateRecognitionResults(RecognizedText recognizedText) {
    if (!mounted) return;

    String? detectedCorridorLabelInFrame;
    Rect? detectedRectInFrame;
    bool targetFoundInFrame = false;
    String? firstWrongLabelInFrame;

    int? targetCorridorNumber;
    final targetMatch = _corridorRegex.firstMatch(widget.targetCorridorLabel);
    if (targetMatch != null && targetMatch.group(1) != null) {
      targetCorridorNumber = int.tryParse(targetMatch.group(1)!);
    }
    if (targetCorridorNumber == null) return;

    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        final match = _corridorRegex.firstMatch(line.text);
        if (match != null && match.group(1) != null) {
          final currentDetectedLabel = match.group(0)!.trim();
          final currentDetectedNumber = int.tryParse(match.group(1)!);
          if (currentDetectedNumber != null) {
            detectedCorridorLabelInFrame = currentDetectedLabel;
            detectedRectInFrame = line.boundingBox;
            if (currentDetectedNumber == targetCorridorNumber) {
              targetFoundInFrame = true;
            } else {
              firstWrongLabelInFrame ??= currentDetectedLabel;
            }
          }
          if (targetFoundInFrame) break;
        }
      }
      if (targetFoundInFrame) break;
    }

    bool updateStateNeeded = false;

    if (targetFoundInFrame && detectedRectInFrame != null) {
      _cancelNotFoundTimer();
      if (!_targetCorridorFound || _targetBoundingBox != detectedRectInFrame) {
        updateStateNeeded = true;
      }
      _targetCorridorFound = true;
      _targetBoundingBox = detectedRectInFrame;
      _lastDetectedIncorrectCorridorLabel = null;

      if (!_instructionSpokenForThisDetection) {
        String shelfSide =
            widget.targetShelf % 2 != 0 ? "στα αριστερά" : "στα δεξιά";
        final String speechText =
            "Βρέθηκε ο $detectedCorridorLabelInFrame. Το ράφι ${widget.targetShelf} είναι $shelfSide σας.";
        _speak(speechText);
        Vibration.hasVibrator().then((has) {
          if (has == true) {
            Vibration.vibrate(duration: 200);
          }
        });
        _instructionSpokenForThisDetection = true;
        updateStateNeeded = true;
      }
    } else {
      if (_targetCorridorFound) {
        _targetCorridorFound = false;
        _targetBoundingBox = null;
        _instructionSpokenForThisDetection = false;
        _startNotFoundTimer();
        updateStateNeeded = true;
      }

      if (detectedCorridorLabelInFrame != null &&
          detectedRectInFrame != null &&
          !targetFoundInFrame) {
        if (_lastDetectedIncorrectCorridorLabel !=
            detectedCorridorLabelInFrame) {
          _lastDetectedIncorrectCorridorLabel = detectedCorridorLabelInFrame;
          _targetBoundingBox = detectedRectInFrame;
          updateStateNeeded = true;
        }
      } else if (detectedCorridorLabelInFrame == null) {
        if (_lastDetectedIncorrectCorridorLabel != null ||
            _targetBoundingBox != null) {
          _lastDetectedIncorrectCorridorLabel = null;
          _targetBoundingBox = null;
          updateStateNeeded = true;
        }
      }
    }

    if (updateStateNeeded && mounted) {
      setState(() {});
    }
  }

  Future<void> _speak(String text) async {
    try {
      await flutterTts.speak(text);
    } catch (e) {
      debugPrint("TTS Error speaking: $e");
    }
  }

  // --- ΔΙΟΡΘΩΜΕΝΗ ΜΕΘΟΔΟΣ ---
  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    int sensorOrientation,
  ) {
    final InputImageRotation imageRotation =
        InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation0deg;

    final InputImageFormat? inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw);

    if (inputImageFormat == null ||
        (Platform.isAndroid && inputImageFormat != InputImageFormat.nv21) ||
        (Platform.isIOS && inputImageFormat != InputImageFormat.bgra8888)) {
      debugPrint('Warning: Unsupported image format: ${image.format.group}');
      return null;
    }

    if (image.planes.isEmpty) {
      debugPrint('Warning: Image has no planes!');
      return null;
    }
    final plane = image.planes.first;
    final bytes = plane.bytes;

    final Size imageSize = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final InputImageMetadata inputImageData = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: plane.bytesPerRow,
    );

    try {
      return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
    } catch (e) {
      debugPrint("Error creating InputImage: $e");
      return null;
    }
  }
  // --- ΤΕΛΟΣ ΔΙΟΡΘΩΜΕΝΗΣ ΜΕΘΟΔΟΥ ---

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraService>(
      builder: (context, cameraService, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text("Αναζήτηση: ${widget.targetCorridorLabel}"),
          ),
          body: _buildScannerBody(cameraService),
        );
      },
    );
  }

  Widget _buildScannerBody(CameraService cameraService) {
    if (!cameraService.isPermissionGranted) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Απαιτείται άδεια κάμερας.'),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed:
                  () => cameraService.requestPermission().then((granted) {
                    if (granted && mounted) {
                      _initializeCameraSystem(cameraService);
                    }
                  }),
              child: const Text('Χορήγηση Άδειας'),
            ),
          ],
        ),
      );
    }

    if (!cameraService.isInitialized || !_iconsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (cameraService.errorMessage != null) {
      return Center(
        child: Text('Σφάλμα κάμερας: ${cameraService.errorMessage}'),
      );
    }

    final previewSize = cameraService.previewSize;
    if (previewSize == null || previewSize.isEmpty) {
      return const Center(child: Text("Σφάλμα μεγέθους προεπισκόπησης"));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        double scale = constraints.maxWidth / previewSize.width;
        var cameraWidgetHeight = previewSize.height * scale;
        if (cameraWidgetHeight > constraints.maxHeight) {
          cameraWidgetHeight = constraints.maxHeight;
          scale = cameraWidgetHeight / previewSize.height;
        }
        var cameraWidgetWidth = previewSize.width * scale;

        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: cameraWidgetWidth,
              height: cameraWidgetHeight,
              child: CameraPreview(cameraService.controller!),
            ),
            if (_imageSize != null)
              SizedBox(
                width: cameraWidgetWidth,
                height: cameraWidgetHeight,
                child: CustomPaint(
                  painter: TextOverlayPainter(
                    targetBoundingBox: _targetBoundingBox,
                    imageSize: _imageSize!,
                    previewSize: previewSize,
                    scale: scale,
                    isTargetFound: _targetCorridorFound,
                    correctIcon: _correctIcon,
                    wrongIcon: _wrongIcon,
                    isWrongTargetFound:
                        !_targetCorridorFound &&
                        _lastDetectedIncorrectCorridorLabel != null,
                  ),
                ),
              ),
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8.0,
                  horizontal: 12.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  _targetCorridorFound
                      ? 'ΒΡΕΘΗΚΕ: ${widget.targetCorridorLabel}!'
                      : _notFoundMessageSpoken
                      ? 'Ο διάδρομος δεν εντοπίστηκε.'
                      : _lastDetectedIncorrectCorridorLabel != null
                      ? 'Βλέπω: $_lastDetectedIncorrectCorridorLabel. Ψάχνω: ${widget.targetCorridorLabel}'
                      : 'Σάρωση για ${widget.targetCorridorLabel}...',
                  style: TextStyle(
                    color:
                        _targetCorridorFound
                            ? Colors.lightGreenAccent
                            : _notFoundMessageSpoken
                            ? Colors.orangeAccent
                            : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
} // Τέλος _ItemScanningScreenState
