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
import 'package:inlib_nav/constants.dart'; // * ΝΕΟ: Import για την myAppBar

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
  CameraService? _cameraServiceInstance; // Για ασφαλή πρόσβαση στη dispose

  Timer? _notFoundTimer;
  bool _notFoundMessageSpoken = false;
  final int _notFoundTimeoutSeconds = 15;

  ui.Image? _correctIcon;
  ui.Image? _wrongIcon;
  bool _iconsLoaded = false;

  DateTime _lastProcessedFrameTime = DateTime.now().subtract(
    const Duration(seconds: 1),
  );
  final Duration _frameProcessingInterval = const Duration(
    milliseconds: 500,
  ); // Προσαρμόστε (π.χ. 300-700ms για OCR)

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
      // Ξεκινάμε το stream εδώ αν ο controller αρχικοποιήθηκε σωστά
      if (mounted &&
          cameraService.isInitialized &&
          !cameraService.isStreamingImages) {
        await cameraService.startImageStream(_processCameraImage);
      }
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
          _iconsLoaded =
              true; // Ακόμα κι αν υπάρχει σφάλμα, για να μη κολλήσει στο loading
        });
      }
    }
  }

  @override
  void dispose() {
    debugPrint("Disposing ItemScanningScreen");

    // Ακύρωση timers
    _notFoundTimer?.cancel();

    // Διακοπή TTS
    flutterTts.stop();

    // Κλείσιμο του TextRecognizer
    _textRecognizer.close();

    // Απελευθέρωση των ui.Image (εικονιδίων)
    _correctIcon?.dispose();
    _wrongIcon?.dispose();

    // Διακοπή της ροής εικόνων μέσω του CameraService
    try {
      if (_cameraServiceInstance != null &&
          _cameraServiceInstance!.isInitialized &&
          _cameraServiceInstance!.isStreamingImages) {
        _cameraServiceInstance!.stopImageStream().catchError((e) {
          debugPrint(
            "Error stopping image stream in dispose for ItemScanningScreen: $e",
          );
        });
        debugPrint("Image stream stop requested for ItemScanningScreen");
      }
    } catch (e) {
      debugPrint(
        "Error accessing CameraService in dispose for ItemScanningScreen: $e",
      );
    }

    super.dispose();
    debugPrint("ItemScanningScreen disposed successfully");
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

  // Επεξεργασία καρέ από την κάμερα για OCR (Text Recognition)
  Future<void> _processCameraImage(CameraImage image) async {
    // Έλεγχοι για αποφυγή περιττής επεξεργασίας ή επεξεργασίας σε unmounted widget
    if (!mounted || _isProcessingOcr || !_iconsLoaded) {
      // Ελέγχουμε και το _iconsLoaded
      // Δεν υπάρχει _finalTargetFoundAndHandled εδώ, εκτός αν το προσθέσετε για συγκεκριμένη λογική
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastProcessedFrameTime) < _frameProcessingInterval) {
      return; // Παράλειψη καρέ
    }
    _lastProcessedFrameTime =
        now; // Ενημέρωση του χρόνου τελευταίας επεξεργασίας

    _isProcessingOcr = true; // Σημαδεύουμε ότι ξεκίνησε η επεξεργασία

    // Λήψη του CameraService (αν δεν το έχετε ήδη ως μεταβλητή μέλους)
    // final cameraService = Provider.of<CameraService>(context, listen: false);
    // Αν το _cameraServiceInstance είναι ήδη αρχικοποιημένο, χρησιμοποιήστε το:
    final cameraService = _cameraServiceInstance;
    if (cameraService == null || !cameraService.isInitialized) {
      _isProcessingOcr = false;
      return;
    }

    final sensorOrientation = cameraService.sensorOrientation;
    if (sensorOrientation == null) {
      _isProcessingOcr = false;
      debugPrint("Sensor orientation is null, cannot process OCR image.");
      return;
    }

    final inputImage = _inputImageFromCameraImage(image, sensorOrientation);

    if (inputImage != null) {
      // Ενημέρωση του _imageSize για τον painter
      // Γίνεται και πριν την κλήση του ML Kit για να είναι διαθέσιμο στον painter
      // ακόμα κι αν η επεξεργασία του ML Kit πάρει χρόνο ή αποτύχει.
      if (mounted) {
        // Η CameraImage έχει τις διαστάσεις όπως έρχονται από τον αισθητήρα.
        // Η InputImageMetadata λαμβάνει αυτές τις διαστάσεις και τον rotation.
        // Ο painter θα χρειαστεί τις διαστάσεις της *αρχικής* εικόνας και το rotation/scale.
        // Το _imageSize πρέπει να αντικατοπτρίζει τις διαστάσεις της εικόνας που πήγε στο ML Kit *πριν* το rotation που εφαρμόζει το ίδιο το ML Kit.
        // Για τον TextOverlayPainter, το imageSize πρέπει να είναι το μέγεθος της εικόνας όπως την "βλέπει" το ML Kit.
        if (sensorOrientation == 90 || sensorOrientation == 270) {
          // Αν η εικόνα περιστρέφεται κατά 90/270 για το ML Kit, οι διαστάσεις αντιστρέφονται
          _imageSize = Size(image.height.toDouble(), image.width.toDouble());
        } else {
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        }
      }

      try {
        final RecognizedText recognizedText = await _textRecognizer
            .processImage(inputImage);
        if (mounted) {
          // Έλεγχος mounted ξανά πριν την κλήση της _updateRecognitionResults
          _updateRecognitionResults(recognizedText);
        }
      } catch (e) {
        debugPrint("ML Kit Error processing image for text recognition: $e");
      } finally {
        if (mounted) {
          // Έλεγχος mounted και στο finally
          _isProcessingOcr = false; // Σημαδεύουμε ότι τελείωσε η επεξεργασία
        }
      }
    } else {
      if (mounted) {
        _isProcessingOcr = false;
      }
      debugPrint("InputImage for OCR was null.");
    }
  }

  void _updateRecognitionResults(RecognizedText recognizedText) {
    if (!mounted) return;

    String? detectedCorridorLabelInFrame;
    Rect? detectedRectInFrame;
    bool targetFoundInFrame = false;
    // String? firstWrongLabelInFrame; // Δεν χρησιμοποιείται ενεργά τώρα για το UI message

    int? targetCorridorNumber;
    final targetMatch = _corridorRegex.firstMatch(widget.targetCorridorLabel);
    if (targetMatch != null && targetMatch.group(1) != null) {
      targetCorridorNumber = int.tryParse(targetMatch.group(1)!);
    }
    if (targetCorridorNumber == null) {
      debugPrint(
        "Target corridor label could not be parsed to a number: ${widget.targetCorridorLabel}",
      );
      return; // Δεν μπορούμε να συνεχίσουμε χωρίς αριθμό-στόχο
    }

    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        final match = _corridorRegex.firstMatch(line.text);
        if (match != null && match.group(1) != null) {
          final currentDetectedLabel = match.group(0)!.trim();
          final currentDetectedNumber = int.tryParse(match.group(1)!);

          if (currentDetectedNumber != null) {
            if (currentDetectedNumber == targetCorridorNumber) {
              detectedCorridorLabelInFrame = currentDetectedLabel;
              detectedRectInFrame = line.boundingBox;
              targetFoundInFrame = true;
              break; // Βρέθηκε ο στόχος, δεν χρειάζεται να ψάξουμε άλλο σε αυτή τη γραμμή/block
            } else if (detectedCorridorLabelInFrame == null) {
              // Αν δεν έχουμε βρει ακόμα τον στόχο, κρατάμε τον πρώτο λάθος που βλέπουμε
              detectedCorridorLabelInFrame = currentDetectedLabel;
              detectedRectInFrame = line.boundingBox;
              // firstWrongLabelInFrame ??= currentDetectedLabel; // Κρατάμε τον πρώτο λάθος
            }
          }
        }
      }
      if (targetFoundInFrame) {
        break; // Βρέθηκε ο στόχος, έξοδος και από τα blocks
      }
    }

    bool updateStateNeeded = false;

    if (targetFoundInFrame && detectedRectInFrame != null) {
      _cancelNotFoundTimer();
      if (!_targetCorridorFound || _targetBoundingBox != detectedRectInFrame) {
        updateStateNeeded = true;
      }
      _targetCorridorFound = true;
      _targetBoundingBox = detectedRectInFrame;
      _lastDetectedIncorrectCorridorLabel =
          null; // Καθαρίζουμε αν προηγουμένως βλέπαμε λάθος

      if (!_instructionSpokenForThisDetection) {
        String shelfSide =
            widget.targetShelf % 2 != 0 ? "στα αριστερά" : "στα δεξιά";
        final String speechText =
            "Βρέθηκε ο $detectedCorridorLabelInFrame. Το ράφι ${widget.targetShelf} είναι $shelfSide σας.";
        _speak(speechText);
        Vibration.hasVibrator().then((has) {
          if (has == true) Vibration.vibrate(duration: 200);
        });
        _instructionSpokenForThisDetection = true;
        // updateStateNeeded = true; // Ήδη θα γίνει true από την αλλαγή του _targetCorridorFound
      }
    } else {
      // Δεν βρέθηκε ο στόχος σε αυτό το frame
      if (_targetCorridorFound) {
        // Αν προηγουμένως είχε βρεθεί
        _targetCorridorFound = false;
        // _targetBoundingBox = null; // Μπορούμε να το αφήσουμε για να δείχνει το τελευταίο λάθος ή να το καθαρίσουμε
        _instructionSpokenForThisDetection = false;
        _startNotFoundTimer(); // Ξαναξεκινάμε τον timer αν χάσαμε τον στόχο
        updateStateNeeded = true;
      }
      // Ενημέρωση για το αν βλέπουμε κάποιον άλλο (λάθος) διάδρομο
      if (detectedCorridorLabelInFrame != null && detectedRectInFrame != null) {
        if (_lastDetectedIncorrectCorridorLabel !=
                detectedCorridorLabelInFrame ||
            _targetBoundingBox != detectedRectInFrame) {
          _lastDetectedIncorrectCorridorLabel = detectedCorridorLabelInFrame;
          _targetBoundingBox =
              detectedRectInFrame; // Δείχνουμε το πλαίσιο του λάθος διαδρόμου
          updateStateNeeded = true;
        }
      } else {
        // Δεν βλέπουμε κανέναν διάδρομο
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
      debugPrint(
        'Warning: Unsupported image format for text recognition: ${image.format.group}',
      );
      return null;
    }
    if (image.planes.isEmpty) {
      debugPrint('Warning: Image has no planes!');
      return null;
    }

    final plane = image.planes.first;
    final bytes = plane.bytes;
    final Size imageSizeForMetadata = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final InputImageMetadata inputImageData = InputImageMetadata(
      size: imageSizeForMetadata,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: plane.bytesPerRow,
    );

    try {
      return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
    } catch (e) {
      debugPrint("Error creating InputImage for text recognition: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraService>(
      builder: (context, cameraService, child) {
        return Scaffold(
          appBar: myAppBar, // * ΑΛΛΑΓΗ: Χρήση της myAppBar
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
            ElevatedButton(
              onPressed: () async {
                bool granted = await cameraService.requestPermission();
                if (granted && mounted) {
                  _initializeCameraSystem(cameraService);
                }
              },
              child: const Text('Χορήγηση Άδειας'),
            ),
          ],
        ),
      );
    }

    if (!cameraService.isInitialized || !_iconsLoaded) {
      // Ελέγχουμε και το _iconsLoaded
      return const Center(child: CircularProgressIndicator());
    }

    if (cameraService.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Σφάλμα κάμερας: ${cameraService.errorMessage}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final previewSize =
        cameraService.previewSize; // Αυτό είναι το μέγεθος του CameraPreview
    if (previewSize == null || previewSize.isEmpty) {
      return const Center(
        child: Text("Σφάλμα μεγέθους προεπισκόπησης κάμερας."),
      );
    }

    // Το _imageSize είναι το μέγεθος της εικόνας που πήγε στο ML Kit (μπορεί να είναι rotated)
    // Το previewSize είναι το μέγεθος του widget της κάμερας στην οθόνη (πριν το scale)

    return LayoutBuilder(
      builder: (context, constraints) {
        // Υπολογισμός scale για το CameraPreview ώστε να γεμίσει το πλάτος
        double scaleX = constraints.maxWidth / previewSize.width;
        //double scaleY = constraints.maxHeight / previewSize.height;
        // Χρησιμοποιούμε το min scale για να χωράει ολόκληρη η προεπισκόπηση χωρίς crop (letterbox/pillarbox)
        // ή το max scale για να γεμίσει (cover) με πιθανό crop. Για OCR, το cover είναι συνήθως ΟΚ.
        // Εδώ, θα κάνουμε scale για να ταιριάξει το πλάτος.
        double scale = scaleX;

        var cameraWidgetHeight = previewSize.height * scale;
        var cameraWidgetWidth =
            previewSize.width * scale; // constraints.maxWidth

        // Αν το ύψος ξεπερνάει τα constraints, κάνουμε scale με βάση το ύψος
        if (cameraWidgetHeight > constraints.maxHeight) {
          scale = constraints.maxHeight / previewSize.height;
          cameraWidgetHeight = constraints.maxHeight;
          cameraWidgetWidth = previewSize.width * scale;
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              // Περιτύλιγμα για το CameraPreview με το σωστό μέγεθος
              width: cameraWidgetWidth,
              height: cameraWidgetHeight,
              child: CameraPreview(cameraService.controller!),
            ),
            if (_imageSize != null &&
                _targetBoundingBox != null &&
                _iconsLoaded) // Ελέγχουμε και το _iconsLoaded
              SizedBox(
                // Το CustomPaint πρέπει να έχει το ίδιο μέγεθος με το CameraPreview
                width: cameraWidgetWidth,
                height: cameraWidgetHeight,
                child: CustomPaint(
                  painter: TextOverlayPainter(
                    targetBoundingBox: _targetBoundingBox,
                    imageSize:
                        _imageSize!, // Το μέγεθος της εικόνας που αναλύθηκε από το MLKit
                    previewSize: Size(
                      cameraWidgetWidth,
                      cameraWidgetHeight,
                    ), // Το μέγεθος του widget στην οθόνη
                    scale: scale, // Το scale που εφαρμόστηκε στο CameraPreview
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
              bottom: 20, // Λίγο πιο πάνω
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10.0,
                  horizontal: 15.0,
                ), // Λίγο μεγαλύτερο padding
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(
                    (255 * 0.75).round(),
                  ), // Λίγο πιο έντονη διαφάνεια
                  borderRadius: BorderRadius.circular(
                    10.0,
                  ), // Πιο στρογγυλεμένες γωνίες
                  boxShadow: [
                    // Σκιά για καλύτερη ανάγνωση
                    BoxShadow(
                      color: Colors.black.withAlpha((255 * 0.3).round()),
                      spreadRadius: 1,
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  _targetCorridorFound
                      ? 'ΒΡΕΘΗΚΕ: ${widget.targetCorridorLabel}!'
                      : _notFoundMessageSpoken
                      ? 'Ο διάδρομος δεν εντοπίστηκε. Ζητήστε βοήθεια.'
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
                    fontSize: 17, // Λίγο μεγαλύτερο font
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
}
