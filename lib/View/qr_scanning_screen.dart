import 'dart:async';
import 'dart:convert'; // Για το jsonDecode
import 'dart:io'; // Για το Platform

import 'package:flutter_tts/flutter_tts.dart'; // Για την εκφώνηση
import 'package:camera/camera.dart'; // Για την κάμερα
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart'; // Για το σκανάρισμα barcode
import 'package:provider/provider.dart'; // Για το CameraService
import 'package:vibration/vibration.dart'; // Για τη δόνηση

import 'package:inlib_nav/Services/camera_service.dart';
// ! ΣΗΜΑΝΤΙΚΟ: Δεν χρειάζεται να εισάγεις το dummy_books_service.dart εδώ,
// ! τα στοιχεία του βιβλίου έρχονται ως παράμετροι.

// Οι καταστάσεις λειτουργίας μου: ψάχνω διάδρομο ή ράφι ή έχω σφάλμα.
enum QrScanningMode { lookingForCorridor, lookingForShelf, error }

/// Η οθόνη μου για τη σάρωση QR.
class QrScanningScreen extends StatefulWidget {
  final String
  targetCorridorLabel; // Ο διάδρομος-στόχος μου (π.χ., "ΔΙΑΔΡΟΜΟΣ 1")
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
    // Οι νέες παράμετροι για τα στοιχεία του βιβλίου
    required this.bookTitle,
    required this.bookAuthor,
    required this.bookIsbn,
  });

  @override
  State<QrScanningScreen> createState() => _QrScanningScreenState();
}

class _QrScanningScreenState extends State<QrScanningScreen> {
  // Χρησιμοποιώ το google_mlkit_barcode_scanning για αναγνώριση QR
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  bool _isProcessingQr =
      false; // Για να μην επεξεργάζομαι πολλά καρέ ταυτόχρονα

  QrScanningMode _currentMode = QrScanningMode.lookingForCorridor;
  String _uiMessage = ""; // Το μήνυμα που θα δείχνω στον χρήστη
  Color _feedbackColor = Colors.white; // Το χρώμα του μηνύματος

  // Κρατάω το τελευταίο QR που είδα (μόνο το αντικείμενο Barcode)
  Barcode? _lastDetectedBarcode;

  // Για την εκφώνηση οδηγιών
  late FlutterTts flutterTts;
  bool _isTtsSpeaking = false;
  bool _isTtsCoolingDown = false; // Περίοδος αναμονής μετά την εκφώνηση
  Timer? _ttsCooldownTimer;
  final Duration _ttsCooldownDuration = const Duration(
    seconds: 5,
  ); // 5 δευτερόλεπτα αναμονή

  // Για την περίπτωση που δεν βρίσκω QR code για πολλή ώρα
  Timer? _notFoundTimer;
  bool _notFoundMessageSpoken = false;
  final int _notFoundTimeoutSeconds = 20; // 20 δευτερόλεπτα timeout

  // Βοηθητικές μεταβλητές για τη λογική της πλοήγησης
  bool _wasCorrectCorridorFound =
      false; // Αν βρήκα τον σωστό διάδρομο έστω μία φορά
  bool _wasCorrectShelfFound = false; // Αν βρήκα το σωστό ράφι έστω μία φορά
  bool _corridorVibrationPlayedForThisDetection =
      false; // Για να παίζει η δόνηση μία φορά ανά εντοπισμό διαδρόμου

  // Το prefix που περιμένω στα QR codes της εφαρμογής μου
  // Μπορείς να το αλλάξεις αν τα QR σου έχουν κάποιο άλλο συγκεκριμένο pattern
  // ή αν δεν θέλεις να βασιστείς σε prefix αλλά μόνο στο πεδίο 'type'.
  // Για τώρα, θα ελέγχω μόνο την ύπαρξη του πεδίου 'type'.
  // final String _appQrPrefix = "inlib_nav::"; // Παράδειγμα prefix

  @override
  void initState() {
    super.initState();
    // Αρχικοποιώ το TTS
    flutterTts = FlutterTts();
    _initializeTts();

    // Παίρνω το CameraService μέσω Provider
    final cameraService = context.read<CameraService>();
    // Ξεκινάω την κάμερα
    _initializeCameraSystem(cameraService);

    // Θέτω το αρχικό μήνυμα στο UI
    _setUiMessageForMode();
    // Ξεκινάω το χρονόμετρο για την περίπτωση που δεν βρεθεί QR
    _startNotFoundTimer();
  }

  // Αρχικοποιώ το σύστημα της κάμερας (άδειες, controller)
  Future<void> _initializeCameraSystem(CameraService cameraService) async {
    bool granted = await cameraService.requestPermission(); // Ζητάω άδεια
    if (granted && mounted) {
      // Αν μου δόθηκε η άδεια και το widget είναι ακόμα στο δέντρο
      await cameraService.initializeController(
        resolutionPreset:
            ResolutionPreset.medium, // Μέτρια ανάλυση αρκεί για QR
        onImageAvailable:
            _processCameraImage, // Η συνάρτηση που θα καλείται για κάθε καρέ
      );
      // Αν η κάμερα αρχικοποιήθηκε και δεν κάνει ήδη stream, το ξεκινάω
      if (mounted &&
          cameraService.isInitialized &&
          !cameraService.isStreamingImages) {
        await cameraService.startImageStream(_processCameraImage);
      }
    } else if (!granted && mounted) {
      // Αν δεν μου δόθηκε η άδεια
      setState(() {
        _currentMode = QrScanningMode.error;
        _setUiMessageForMode(error: "Η άδεια κάμερας είναι απαραίτητη.");
      });
    }
  }

  // Αρχικοποιώ τις ρυθμίσεις του Text-to-Speech
  Future<void> _initializeTts() async {
    await flutterTts.setLanguage("el-GR"); // Ελληνικά
    await flutterTts.setSpeechRate(0.5); // Ταχύτητα ομιλίας
    await flutterTts.setPitch(1.0); // Τόνος φωνής

    // Ορίζω handlers για την κατάσταση του TTS
    flutterTts.setStartHandler(() {
      if (mounted) {
        setState(() {
          _isTtsSpeaking = true;
          _isTtsCoolingDown =
              true; // Ξεκινάει και το cooldown μαζί με την ομιλία
        });
      }
    });

    flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isTtsSpeaking = false;
          // Όταν τελειώσει η ομιλία, ξεκινάει ο timer για το cooldown
          _ttsCooldownTimer?.cancel();
          _ttsCooldownTimer = Timer(_ttsCooldownDuration, () {
            if (mounted) {
              setState(() {
                _isTtsCoolingDown = false; // Τέλος cooldown
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
        // Αν γίνει λάθος, ακυρώνω την ομιλία και το cooldown
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
    // Καθαρίζω τους πόρους όταν φεύγω από την οθόνη
    _notFoundTimer?.cancel();
    _ttsCooldownTimer?.cancel();
    flutterTts.stop();
    _barcodeScanner.close();
    // Το CameraService ΔΕΝ το κάνω dispose εδώ, γιατί είναι ChangeNotifierProvider
    // και μπορεί να χρησιμοποιείται και από άλλες οθόνες ή να θέλω να διατηρήσω
    // την κατάστασή του. Η διαχείρισή του γίνεται στο main.dart.
    super.dispose();
  }

  // Ξεκινάω το χρονόμετρο που θα με ειδοποιήσει αν δεν βρω QR για πολλή ώρα
  void _startNotFoundTimer() {
    _notFoundTimer?.cancel(); // Ακυρώνω τυχόν προηγούμενο
    _notFoundMessageSpoken = false;
    _notFoundTimer = Timer(Duration(seconds: _notFoundTimeoutSeconds), () {
      // Αν περάσει ο χρόνος και δεν έχω βρει κάτι και δεν έχω μιλήσει ήδη
      if (mounted &&
          !_notFoundMessageSpoken &&
          _lastDetectedBarcode == null && // Έλεγχος αν έχω δει κάποιο barcode
          !_wasCorrectShelfFound) {
        // Και δεν έχω βρει το τελικό ράφι
        String msg =
            _currentMode == QrScanningMode.lookingForCorridor
                ? "Δεν εντοπίστηκε QR code διαδρόμου. Παρακαλώ, ελέγξτε την περιοχή γύρω σας."
                : "Δεν εντοπίστηκε QR code ραφιού. Βεβαιωθείτε ότι βρίσκεστε στη σωστή πλευρά του διαδρόμου.";
        _speak(msg); // Εκφωνώ το μήνυμα
        if (mounted) {
          setState(() {
            _notFoundMessageSpoken = true;
            _uiMessage = msg;
            _feedbackColor = Colors.grey; // Γκρι χρώμα για το μήνυμα
          });
        }
      }
    });
  }

  // Επαναφέρω το χρονόμετρο αν χρειαστεί (π.χ. αν είδα ένα QR αλλά δεν ήταν το σωστό)
  void _resetNotFoundTimerIfNeeded() {
    if (_notFoundMessageSpoken) {
      _notFoundMessageSpoken = false;
    }
    _notFoundTimer?.cancel();
    if (!_wasCorrectShelfFound) {
      // Αν δεν έχω βρει το τελικό ράφι, το ξαναξεκινάω
      _startNotFoundTimer();
    }
  }

  // Ακυρώνω όλα τα χρονόμετρα (TTS cooldown, not found)
  void _cancelAllTimers() {
    _ttsCooldownTimer?.cancel();
    _notFoundTimer?.cancel();
    _notFoundMessageSpoken = false;
  }

  // Επεξεργάζομαι το κάθε καρέ από την κάμερα
  Future<void> _processCameraImage(CameraImage image) async {
    final cameraService = Provider.of<CameraService>(context, listen: false);
    // Αν επεξεργάζομαι ήδη, ή το widget δεν είναι στο δέντρο, ή η κάμερα δεν είναι έτοιμη, δεν κάνω τίποτα
    if (_isProcessingQr || !mounted || !cameraService.isInitialized) return;

    _isProcessingQr = true; // Σημαδεύω ότι ξεκίνησα επεξεργασία

    final sensorOrientation = cameraService.sensorOrientation;
    if (sensorOrientation == null) {
      _isProcessingQr = false;
      return; // Χρειάζομαι τον προσανατολισμό του αισθητήρα
    }

    // Μετατρέπω το CameraImage σε InputImage για το ML Kit
    final inputImage = _inputImageFromCameraImage(image, sensorOrientation);

    if (inputImage != null) {
      try {
        // Στέλνω το InputImage στον BarcodeScanner
        final List<Barcode> barcodes = await _barcodeScanner.processImage(
          inputImage,
        );
        if (mounted) {
          // Αν βρέθηκαν barcodes, τα επεξεργάζομαι
          _processBarcodes(barcodes);
        }
      } catch (e) {
        debugPrint("Barcode Scanner Error: $e");
      } finally {
        if (mounted) {
          _isProcessingQr = false; // Σημαδεύω ότι τελείωσα την επεξεργασία
        }
      }
    } else {
      if (mounted) {
        _isProcessingQr = false;
      }
    }
  }

  // Βοηθητική συνάρτηση για να πάρω τον αριθμό του διαδρόμου από το label
  int? _parseCorridorNumber(String? label) {
    if (label == null) return null;
    // Ψάχνω για "ΔΙΑΔΡΟΜΟΣ" ακολουθούμενο από έναν ή περισσότερους αριθμούς
    final match = RegExp(
      r'ΔΙΑΔΡΟΜΟΣ\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(label);
    if (match != null && match.group(1) != null) {
      return int.tryParse(match.group(1)!); // Επιστρέφω τον αριθμό
    }
    return null;
  }

  // Επεξεργάζομαι τα barcodes που βρήκα
  void _processBarcodes(List<Barcode> barcodes) {
    if (barcodes.isEmpty) {
      // Αν δεν βλέπω QR code τώρα, αλλά είχα δει προηγουμένως, επαναφέρω την κατάσταση
      if (_lastDetectedBarcode != null ||
          _wasCorrectCorridorFound ||
          _wasCorrectShelfFound ||
          _corridorVibrationPlayedForThisDetection) {
        if (mounted) {
          setState(() {
            _lastDetectedBarcode = null;
            _wasCorrectCorridorFound = false;
            _wasCorrectShelfFound = false;
            _corridorVibrationPlayedForThisDetection = false;
            _setUiMessageForMode(); // Θέτω το μήνυμα ανάλογα την κατάσταση πλοήγησης
            _resetNotFoundTimerIfNeeded(); // Επανεκκινώ το χρονόμετρο "not found"
          });
        }
      }
      return; // Δεν βρέθηκε κανένα barcode
    }

    final barcode = barcodes.first; // Παίρνω το πρώτο barcode που βρέθηκε
    final qrDataString = barcode.rawValue; // Τα δεδομένα του QR ως string

    _resetNotFoundTimerIfNeeded(); // Είδα ένα QR, οπότε κάνω reset τον timer

    if (qrDataString == null) return; // Αν δεν έχει δεδομένα, δεν κάνω κάτι

    Map<String, dynamic>? qrData;
    bool isAppQr = false; // Σημαία για το αν το QR ανήκει στην εφαρμογή

    try {
      qrData = jsonDecode(qrDataString); // Προσπαθώ να το κάνω decode ως JSON
      // Ελέγχω αν το JSON έχει το πεδίο 'type', που σηματοδοτεί ότι είναι QR της εφαρμογής
      if (qrData != null && qrData.containsKey('type')) {
        isAppQr = true;
      }
    } catch (e) {
      // Αν δεν είναι έγκυρο JSON, ή γίνει κάποιο άλλο σφάλμα, δεν είναι της εφαρμογής
      debugPrint(
        "QR Data is not valid JSON or processing error: '$qrDataString'. Error: $e",
      );
      isAppQr = false;
      qrData = null; // Σιγουρεύομαι ότι το qrData είναι null
    }

    // Μεταβλητές για την ενημέρωση του UI και του TTS
    bool stateChanged = false;
    String currentUiMessage = _uiMessage;
    Color currentFeedbackColor = _feedbackColor;
    bool currentCorrectCorridor =
        _wasCorrectCorridorFound; // Διατηρώ την προηγούμενη κατάσταση
    bool currentCorrectShelf =
        _wasCorrectShelfFound; // Διατηρώ την προηγούμενη κατάσταση
    String? ttsMessageToSpeak;

    if (!isAppQr) {
      // Αν το QR ΔΕΝ ανήκει στην εφαρμογή
      currentUiMessage = "Αυτό το QR code δεν αφορά την εφαρμογή.";
      currentFeedbackColor = Colors.orange; // Πορτοκαλί χρώμα για προειδοποίηση
      ttsMessageToSpeak = "Αυτό το QR code δεν αφορά την εφαρμογή.";
      // Δεν αλλάζω τις _wasCorrectCorridorFound, _wasCorrectShelfFound
      // Δεν θέλω να χάσω την πρόοδο αν κατά λάθος σκάναρα ένα άσχετο QR
    } else if (qrData != null) {
      // Αν το QR ανήκει στην εφαρμογή και έχω τα δεδομένα του
      final qrType = qrData['type'];

      if (qrType == 'corridor') {
        String? scannedLabel = qrData['label'];
        if (scannedLabel != null &&
            scannedLabel == widget.targetCorridorLabel) {
          // Βρήκα τον ΣΩΣΤΟ ΔΙΑΔΡΟΜΟ
          currentCorrectCorridor = true;
          currentFeedbackColor = Colors.cyanAccent;
          String shelfSide =
              widget.targetShelf % 2 != 0 ? "στα αριστερά" : "στα δεξιά";
          currentUiMessage =
              "Βρέθηκε ο $scannedLabel.\nΤο Ράφι ${widget.targetShelf} είναι $shelfSide σας.\nΣαρώστε το QR του Ραφιού.";
          if (!_corridorVibrationPlayedForThisDetection) {
            Vibration.vibrate(duration: 150); // Δόνηση!
            _corridorVibrationPlayedForThisDetection = true;
          }
          // Αν ήμουν σε κατάσταση αναζήτησης διαδρόμου, αλλάζω σε αναζήτηση ραφιού
          if (_currentMode == QrScanningMode.lookingForCorridor) {
            ttsMessageToSpeak =
                "Βρέθηκε ο $scannedLabel. Το ράφι ${widget.targetShelf} είναι $shelfSide σας. Σαρώστε το QR code του ραφιού.";
            _currentMode = QrScanningMode.lookingForShelf;
          } else {
            // Αν ήδη έψαχνα ράφι (π.χ. σάρωσα ξανά τον ίδιο διάδρομο), απλά το επιβεβαιώνω
            ttsMessageToSpeak = "Σωστός διάδρομος: $scannedLabel.";
          }
        } else if (scannedLabel != null) {
          // Βρήκα ΛΑΘΟΣ ΔΙΑΔΡΟΜΟ
          currentCorrectCorridor = false; // Δεν είναι ο σωστός
          final int? targetNumber = _parseCorridorNumber(
            widget.targetCorridorLabel,
          );
          final int? scannedNumber = _parseCorridorNumber(scannedLabel);
          String baseMsg = "Λάθος Διάδρομος";
          String directionMsg = "";
          if (targetNumber != null && scannedNumber != null) {
            // Υπολογίζω την κατεύθυνση προς τον σωστό διάδρομο
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
          _corridorVibrationPlayedForThisDetection =
              false; // Reset για τη δόνηση
        }
      } else if (qrType == 'shelf') {
        // Αν σάρωσα QR ΡΑΦΙΟΥ
        if (_currentMode == QrScanningMode.lookingForCorridor) {
          // Αν ακόμα έψαχνα διάδρομο, του λέω να σκανάρει πρώτα τον διάδρομο
          currentUiMessage =
              "Είδα Ράφι. Σάρωσε πρώτα το QR του διαδρόμου ${widget.targetCorridorLabel}.";
          currentFeedbackColor = Colors.grey;
        } else {
          // Αν ήμουν σε κατάσταση αναζήτησης ραφιού (δηλαδή έχω βρει τον σωστό διάδρομο)
          String? startLoc = qrData['loc_start'];
          String? endLoc = qrData['loc_end'];
          int? shelfNum =
              qrData['shelf_number']; // Παίρνω και τον αριθμό του ραφιού από το QR

          // Έλεγχος αν ο αριθμός ραφιού του QR ταιριάζει με τον στόχο μου
          if (shelfNum != null && shelfNum == widget.targetShelf) {
            if (startLoc != null && endLoc != null) {
              // Ελέγχω αν το LoC του βιβλίου είναι εντός του εύρους του ραφιού
              bool isInRange = isLocInRange(
                widget.targetBookLoc,
                startLoc,
                endLoc,
              );
              if (isInRange) {
                // ΒΡΗΚΑ ΤΟ ΣΩΣΤΟ ΡΑΦΙ ΚΑΙ ΤΟ ΒΙΒΛΙΟ ΕΙΝΑΙ ΕΔΩ!
                currentCorrectShelf = true;
                currentFeedbackColor = Colors.lightGreenAccent;
                currentUiMessage =
                    "ΤΟ ΒΙΒΛΙΟ ΕΙΝΑΙ ΕΔΩ!\nΡάφι ${widget.targetShelf} (${widget.targetCorridorLabel})\nΚωδικός: ${widget.targetBookLoc}";
                ttsMessageToSpeak = "Το βιβλίο βρίσκεται σε αυτό το ράφι.";
                Vibration.vibrate(
                  duration: 300,
                  amplitude: 192,
                ); // Μεγαλύτερη δόνηση!
                _cancelAllTimers(); // Σταματάω τα πάντα, η πλοήγηση ολοκληρώθηκε
              } else {
                // Λάθος εύρος LoC στο σωστό ράφι (λογικά δεν θα έπρεπε να συμβεί αν τα QR είναι σωστά)
                currentCorrectShelf = false;
                currentUiMessage =
                    "Σωστό Ράφι (${widget.targetShelf}), αλλά λάθος εύρος LoC.\nΑυτό περιέχει: $startLoc - $endLoc.\nΨάχνετε: ${widget.targetBookLoc}.\nΕλέγξτε τα δεδομένα.";
                ttsMessageToSpeak =
                    "Σωστό ράφι, αλλά το βιβλίο δεν ανήκει εδώ. Ελέγξτε τα δεδομένα.";
                currentFeedbackColor = Colors.yellowAccent;
              }
            } else {
              // Το QR του ραφιού δεν έχει loc_start ή loc_end (πρόβλημα δεδομένων)
              currentCorrectShelf = false;
              currentUiMessage =
                  "Σφάλμα στα δεδομένα του QR ραφιού (λείπει το εύρος LoC).";
              ttsMessageToSpeak = "Σφάλμα στα δεδομένα του QR code του ραφιού.";
              currentFeedbackColor = Colors.redAccent;
            }
          } else if (shelfNum != null) {
            // Λάθος αριθμός ραφιού
            currentCorrectShelf = false;
            currentUiMessage =
                "Λάθος Ράφι (είδα το $shelfNum, ψάχνω το ${widget.targetShelf}).\nΣυνεχίστε στην ίδια πλευρά του διαδρόμου.";
            ttsMessageToSpeak = "Λάθος ράφι. Συνεχίστε τη σάρωση.";
            currentFeedbackColor = Colors.yellowAccent;
          } else {
            // Το QR του ραφιού δεν έχει αριθμό (πρόβλημα δεδομένων)
            currentCorrectShelf = false;
            currentUiMessage =
                "Σφάλμα στα δεδομένα του QR ραφιού (λείπει ο αριθμός ραφιού).";
            ttsMessageToSpeak = "Σφάλμα στα δεδομένα του QR code του ραφιού.";
            currentFeedbackColor = Colors.redAccent;
          }
        }
      } else {
        // Άγνωστος τύπος 'type' στο QR code της εφαρμογής
        currentUiMessage = "Άγνωστος τύπος QR Code της εφαρμογής: '$qrType'.";
        currentFeedbackColor = Colors.redAccent;
        ttsMessageToSpeak = "Άγνωστος τύπος κωδικού QR.";
      }
    }
    // --- Τέλος επεξεργασίας έγκυρου QR ---

    // Ενημερώνω το state αν κάτι άλλαξε
    if (_lastDetectedBarcode !=
            barcode || // Αν είναι διαφορετικό QR από το προηγούμενο
        _uiMessage != currentUiMessage ||
        _feedbackColor != currentFeedbackColor ||
        _wasCorrectCorridorFound != currentCorrectCorridor ||
        _wasCorrectShelfFound != currentCorrectShelf) {
      stateChanged = true;
      _uiMessage = currentUiMessage;
      _feedbackColor = currentFeedbackColor;
      _wasCorrectCorridorFound = currentCorrectCorridor;
      _wasCorrectShelfFound = currentCorrectShelf;
      _lastDetectedBarcode = barcode; // Αποθηκεύω το τρέχον barcode
    }

    // Αν δεν βρήκα τον σωστό διάδρομο, αλλά είχα παίξει τη δόνηση, την κάνω reset
    if (!currentCorrectCorridor) {
      if (_corridorVibrationPlayedForThisDetection) {
        _corridorVibrationPlayedForThisDetection = false;
        stateChanged = true;
      }
    }

    // Αν έχω μήνυμα για εκφώνηση και το TTS δεν μιλάει ή δεν είναι σε cooldown
    if (ttsMessageToSpeak != null && !_isTtsSpeaking && !_isTtsCoolingDown) {
      _speak(ttsMessageToSpeak);
    } else if (ttsMessageToSpeak != null) {
      // Αν το TTS είναι απασχολημένο, απλά το γράφω στο debug console
      debugPrint(
        "TTS Skipped: Speaking=$_isTtsSpeaking, CoolingDown=$_isTtsCoolingDown, Message: $ttsMessageToSpeak",
      );
    }

    // Αν κάτι άλλαξε, κάνω setState για να ενημερωθεί το UI
    if (stateChanged && mounted) {
      setState(() {});
    }
  }

  // Θέτω το μήνυμα στο UI ανάλογα την κατάσταση (mode) της πλοήγησης
  void _setUiMessageForMode({String? error}) {
    if (error != null) {
      _uiMessage = "Σφάλμα: $error";
      _feedbackColor = Colors.redAccent;
      _cancelAllTimers(); // Αν υπάρχει σφάλμα, σταματάω τα χρονόμετρα
      return;
    }
    // Αν έχω ήδη ένα μήνυμα από επεξεργασία QR, δεν το αλλάζω εδώ
    if (_lastDetectedBarcode != null &&
        _uiMessage.isNotEmpty &&
        _uiMessage != "Αυτό το QR code δεν αφορά την εφαρμογή.") {
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
        // Το μήνυμα σφάλματος θα έχει τεθεί ήδη
        _feedbackColor = Colors.redAccent;
        break;
    }
  }

  // Εκφωνώ το κείμενο
  Future<void> _speak(String text) async {
    if (_isTtsSpeaking || _isTtsCoolingDown) {
      debugPrint("Speak request ignored: TTS is busy or cooling down.");
      return;
    }
    try {
      await flutterTts.stop(); // Σταματάω τυχόν προηγούμενη εκφώνηση
      await flutterTts.speak(text); // Ξεκινάω τη νέα
      debugPrint("TTS Speak initiated for: $text");
    } catch (e) {
      debugPrint("TTS Error speaking: $e");
      // Αν γίνει λάθος, επαναφέρω τις σημαίες του TTS
      if (mounted) {
        setState(() {
          _isTtsSpeaking = false;
          _isTtsCoolingDown = false;
          _ttsCooldownTimer?.cancel();
        });
      }
    }
  }

  // Μετατρέπω το CameraImage σε InputImage
  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    int sensorOrientation,
  ) {
    final InputImageRotation imageRotation =
        InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation0deg;

    final InputImageFormat? inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw);

    // Ελέγχω αν το format υποστηρίζεται
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

  // Placeholder συνάρτηση για σύγκριση LoC.
  // !!! ΣΗΜΑΝΤΙΚΟ: Πρέπει να αντικατασταθεί με τη σωστή λογική σύγκρισης LoC
  // που χρησιμοποιείς στο dummy_books_service.dart ή όπου αλλού.
  bool isLocInRange(String targetLoc, String startLoc, String endLoc) {
    debugPrint(
      "Checking (placeholder) if '$targetLoc' is between '$startLoc' and '$endLoc'",
    );
    try {
      final String targetUpper = targetLoc.toUpperCase();
      final String startUpper = startLoc.toUpperCase();
      final String endUpper = endLoc.toUpperCase();
      // Αυτή είναι μια πολύ απλή αλφαριθμητική σύγκριση.
      // Μπορεί να μην είναι σωστή για όλες τις περιπτώσεις LoC.
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
          appBar: AppBar(title: Text(_getAppBarTitle())),
          body: _buildScannerBody(
            cameraService,
          ), // Αυτή η μέθοδος θα τροποποιηθεί
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
        return "Σφάλμα Σάρωσης";
    }
  }

  Widget _buildScannerBody(CameraService cameraService) {
    if (!cameraService.isPermissionGranted &&
        _currentMode != QrScanningMode.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Απαιτείται άδεια κάμερας για τη σάρωση QR.'),
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
        child: Text("Σφάλμα μεγέθους προεπισκόπησης κάμερας. Επανεκκινήστε."),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Υπολογισμοί για το scaling της προεπισκόπησης
        double scale = constraints.maxWidth / previewSize.width;
        double cameraWidgetHeight = previewSize.height * scale;

        // Περιορίζω το μέγιστο ύψος που μπορεί να πάρει η κάμερα
        // για να υπάρχει πάντα χώρος για τις πληροφορίες του βιβλίου,
        // ακόμα και σε landscape ή πολύ μικρές οθόνες, πριν χρειαστεί scroll.
        // Το υπόλοιπο θα καλυφθεί από το SingleChildScrollView.
        final double maxAllocatedCameraHeight =
            constraints.maxHeight * 0.7; // π.χ. 70% του διαθέσιμου ύψους

        if (cameraWidgetHeight > maxAllocatedCameraHeight) {
          cameraWidgetHeight = maxAllocatedCameraHeight;
          // Επαναυπολογίζω το scale αν άλλαξε το ύψος για να διατηρηθεί το aspect ratio
          scale = cameraWidgetHeight / previewSize.height;
        }
        double cameraWidgetWidth = previewSize.width * scale;

        // Αν το cameraWidgetHeight είναι πολύ μικρό, δίνω ένα λογικό ελάχιστο
        // (π.χ. για landscape mode σε πολύ στενή οθόνη)
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

        // Τυλίγω το Column με SingleChildScrollView
        return SingleChildScrollView(
          child: Column(
            // mainAxisSize: MainAxisSize.min, // Προαιρετικά, για να παίρνει το Column το ελάχιστο δυνατό ύψος
            children: [
              // Stack για την κάμερα και τα overlays της
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    // Χρησιμοποιώ SizedBox αντί για Expanded
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
                            ), // Placeholder αν ο controller δεν είναι έτοιμος
                  ),
                  // Το μήνυμα στο κάτω μέρος της κάμερας
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
                  // Εικονίδιο κατάστασης TTS
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
              // Container για τις πληροφορίες του βιβλίου
              Container(
                // Χρησιμοποιώ Container αντί για Expanded
                width: double.infinity, // Γεμίζει το πλάτος
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
            ],
          ),
        );
      },
    );
  }
}
