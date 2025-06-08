import 'dart:async';
import 'dart:convert'; // Για το jsonDecode
import 'dart:io'; //

import 'package:flutter_tts/flutter_tts.dart'; // Για την εκφώνηση
import 'package:camera/camera.dart'; // Για την κάμερα
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart'; // Για το σκανάρισμα barcode
import 'package:provider/provider.dart'; // Για το CameraService
import 'package:vibration/vibration.dart'; // Για τη δόνηση

import 'package:inlib_nav/Services/camera_service.dart';
import 'package:inlib_nav/Services/dummy_books_service.dart';
import 'package:inlib_nav/constants.dart';
import 'package:inlib_nav/View/book_found_screen.dart';

// Οι καταστάσεις λειτουργίας μου: ψάχνω διάδρομο ή ράφι ή έχω σφάλμα.
enum QrScanningMode { lookingForCorridor, lookingForShelf, error }

/// Η οθόνη μου για τη σάρωση QR.
class QrScanningScreen extends StatefulWidget {
  final String targetCorridorLabel;
  final String targetBookLoc; // Το LoC του βιβλίου-στόχου
  final int targetShelf; // Το ράφι-στόχος
  // Προσθέτω τα πεδία για τα στοιχεία του βιβλίου που θα εμφανίζω
  final String bookTitle;
  final String bookAuthor;
  final String bookIsbn;

  const QrScanningScreen({
    super.key,
    required this.targetCorridorLabel,
    required this.targetBookLoc,
    required this.targetShelf,
    required this.bookTitle,
    required this.bookAuthor,
    required this.bookIsbn,
  });

  @override
  State<QrScanningScreen> createState() => _QrScanningScreenState();
}

class _QrScanningScreenState extends State<QrScanningScreen> {
  CameraService? _cameraServiceInstance;
  // ML Kit Barcode Scanner
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  bool _isProcessingQr = false;

  // Κατάσταση πλοήγησης και UI
  QrScanningMode _currentMode = QrScanningMode.lookingForCorridor;
  String _uiMessage = "";
  Color _feedbackColor = Colors.white;
  Barcode? _lastDetectedBarcode;

  // Text-to-Speech (TTS)
  late FlutterTts flutterTts;
  bool _isTtsSpeaking = false;
  bool _isTtsCoolingDown = false;
  Timer? _ttsCooldownTimer;
  final Duration _ttsCooldownDuration = const Duration(seconds: 5);

  // Timer για μη εύρεση QR
  Timer? _notFoundTimer;
  bool _notFoundMessageSpoken = false;
  final int _notFoundTimeoutSeconds = 20;

  bool _wasCorrectCorridorFound = false;
  bool _wasCorrectShelfFound = false; // Θα γίνει true όταν βρεθεί το σωστό ράφι
  bool _corridorVibrationPlayedForThisDetection = false;
  bool _finalTargetFoundAndHandled = false;

  DateTime? _startTime; // Χρόνος έναρξης αναζήτησης από αυτή την οθόνη
  DateTime? _shelfFoundTime; // Χρόνος που βρέθηκε το σωστό ράφι
  Duration? _timeToFindShelf; // Διάρκεια αναζήτησης

  DateTime _lastProcessedFrameTime = DateTime.now().subtract(
    const Duration(seconds: 1),
  );
  final Duration _frameProcessingInterval = const Duration(milliseconds: 200);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cameraServiceInstance ??= Provider.of<CameraService>(
      context,
      listen: false,
    );
  }

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now(); // * ΟΡΙΣΜΟΣ ΤΟΥ START TIME
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
      if (mounted) setState(() => _isTtsSpeaking = true);
    });

    flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() => _isTtsSpeaking = false);
        _ttsCooldownTimer?.cancel();
        _isTtsCoolingDown = true;
        _ttsCooldownTimer = Timer(_ttsCooldownDuration, () {
          if (mounted) setState(() => _isTtsCoolingDown = false);
          debugPrint("TTS Cooldown Finished");
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
    debugPrint("Disposing QrScanningScreen");
    _notFoundTimer?.cancel();
    _ttsCooldownTimer?.cancel();
    flutterTts.stop();
    _barcodeScanner.close();
    try {
      if (_cameraServiceInstance != null &&
          _cameraServiceInstance!.isInitialized &&
          _cameraServiceInstance!.isStreamingImages) {
        _cameraServiceInstance!.stopImageStream().catchError((e) {
          debugPrint(
            "Error stopping image stream in dispose for QrScanningScreen: $e",
          );
        });
        debugPrint("Image stream stop requested for QrScanningScreen");
      }
    } catch (e) {
      debugPrint(
        "Error accessing CameraService in dispose for QrScanningScreen: $e",
      );
    }
    super.dispose();
    debugPrint("QrScanningScreen disposed successfully");
  }

  void _startNotFoundTimer() {
    _notFoundTimer?.cancel();
    _notFoundMessageSpoken = false;
    _notFoundTimer = Timer(Duration(seconds: _notFoundTimeoutSeconds), () {
      if (mounted &&
          !_notFoundMessageSpoken &&
          _lastDetectedBarcode == null &&
          !_wasCorrectShelfFound &&
          !_finalTargetFoundAndHandled) {
        String msg =
            _currentMode == QrScanningMode.lookingForCorridor
                ? "Δεν εντοπίστηκε QR code διαδρόμου. Ελέγξτε την περιοχή."
                : "Δεν εντοπίστηκε QR code ραφιού. Είστε στη σωστή πλευρά;";
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
    if (_notFoundMessageSpoken) _notFoundMessageSpoken = false;
    _notFoundTimer?.cancel();
    if (!_finalTargetFoundAndHandled) {
      _startNotFoundTimer();
    }
  }

  void _cancelAllTimers() {
    _ttsCooldownTimer?.cancel();
    _notFoundTimer?.cancel();
    if (mounted) _notFoundMessageSpoken = false;
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!mounted || _isProcessingQr || _finalTargetFoundAndHandled) return;
    final now = DateTime.now();
    if (now.difference(_lastProcessedFrameTime) < _frameProcessingInterval) {
      return;
    }
    _lastProcessedFrameTime = now;
    _isProcessingQr = true;
    final cameraService = _cameraServiceInstance;
    if (cameraService == null || !cameraService.isInitialized) {
      _isProcessingQr = false;
      return;
    }
    final sensorOrientation = cameraService.sensorOrientation;
    if (sensorOrientation == null) {
      _isProcessingQr = false;
      debugPrint("Sensor orientation is null, cannot process QR image.");
      return;
    }
    final inputImage = _inputImageFromCameraImage(image, sensorOrientation);
    if (inputImage != null) {
      try {
        final List<Barcode> barcodes = await _barcodeScanner.processImage(
          inputImage,
        );
        if (mounted) {
          _processBarcodes(barcodes);
        }
      } catch (e) {
        debugPrint("Barcode Scanner Error during processing: $e");
      } finally {
        if (mounted) {
          _isProcessingQr = false;
        }
      }
    } else {
      if (mounted) {
        _isProcessingQr = false;
      }
      debugPrint("InputImage for QR scanning was null.");
    }
  }

  int? _parseCorridorNumber(String? label) {
    if (label == null) return null;
    final match = RegExp(
      r'ΔΙΑΔΡΟΜΟΣ\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(label);
    return (match != null && match.group(1) != null)
        ? int.tryParse(match.group(1)!)
        : null;
  }

  void _processBarcodes(List<Barcode> barcodes) {
    if (_finalTargetFoundAndHandled) return;

    if (barcodes.isEmpty) {
      if (_lastDetectedBarcode != null ||
          _wasCorrectCorridorFound ||
          // _wasCorrectShelfFound δεν το μηδενίζουμε εδώ αν έχει γίνει true
          _corridorVibrationPlayedForThisDetection) {
        if (mounted) {
          setState(() {
            _lastDetectedBarcode = null;
            // Δεν μηδενίζουμε το _wasCorrectCorridorFound αν το _wasCorrectShelfFound είναι true
            if (!_wasCorrectShelfFound) {
              _wasCorrectCorridorFound = false;
            }
            _corridorVibrationPlayedForThisDetection = false;
            if (!_wasCorrectShelfFound) {
              // Ενημερώνουμε το μήνυμα μόνο αν δεν έχει βρεθεί το ράφι
              _setUiMessageForMode();
            }
            _resetNotFoundTimerIfNeeded();
          });
        }
      }
      return;
    }

    final barcode = barcodes.first;
    final qrDataString = barcode.rawValue;
    _resetNotFoundTimerIfNeeded();
    if (qrDataString == null) return;

    Map<String, dynamic>? qrData;
    bool isAppQr = false;
    try {
      qrData = jsonDecode(qrDataString);
      if (qrData != null && qrData.containsKey('type')) isAppQr = true;
    } catch (e) {
      isAppQr = false;
      qrData = null;
    }

    bool stateChanged = false;
    String currentUiMessage = _uiMessage;
    Color currentFeedbackColor = _feedbackColor;
    bool tempCorrectCorridorFound = _wasCorrectCorridorFound;
    String? ttsMessageToSpeak;

    if (!isAppQr) {
      currentUiMessage = "Αυτό το QR code δεν αφορά την εφαρμογή.";
      currentFeedbackColor = Colors.orange;
      ttsMessageToSpeak = "Αυτό το QR code δεν αφορά την εφαρμογή.";
    } else if (qrData != null) {
      final qrType = qrData['type'];

      if (qrType == 'corridor') {
        String? scannedLabel = qrData['label'];
        if (scannedLabel != null &&
            scannedLabel == widget.targetCorridorLabel) {
          tempCorrectCorridorFound = true;
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
            ttsMessageToSpeak =
                "Σωστός διάδρομος: $scannedLabel. Σαρώστε το QR code του ραφιού";
          }
        } else if (scannedLabel != null) {
          tempCorrectCorridorFound = false;
          _corridorVibrationPlayedForThisDetection = false;
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
          ttsMessageToSpeak = "$baseMsg.$directionMsg";
          currentFeedbackColor = Colors.orangeAccent;
        }
      } else if (qrType == 'shelf') {
        String? scannedShelfLocStart = qrData['loc_start'];
        String? scannedShelfLocEnd = qrData['loc_end'];
        int? scannedShelfNum = qrData['shelf_number'];

        if (scannedShelfNum != null) {
          String actualCorridorOfScannedShelf = calculateCorridor(
            scannedShelfNum,
          );

          if (_currentMode == QrScanningMode.lookingForCorridor) {
            if (actualCorridorOfScannedShelf == widget.targetCorridorLabel) {
              _currentMode = QrScanningMode.lookingForShelf;
              tempCorrectCorridorFound = true;
              if (!_corridorVibrationPlayedForThisDetection) {
                Vibration.vibrate(duration: 150);
                _corridorVibrationPlayedForThisDetection = true;
              }

              if (scannedShelfNum == widget.targetShelf) {
                if (scannedShelfLocStart != null &&
                    scannedShelfLocEnd != null) {
                  bool isInRange = isLocInRange(
                    widget.targetBookLoc,
                    scannedShelfLocStart,
                    scannedShelfLocEnd,
                  );
                  if (isInRange) {
                    // * ΕΝΤΟΠΙΣΜΟΣ ΣΩΣΤΟΥ ΡΑΦΙΟΥ
                    if (!_wasCorrectShelfFound) {
                      // Έλεγχος για να εκτελεστεί μία φορά
                      _wasCorrectShelfFound =
                          true; // Ορίζουμε ότι το ράφι βρέθηκε
                      _shelfFoundTime ??= DateTime.now();
                      if (_startTime != null && _shelfFoundTime != null) {
                        _timeToFindShelf = _shelfFoundTime!.difference(
                          _startTime!,
                        );
                      }
                      currentFeedbackColor = Colors.lightGreenAccent;
                      currentUiMessage =
                          "ΤΟ ΒΙΒΛΙΟ ΕΙΝΑΙ ΕΔΩ!\nΡάφι ${widget.targetShelf} (${widget.targetCorridorLabel})\nΚωδικός: ${widget.targetBookLoc}\nΠατήστε 'Ολοκλήρωση'.";
                      ttsMessageToSpeak =
                          "Το βιβλίο βρίσκεται σε αυτό το ράφι. Όταν το εντοπίσετε πατήστε το κουμπί ολοκλήρωση .";
                      Vibration.vibrate(duration: 300, amplitude: 192);
                      _cancelAllTimers();
                      _finalTargetFoundAndHandled = true;
                      stateChanged = true; // Σημαντικό για να φανεί το κουμπί
                    }
                  } else {
                    currentFeedbackColor = Colors.yellowAccent;
                    currentUiMessage =
                        "Ράφι ${widget.targetShelf} (${widget.targetCorridorLabel}). Το βιβλίο δεν είναι σε αυτό το εύρος LoC ($scannedShelfLocStart - $scannedShelfLocEnd).";
                    ttsMessageToSpeak =
                        "Σωστό ράφι και διάδρομος, αλλά το βιβλίο δεν ανήκει εδώ.";
                  }
                } else {
                  currentFeedbackColor = Colors.redAccent;
                  currentUiMessage =
                      "Σφάλμα QR ραφιού (${widget.targetShelf}): Λείπει το εύρος LoC.";
                  ttsMessageToSpeak =
                      "Σφάλμα στα δεδομένα του QR code του ραφιού.";
                }
              } else {
                currentFeedbackColor = Colors.yellowAccent;
                String shelfSideTarget =
                    widget.targetShelf % 2 != 0 ? "στα αριστερά" : "στα δεξιά";
                currentUiMessage =
                    "Σωστός Διάδρομος (${widget.targetCorridorLabel}).\nΑυτό είναι το Ράφι $scannedShelfNum.\nΨάχνετε το Ράφι ${widget.targetShelf} ($shelfSideTarget σας).";
                ttsMessageToSpeak =
                    "Σωστός Διάδρομος. Αυτό είναι το Ράφι $scannedShelfNum. Ψάχνετε το Ράφι ${widget.targetShelf}.";
              }
            } else {
              tempCorrectCorridorFound = false;
              currentFeedbackColor = Colors.orangeAccent;
              _corridorVibrationPlayedForThisDetection = false;
              currentUiMessage =
                  "Λάθος Διάδρομος.\nΑυτό το ράφι ($scannedShelfNum) είναι στον $actualCorridorOfScannedShelf.\nΠηγαίνετε στον ${widget.targetCorridorLabel}.";
              ttsMessageToSpeak =
                  "Λάθος Διάδρομος. Αυτό το ράφι βρίσκεται στον $actualCorridorOfScannedShelf. Πρέπει να μεταβείτε στον ${widget.targetCorridorLabel}.";
            }
          } else {
            if (scannedShelfNum == widget.targetShelf) {
              if (scannedShelfLocStart != null && scannedShelfLocEnd != null) {
                bool isInRange = isLocInRange(
                  widget.targetBookLoc,
                  scannedShelfLocStart,
                  scannedShelfLocEnd,
                );
                if (isInRange) {
                  // * ΕΝΤΟΠΙΣΜΟΣ ΣΩΣΤΟΥ ΡΑΦΙΟΥ
                  if (!_wasCorrectShelfFound) {
                    _wasCorrectShelfFound = true;
                    _shelfFoundTime ??= DateTime.now();
                    if (_startTime != null && _shelfFoundTime != null) {
                      _timeToFindShelf = _shelfFoundTime!.difference(
                        _startTime!,
                      );
                    }
                    currentFeedbackColor = Colors.lightGreenAccent;
                    currentUiMessage =
                        "ΤΟ ΒΙΒΛΙΟ ΕΙΝΑΙ ΕΔΩ!\nΡάφι ${widget.targetShelf} (${widget.targetCorridorLabel})\nΚωδικός: ${widget.targetBookLoc}\nΠατήστε 'Ολοκλήρωση'.";
                    ttsMessageToSpeak =
                        "Το βιβλίο βρίσκεται σε αυτό το ράφι. Πατήστε ολοκλήρωση.";
                    Vibration.vibrate(duration: 300, amplitude: 192);
                    _cancelAllTimers();
                    _finalTargetFoundAndHandled = true;
                    stateChanged = true;
                  }
                } else {
                  currentFeedbackColor = Colors.yellowAccent;
                  currentUiMessage =
                      "Σωστό Ράφι (${widget.targetShelf}), αλλά λάθος εύρος LoC.\nΠεριέχει: $scannedShelfLocStart - $scannedShelfLocEnd.\nΨάχνετε: ${widget.targetBookLoc}.";
                  ttsMessageToSpeak =
                      "Σωστό ράφι, αλλά το βιβλίο δεν ανήκει εδώ. Ελέγξτε τα δεδομένα.";
                }
              } else {
                currentFeedbackColor = Colors.redAccent;
                currentUiMessage =
                    "Σφάλμα QR ραφιού (${widget.targetShelf}): Λείπει το εύρος LoC.";
                ttsMessageToSpeak =
                    "Σφάλμα στα δεδομένα του QR code του ραφιού.";
              }
            } else {
              currentFeedbackColor = Colors.yellowAccent;
              currentUiMessage =
                  "Λάθος Ράφι (είδα το $scannedShelfNum, ψάχνω το ${widget.targetShelf}).\nΣυνεχίστε στην άλλη πλευρά του διαδρόμου.";
              ttsMessageToSpeak =
                  "Λάθος ράφι. Σαρώστε την άλλη πλευρά του διαδρόμου.";
            }
          }
        } else {
          currentFeedbackColor = Colors.redAccent;
          currentUiMessage = "Σφάλμα QR ραφιού: Λείπει ο αριθμός ραφιού.";
          ttsMessageToSpeak = "Σφάλμα στα δεδομένα του QR code του ραφιού.";
        }
      } else {
        currentUiMessage = "Άγνωστος τύπος QR Code της εφαρμογής: '$qrType'.";
        currentFeedbackColor = Colors.redAccent;
        ttsMessageToSpeak = "Άγνωστος τύπος κωδικού QR.";
      }
    }

    if (_lastDetectedBarcode != barcode ||
        _uiMessage != currentUiMessage ||
        _feedbackColor != currentFeedbackColor ||
        _wasCorrectCorridorFound != tempCorrectCorridorFound ||
        _wasCorrectShelfFound != _wasCorrectShelfFound) {
      stateChanged = true;
      _uiMessage = currentUiMessage;
      _feedbackColor = currentFeedbackColor;
      _wasCorrectCorridorFound = tempCorrectCorridorFound;
      _lastDetectedBarcode = barcode;
    }

    if (!_wasCorrectCorridorFound && _corridorVibrationPlayedForThisDetection) {
      _corridorVibrationPlayedForThisDetection = false;
      stateChanged = true;
    }

    if (ttsMessageToSpeak != null && !_isTtsSpeaking && !_isTtsCoolingDown) {
      _speak(ttsMessageToSpeak);
    } else if (ttsMessageToSpeak != null) {
      debugPrint(
        "TTS Skipped: Speaking=$_isTtsSpeaking, CoolingDown=$_isTtsCoolingDown, Message: $ttsMessageToSpeak",
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
    if (_lastDetectedBarcode != null &&
        _uiMessage.isNotEmpty &&
        _uiMessage != "Αυτό το QR code δεν αφορά την εφαρμογή.") {
      // Αν έχουμε ήδη ένα συγκεκριμένο μήνυμα από την επεξεργασία του QR,
      // και δεν έχει βρεθεί το τελικό ράφι, το διατηρούμε.
      if (!_finalTargetFoundAndHandled) return;
    }
    if (_finalTargetFoundAndHandled) {
      // Αυτό το μήνυμα θα έχει τεθεί από την _processBarcodes όταν βρεθεί ο τελικός στόχος.
      // Δεν το αλλάζουμε εδώ, εκτός αν θέλουμε ένα γενικό μήνυμα επιτυχίας.
      return;
    }

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
      debugPrint(
        "Speak request ignored: TTS is busy or cooling down for '$text'",
      );
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

  bool isLocInRange(String targetLoc, String startLoc, String endLoc) {
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
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraService>(
      builder: (context, cameraService, child) {
        return Scaffold(
          appBar: myAppBar,
          body: _buildScannerBody(cameraService),
        );
      },
    );
  }

  Widget _buildScannerBody(CameraService cameraService) {
    if (!cameraService.isPermissionGranted &&
        _currentMode != QrScanningMode.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Απαιτείται άδεια κάμερας για τη σάρωση QR.'),
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Σφάλμα κάμερας: ${cameraService.errorMessage}\nΠαρακαλώ επανεκκινήστε την εφαρμογή ή ελέγξτε τις άδειες.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final previewSize = cameraService.previewSize;
    if (previewSize == null || previewSize.isEmpty) {
      return const Center(
        child: Text("Σφάλμα μεγέθους προεπισκόπησης. Επανεκκινήστε."),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        double scale = constraints.maxWidth / previewSize.width;
        double cameraWidgetHeight = previewSize.height * scale;
        final double maxAllocatedCameraHeight =
            constraints.maxHeight *
            (_wasCorrectShelfFound
                ? 0.60
                : 0.7); // * Μικραίνει αν εμφανιστεί το κουμπί

        if (cameraWidgetHeight > maxAllocatedCameraHeight) {
          cameraWidgetHeight = maxAllocatedCameraHeight;
          scale = cameraWidgetHeight / previewSize.height;
        }
        double cameraWidgetWidth = previewSize.width * scale;

        if (cameraWidgetHeight < 200 && constraints.maxHeight > 200) {
          cameraWidgetHeight = 200;
          scale = cameraWidgetHeight / previewSize.height;
          cameraWidgetWidth = previewSize.width * scale;
          if (cameraWidgetWidth > constraints.maxWidth) {
            cameraWidgetWidth = constraints.maxWidth;
            scale = cameraWidgetWidth / previewSize.width;
            cameraWidgetHeight = previewSize.height * scale;
          }
        }

        return SingleChildScrollView(
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: cameraWidgetWidth,
                    height: cameraWidgetHeight,
                    child:
                        (cameraService.controller != null &&
                                cameraService.controller!.value.isInitialized)
                            ? CameraPreview(cameraService.controller!)
                            : Container(
                              color: Colors.black,
                              child: const Center(
                                child: Text(
                                  "Kάμερα...",
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 12.0,
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
                  if (_isTtsSpeaking || _isTtsCoolingDown)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Icon(
                        _isTtsSpeaking
                            ? Icons.volume_up_rounded
                            : Icons.timer_outlined,
                        color: Colors.white.withAlpha(220),
                        size: 30,
                        shadows: const [
                          Shadow(blurRadius: 2, color: Colors.black54),
                        ],
                      ),
                    ),
                ],
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                color: Theme.of(
                  context,
                ).scaffoldBackgroundColor.withAlpha((255 * 0.9).round()),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Πληροφορίες Βιβλίου:",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Τίτλος: ${widget.bookTitle}",
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      "Συγγραφέας: ${widget.bookAuthor}",
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      "ISBN: ${widget.bookIsbn}",
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      "LoC: ${widget.targetBookLoc}",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
              // * ΚΟΥΜΠΙ ΟΛΟΚΛΗΡΩΣΗΣ
              if (_wasCorrectShelfFound)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 20.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                      textStyle: const TextStyle(fontSize: 18),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () {
                      if (_finalTargetFoundAndHandled) {
                        // Βεβαιωνόμαστε ότι ο τελικός στόχος έχει επιτευχθεί
                        // Υπολογίζουμε τον χρόνο μόνο αν δεν έχει ήδη υπολογιστεί
                        if (_timeToFindShelf == null &&
                            _startTime != null &&
                            _shelfFoundTime != null) {
                          _timeToFindShelf = _shelfFoundTime!.difference(
                            _startTime!,
                          );
                        } else if (_timeToFindShelf == null &&
                            _startTime != null) {
                          // Fallback αν ο χρήστης πάτησε πολύ γρήγορα
                          _shelfFoundTime = DateTime.now();
                          _timeToFindShelf = _shelfFoundTime!.difference(
                            _startTime!,
                          );
                        }

                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => BookFoundScreen(
                                  bookTitle: widget.bookTitle,
                                  bookAuthor: widget.bookAuthor,
                                  bookIsbn: widget.bookIsbn,
                                  bookLoc: widget.targetBookLoc,
                                  shelfNumber: widget.targetShelf,
                                  corridorLabel: widget.targetCorridorLabel,
                                  timeTaken: _timeToFindShelf,
                                ),
                          ),
                        );
                      } else {
                        // Εμφάνιση μηνύματος αν πατηθεί ενώ δεν έχει ολοκληρωθεί η εύρεση
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Η αναζήτηση δεν έχει ολοκληρωθεί πλήρως.",
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text('Ολοκλήρωση Αναζήτησης'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
