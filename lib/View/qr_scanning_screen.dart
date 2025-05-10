import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import 'package:inlib_nav/Services/camera_service.dart';

// Οι καταστάσεις λειτουργίας μου: ψάχνω διάδρομο ή ράφι ή έχω σφάλμα.
enum QrScanningMode { lookingForCorridor, lookingForShelf, error }

/// Η οθόνη μου για τη σάρωση QR.
class QrScanningScreen extends StatefulWidget {
  final String
  targetCorridorLabel; // Ο διάδρομος-στόχος μου (π.χ., "ΔΙΑΔΡΟΜΟΣ 1")
  final String targetBookLoc; // Το LoC του βιβλίου-στόχου
  final int targetShelf; // Το ράφι-στόχος

  const QrScanningScreen({
    super.key,
    required this.targetCorridorLabel,
    required this.targetBookLoc,
    required this.targetShelf,
  });

  @override
  State<QrScanningScreen> createState() => _QrScanningScreenState();
}

class _QrScanningScreenState extends State<QrScanningScreen> {
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  bool _isProcessingQr = false;

  QrScanningMode _currentMode = QrScanningMode.lookingForCorridor;
  String _uiMessage = "";
  Color _feedbackColor = Colors.white;

  // ΑΦΑΙΡΕΘΗΚΑΝ:
  // Rect? _barcodeBoundingBox;
  // Size? _imageSize;

  // Κρατάω το τελευταίο QR που είδα (μόνο το αντικείμενο Barcode)
  Barcode? _lastDetectedBarcode;

  late FlutterTts flutterTts;
  bool _isTtsSpeaking = false;
  bool _isTtsCoolingDown = false;
  Timer? _ttsCooldownTimer;
  final Duration _ttsCooldownDuration = const Duration(seconds: 5);

  Timer? _notFoundTimer;
  bool _notFoundMessageSpoken = false;
  final int _notFoundTimeoutSeconds = 20;

  bool _wasCorrectCorridorFound = false;
  bool _wasCorrectShelfFound = false;
  bool _corridorVibrationPlayedForThisDetection = false;

  @override
  void initState() {
    super.initState();
    flutterTts = FlutterTts();
    _initializeTts();
    final cameraService = context.read<CameraService>();
    _initializeCameraSystem(cameraService);
    _setUiMessageForMode();
    _startNotFoundTimer();
  }

  Future<void> _initializeCameraSystem(CameraService cameraService) async {
    bool granted = await cameraService.requestPermission();
    if (granted && mounted) {
      await cameraService.initializeController(
        resolutionPreset: ResolutionPreset.medium,
        onImageAvailable: _processCameraImage,
      );
      if (mounted &&
          cameraService.isInitialized &&
          !cameraService.isStreamingImages) {
        await cameraService.startImageStream(_processCameraImage);
      }
    } else if (!granted && mounted) {
      setState(() {
        _currentMode = QrScanningMode.error;
        _setUiMessageForMode(error: "Η άδεια κάμερας είναι απαραίτητη.");
      });
    }
  }

  Future<void> _initializeTts() async {
    await flutterTts.setLanguage("el-GR");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);

    flutterTts.setStartHandler(() {
      if (mounted) {
        setState(() {
          _isTtsSpeaking = true;
          _isTtsCoolingDown = true;
        });
      }
    });

    flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isTtsSpeaking = false;
          _ttsCooldownTimer?.cancel();
          _ttsCooldownTimer = Timer(_ttsCooldownDuration, () {
            if (mounted) {
              setState(() {
                _isTtsCoolingDown = false;
              });
            }
            debugPrint("TTS Cooldown Finished");
          });
        });
        debugPrint("TTS Completed, Starting Cooldown Timer");
      }
    });

    flutterTts.setErrorHandler((msg) {
      debugPrint("TTS Error: $msg");
      if (mounted) {
        setState(() {
          _isTtsSpeaking = false;
          _isTtsCoolingDown = false;
          _ttsCooldownTimer?.cancel();
        });
      }
    });
  }

  @override
  void dispose() {
    _notFoundTimer?.cancel();
    _ttsCooldownTimer?.cancel();
    flutterTts.stop();
    _barcodeScanner.close();
    super.dispose();
  }

  void _startNotFoundTimer() {
    _notFoundTimer?.cancel();
    _notFoundMessageSpoken = false;
    _notFoundTimer = Timer(Duration(seconds: _notFoundTimeoutSeconds), () {
      if (mounted &&
          !_notFoundMessageSpoken &&
          _lastDetectedBarcode == null &&
          !_wasCorrectShelfFound) {
        String msg =
            _currentMode == QrScanningMode.lookingForCorridor
                ? "Δεν βρήκα QR διαδρόμου. Κοίτα τριγύρω."
                : "Δεν βρήκα QR ραφιού. Είσαι στη σωστή πλευρά;";
        _speak(msg);
        if (mounted) {
          setState(() {
            _notFoundMessageSpoken = true;
            _uiMessage = msg;
            _feedbackColor = Colors.grey;
          });
        }
      }
    });
  }

  void _resetNotFoundTimerIfNeeded() {
    if (_notFoundMessageSpoken) {
      _notFoundMessageSpoken = false;
    }
    _notFoundTimer?.cancel();
    if (!_wasCorrectShelfFound) {
      _startNotFoundTimer();
    }
  }

  void _cancelAllTimers() {
    _ttsCooldownTimer?.cancel();
    _notFoundTimer?.cancel();
    _notFoundMessageSpoken = false;
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final cameraService = Provider.of<CameraService>(context, listen: false);
    if (_isProcessingQr || !mounted || !cameraService.isInitialized) return;
    _isProcessingQr = true;

    final sensorOrientation = cameraService.sensorOrientation;
    if (sensorOrientation == null) {
      _isProcessingQr = false;
      return;
    }
    final inputImage = _inputImageFromCameraImage(image, sensorOrientation);

    if (inputImage != null) {
      // ΑΦΑΙΡΕΘΗΚΕ η ανάθεση στο _imageSize
      // if (mounted) { _imageSize = Size(image.width.toDouble(), image.height.toDouble()); }
      try {
        final List<Barcode> barcodes = await _barcodeScanner.processImage(
          inputImage,
        );
        if (mounted) {
          _processBarcodes(barcodes);
        }
      } catch (e) {
        debugPrint("Barcode Scanner Error: $e");
      } finally {
        if (mounted) {
          _isProcessingQr = false;
        }
      }
    } else {
      if (mounted) {
        _isProcessingQr = false;
      }
    }
  }

  int? _parseCorridorNumber(String? label) {
    if (label == null) return null;
    final match = RegExp(
      r'ΔΙΑΔΡΟΜΟΣ\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(label);
    if (match != null && match.group(1) != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  void _processBarcodes(List<Barcode> barcodes) {
    if (barcodes.isEmpty) {
      // Αν δεν βλέπω QR, επαναφέρω τα πάντα
      if (_lastDetectedBarcode != null ||
          _wasCorrectCorridorFound ||
          _wasCorrectShelfFound ||
          _corridorVibrationPlayedForThisDetection) {
        if (mounted) {
          setState(() {
            _lastDetectedBarcode = null;
            // ΑΦΑΙΡΕΘΗΚΕ: _barcodeBoundingBox = null;
            _wasCorrectCorridorFound = false;
            _wasCorrectShelfFound = false;
            _corridorVibrationPlayedForThisDetection = false;
            _setUiMessageForMode();
            _resetNotFoundTimerIfNeeded();
          });
        }
      }
      return;
    }

    final barcode = barcodes.first;
    final qrDataString = barcode.rawValue;
    //! ΑΦΑΙΡΕΣΣΑ την ανάθεση στο _barcodeBoundingBox από εδώ, γίνεται παρακάτω στο setState αν χρειαστεί
    // final qrBoundingBox = barcode.boundingBox;

    _resetNotFoundTimerIfNeeded();

    if (qrDataString == null) return;

    Map<String, dynamic>? qrData;
    try {
      qrData = jsonDecode(qrDataString);
    } catch (e) {
      debugPrint("Error decoding QR data: '$qrDataString'. Error: $e");
      return;
    }

    if (qrData == null || qrData['type'] == null) {
      debugPrint(
        "QR Data is not in expected format (missing 'type'): $qrDataString",
      );
      return;
    }

    bool stateChanged = false;
    String currentUiMessage = _uiMessage;
    Color currentFeedbackColor = _feedbackColor;
    bool currentCorrectCorridor = false;
    bool currentCorrectShelf = false;
    String? ttsMessageToSpeak;

    final qrType = qrData['type'];

    // --- Υπολογισμός μηνυμάτων και κατάστασης (ίδιος με πριν) ---
    if (qrType == 'corridor') {
      String? scannedLabel = qrData['label'];
      if (scannedLabel != null && scannedLabel == widget.targetCorridorLabel) {
        // Correct Corridor
        currentCorrectCorridor = true;
        currentFeedbackColor = Colors.cyanAccent;
        String shelfSide =
            widget.targetShelf % 2 != 0 ? "στα αριστερά" : "στα δεξιά";
        currentUiMessage =
            "Βρέθηκε ο $scannedLabel.\nΤο Ράφι ${widget.targetShelf} είναι $shelfSide σας.\nΣαρώστε το QR του Ραφιού.";
        if (!_corridorVibrationPlayedForThisDetection) {
          Vibration.vibrate(duration: 150);
          _corridorVibrationPlayedForThisDetection = true;
        }
        if (_currentMode == QrScanningMode.lookingForCorridor) {
          ttsMessageToSpeak =
              "Βρέθηκε ο $scannedLabel. Το ράφι ${widget.targetShelf} είναι $shelfSide σας. Σαρώστε το QR code του ραφιού.";
          _currentMode = QrScanningMode.lookingForShelf;
        } else {
          ttsMessageToSpeak = "Σωστός διάδρομος: $scannedLabel.";
        }
      } else if (scannedLabel != null) {
        // Wrong Corridor
        final int? targetNumber = _parseCorridorNumber(
          widget.targetCorridorLabel,
        );
        final int? scannedNumber = _parseCorridorNumber(scannedLabel);
        String baseMsg = "Λάθος Διάδρομος";
        String directionMsg = "";
        if (targetNumber != null && scannedNumber != null) {
          final diff = targetNumber - scannedNumber;
          if (diff != 0) {
            final direction = diff > 0 ? "μετά" : "πριν";
            final plural = diff.abs() == 1 ? "" : "ους";
            final corridors = diff.abs();
            directionMsg =
                "\nΟ σωστός είναι $corridors διάδρομ$plural $direction από εδώ.";
          }
        }
        currentUiMessage = "$baseMsg ($scannedLabel).$directionMsg";
        ttsMessageToSpeak = "$baseMsg. $directionMsg";
        currentFeedbackColor = Colors.orangeAccent;
      }
    } else if (qrType == 'shelf') {
      if (_currentMode == QrScanningMode.lookingForCorridor) {
        currentUiMessage =
            "Είδα Ράφι. Σάρωσε πρώτα το QR του διαδρόμου ${widget.targetCorridorLabel}.";
        currentFeedbackColor = Colors.grey;
      } else {
        // Process Shelf QR
        String? startLoc = qrData['loc_start'];
        String? endLoc = qrData['loc_end'];
        if (startLoc != null && endLoc != null) {
          bool isInRange = isLocInRange(widget.targetBookLoc, startLoc, endLoc);
          if (isInRange) {
            // Correct Shelf
            currentCorrectShelf = true;
            currentFeedbackColor = Colors.lightGreenAccent;
            currentUiMessage =
                "ΤΟ ΒΙΒΛΙΟ ΕΙΝΑΙ ΕΔΩ!\nΡάφι ${widget.targetShelf} (${widget.targetCorridorLabel})\nΚωδικός: ${widget.targetBookLoc}";
            ttsMessageToSpeak = "Το βιβλίο βρίσκεται σε αυτό το ράφι.";
            Vibration.vibrate(duration: 300, amplitude: 192);
            _cancelAllTimers();
          } else {
            // Wrong Shelf Range
            currentUiMessage =
                "Λάθος Ράφι.\nΑυτό περιέχει: $startLoc - $endLoc.\nΨάχνετε: ${widget.targetBookLoc}.\nΣυνεχίστε.";
            ttsMessageToSpeak = "Λάθος ράφι. Συνεχίστε τη σάρωση.";
            currentFeedbackColor = Colors.yellowAccent;
          }
        }
      }
    } else {
      /* Unknown QR Type */
      currentUiMessage = "Άγνωστος τύπος QR Code.";
      currentFeedbackColor = Colors.redAccent;
      ttsMessageToSpeak = "Άγνωστος κωδικός QR.";
    }
    // --- Τέλος υπολογισμού ---

    // --- Update State ---
    if (_lastDetectedBarcode != barcode ||
        _uiMessage != currentUiMessage ||
        _feedbackColor != currentFeedbackColor ||
        _wasCorrectCorridorFound != currentCorrectCorridor ||
        _wasCorrectShelfFound != currentCorrectShelf) {
      stateChanged = true;
      _uiMessage = currentUiMessage;
      _feedbackColor = currentFeedbackColor;
      _wasCorrectCorridorFound = currentCorrectCorridor;
      _wasCorrectShelfFound = currentCorrectShelf;
      _lastDetectedBarcode = barcode;
      // ΑΦΑΙΡΕΘΗΚΕ η ανάθεση στο _barcodeBoundingBox
      // _barcodeBoundingBox = qrBoundingBox;
    }

    if (!currentCorrectCorridor) {
      if (_corridorVibrationPlayedForThisDetection) {
        _corridorVibrationPlayedForThisDetection = false;
        stateChanged = true;
      }
    }

    if (ttsMessageToSpeak != null && !_isTtsSpeaking && !_isTtsCoolingDown) {
      _speak(ttsMessageToSpeak);
    } else if (ttsMessageToSpeak != null) {
      debugPrint(
        "TTS Skipped: Speaking=$_isTtsSpeaking, CoolingDown=$_isTtsCoolingDown",
      );
    }

    if (stateChanged && mounted) {
      setState(() {});
    }
  }

  void _setUiMessageForMode({String? error}) {
    if (error != null) {
      _uiMessage = "Σφάλμα: $error";
      _feedbackColor = Colors.redAccent;
      _cancelAllTimers();
      return;
    }
    if (_lastDetectedBarcode != null) return;

    switch (_currentMode) {
      case QrScanningMode.lookingForCorridor:
        _uiMessage =
            "Σαρώστε το QR στην είσοδο του διαδρόμου ${widget.targetCorridorLabel}";
        _feedbackColor = Colors.white;
        break;
      case QrScanningMode.lookingForShelf:
        String shelfSide = widget.targetShelf % 2 != 0 ? "αριστερό" : "δεξιό";
        _uiMessage =
            "Προχωρήστε στο Ράφι ${widget.targetShelf} ($shelfSide σας) και σαρώστε το QR του Ραφιού";
        _feedbackColor = Colors.white;
        break;
      case QrScanningMode.error:
        _feedbackColor = Colors.redAccent;
        break;
    }
  }

  Future<void> _speak(String text) async {
    if (_isTtsSpeaking || _isTtsCoolingDown) {
      debugPrint("Speak request ignored: TTS is busy or cooling down.");
      return;
    }
    try {
      await flutterTts.stop();
      await flutterTts.speak(text);
      debugPrint("TTS Speak initiated for: $text");
    } catch (e) {
      debugPrint("TTS Error speaking: $e");
      if (mounted) {
        setState(() {
          _isTtsSpeaking = false;
          _isTtsCoolingDown = false;
          _ttsCooldownTimer?.cancel();
        });
      }
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
      return null;
    }
    if (image.planes.isEmpty) return null;
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

  // --- !!! Placeholder: Σύγκριση Εύρους LoC !!! ---
  bool isLocInRange(String targetLoc, String startLoc, String endLoc) {
    // ΣΗΜΑΝΤΙΚΟ: Αντικατάστησε με σωστή λογική LoC.
    debugPrint("Checking if '$targetLoc' is between '$startLoc' and '$endLoc'");
    try {
      final String targetUpper = targetLoc.toUpperCase();
      final String startUpper = startLoc.toUpperCase();
      final String endUpper = endLoc.toUpperCase();
      bool basicCheck =
          targetUpper.compareTo(startUpper) >= 0 &&
          targetUpper.compareTo(endUpper) <= 0;
      debugPrint("Basic String Comparison Result (Placeholder): $basicCheck");
      return basicCheck;
    } catch (e) {
      debugPrint("Error during basic LoC comparison (Placeholder): $e");
      return false;
    }
    // --- Τέλος Placeholder ---
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraService>(
      builder: (context, cameraService, child) {
        return Scaffold(
          appBar: AppBar(title: Text(_getAppBarTitle())),
          body: _buildScannerBody(cameraService),
        );
      },
    );
  }

  String _getAppBarTitle() {
    switch (_currentMode) {
      case QrScanningMode.lookingForCorridor:
        return "Σάρωση: ${widget.targetCorridorLabel}";
      case QrScanningMode.lookingForShelf:
        return "Σάρωση Ραφιού ${widget.targetShelf} (${widget.targetCorridorLabel})";
      case QrScanningMode.error:
        return "Σφάλμα";
    }
  }

  Widget _buildScannerBody(CameraService cameraService) {
    // Έλεγχοι άδειας, αρχικοποίησης κλπ.
    if (!cameraService.isPermissionGranted &&
        _currentMode != QrScanningMode.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Απαιτείται άδεια κάμερας.'),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => _initializeCameraSystem(cameraService),
              child: const Text('Χορήγηση Άδειας'),
            ),
          ],
        ),
      );
    }
    if (!cameraService.isInitialized && _currentMode != QrScanningMode.error) {
      return const Center(child: CircularProgressIndicator());
    }
    if (cameraService.errorMessage != null &&
        _currentMode != QrScanningMode.error) {
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
        // Υπολογισμοί μεγέθους προεπισκόπησης
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
            // Προεπισκόπηση κάμερας
            SizedBox(
              width: cameraWidgetWidth,
              height: cameraWidgetHeight,
              child: CameraPreview(cameraService.controller!),
            ),

            // ΑΦΑΙΡΕΘΗΚΕ το κομμάτι για τον BarcodeOverlayPainter

            // Το μήνυμα στο κάτω μέρος
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10.0,
                  horizontal: 15.0,
                ),
                decoration: BoxDecoration(
                  color:
                      _feedbackColor == Colors.white
                          ? Colors.black.withAlpha((255 * 0.7).round())
                          : _feedbackColor.withAlpha((255 * 0.9).round()),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Text(
                  _uiMessage,
                  style: TextStyle(
                    color:
                        (_feedbackColor == Colors.white ||
                                _feedbackColor == Colors.cyanAccent ||
                                _feedbackColor == Colors.yellowAccent ||
                                _feedbackColor == Colors.orangeAccent ||
                                _feedbackColor == Colors.grey)
                            ? Colors.white
                            : Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            // Εικονίδιο κατάστασης TTS
            if (_isTtsSpeaking || _isTtsCoolingDown)
              Positioned(
                top: 10,
                right: 10,
                child: Icon(
                  _isTtsSpeaking ? Icons.volume_up : Icons.timer_outlined,
                  color: Colors.white.withAlpha(200),
                  size: 30,
                ),
              ),
          ],
        );
      },
    );
  }
} // Τέλος της _QrScanningScreenState
