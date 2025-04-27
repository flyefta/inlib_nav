import 'dart:async';
import 'dart:io'; // Για το Platform.isAndroid

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service που έφτιαξα για να διαχειρίζομαι την κάμερα.
///
/// Χρησιμοποιώ το ChangeNotifier για να ενημερώνω τους listeners μου
/// για αλλαγές στην κατάσταση (άδεια, αρχικοποίηση, σφάλματα).
class CameraService with ChangeNotifier {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  bool _isPermissionGranted = false;
  bool _isInitializing = false;
  bool _isInitialized = false;
  bool _isDisposed = false;
  String? _errorMessage;

  // --- Getters για την κατάσταση (να ξέρω τι γίνεται) ---

  /// Επιστρέφει true αν μου έχει δοθεί άδεια για την κάμερα.
  bool get isPermissionGranted => _isPermissionGranted;

  /// Επιστρέφει true όσο αρχικοποιώ τον controller.
  bool get isInitializing => _isInitializing;

  /// Επιστρέφει true αν ο controller αρχικοποιήθηκε ΟΚ.
  bool get isInitialized => _isInitialized;

  /// Επιστρέφει τον controller μου. Null αν δεν είναι έτοιμος.
  CameraController? get controller => _controller;

  /// Επιστρέφει το μήνυμα λάθους, αν κάτι πήγε στραβά στην αρχικοποίηση.
  String? get errorMessage => _errorMessage;

  /// Επιστρέφει το μέγεθος του preview (για τους υπολογισμούς στο UI).
  Size? get previewSize => _controller?.value.previewSize;

  /// Επιστρέφει τον προσανατολισμό του αισθητήρα (για το ML Kit).
  int? get sensorOrientation => _controller?.description.sensorOrientation;

  /// Επιστρέφει true αν η κάμερα στέλνει stream τώρα.
  bool get isStreamingImages => _controller?.value.isStreamingImages ?? false;

  // --- Οι Μέθοδοί μου ---

  /// Ζητάω άδεια από τον χρήστη.
  /// Επιστρέφει true αν μου την έδωσε, αλλιώς false.
  Future<bool> requestPermission() async {
    final status = await Permission.camera.request();
    _isPermissionGranted = status == PermissionStatus.granted;
    if (!_isPermissionGranted) {
      _errorMessage = "Η άδεια κάμερας δεν δόθηκε.";
    } else {
      _errorMessage = null; // Καθαρίζω τυχόν παλιό σφάλμα άδειας
    }
    _notify();
    return _isPermissionGranted;
  }

  /// Αρχικοποιώ τον CameraController.
  ///
  /// Διαλέγω την πίσω κάμερα (αν βρω), την αρχικοποιώ και
  /// προαιρετικά ξεκινάω το image stream καλώντας την [onImageAvailable].
  ///
  /// Πρέπει να έχω πάρει άδεια πρώτα!
  Future<void> initializeController({
    ResolutionPreset resolutionPreset = ResolutionPreset.high,
    ImageFormatGroup?
    imageFormatGroup, // Προαιρετικό, θα διαλέξω αυτόματα αν δεν μου δώσεις
    Function(CameraImage image)? onImageAvailable,
  }) async {
    if (_isInitializing || _isInitialized) {
      debugPrint(
        "CameraService: Controller is already initializing or initialized.",
      );
      return;
    }
    if (!_isPermissionGranted) {
      _errorMessage = "CameraService Error: Camera permission not granted.";
      debugPrint(_errorMessage);
      _notify();
      // Καλύτερα να ξαναζητήσω άδεια ή να δείξω κάτι στο UI
      //await requestPermission(); // Εναλλακτικά, ξαναζητάω άδεια
      //if (!_isPermissionGranted) return;
      return;
    }

    _isInitializing = true;
    _isInitialized = false;
    _errorMessage = null;
    _notify();

    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw CameraException(
          'NoCamerasAvailable',
          'Δεν βρέθηκαν διαθέσιμες κάμερες.',
        );
      }

      // Προτιμώ την πίσω κάμερα
      CameraDescription selectedCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first, // Αλλιώς, παίρνω την πρώτη που βρίσκω
      );

      // Διαλέγω ImageFormatGroup αν δεν μου δώσουν
      final formatGroup =
          imageFormatGroup ??
          (Platform.isAndroid
              ? ImageFormatGroup
                  .nv21 // Αυτό θέλει συνήθως το ML Kit στο Android
              : ImageFormatGroup.bgra8888); // Αυτό συνήθως παίζει στο iOS

      _controller = CameraController(
        selectedCamera,
        resolutionPreset,
        enableAudio: false, // Δεν χρειάζομαι ήχο για το OCR
        imageFormatGroup: formatGroup,
      );

      await _controller!.initialize();

      // Ξεκινάω το stream αν μου έδωσαν callback
      if (onImageAvailable != null) {
        await startImageStream(onImageAvailable);
      }

      _isInitialized = true;
      _errorMessage = null;
      debugPrint("CameraService: Controller initialized successfully.");
    } on CameraException catch (e) {
      _errorMessage = "Camera Error: ${e.code} - ${e.description}";
      debugPrint("CameraService: Error initializing camera: $_errorMessage");
      _controller = null; // Σιγουρεύομαι ότι είναι null αν γίνει λάθος
      _isInitialized = false;
    } catch (e) {
      _errorMessage = "Unexpected Error: ${e.toString()}";
      debugPrint(
        "CameraService: Unexpected error initializing camera: $_errorMessage",
      );
      _controller = null;
      _isInitialized = false;
    } finally {
      _isInitializing = false;
      _notify(); // Ενημερώνω τους listeners για το τι έγινε
    }
  }

  /// Ξεκινάω το stream εικόνων.
  ///
  /// Καλώ την [onImageAvailable] για κάθε frame.
  /// Πρέπει να έχω αρχικοποιήσει τον controller πρώτα.
  Future<void> startImageStream(
    Function(CameraImage image) onImageAvailable,
  ) async {
    if (!_isInitialized || _controller == null) {
      debugPrint(
        "CameraService Error: Cannot start stream, controller not initialized.",
      );
      return;
    }
    if (_controller!.value.isStreamingImages) {
      debugPrint("CameraService: Stream already started.");
      return;
    }

    try {
      await _controller!.startImageStream(onImageAvailable);
      debugPrint("CameraService: Image stream started.");
      _notify(); // Ενημερώνω ότι άλλαξε η κατάσταση (isStreaming)
    } on CameraException catch (e) {
      _errorMessage =
          "Camera Error starting stream: ${e.code} - ${e.description}";
      debugPrint("CameraService: Error starting stream: $_errorMessage");
      _notify();
    }
  }

  /// Σταματάω το stream εικόνων.
  Future<void> stopImageStream() async {
    if (!_isInitialized ||
        _controller == null ||
        !_controller!.value.isStreamingImages) {
      // Δεν χρειάζεται να κάνω κάτι αν δεν τρέχει ήδη
      return;
    }
    try {
      await _controller!.stopImageStream();
      debugPrint("CameraService: Image stream stopped.");
      _notify(); // Ενημερώνω ότι άλλαξε η κατάσταση (isStreaming)
    } on CameraException catch (e) {
      _errorMessage =
          "Camera Error stopping stream: ${e.code} - ${e.description}";
      debugPrint("CameraService: Error stopping stream: $_errorMessage");
      _notify();
    }
  }

  /// Απελευθερώνω τους πόρους του CameraController και σταματάω το stream.
  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    debugPrint("CameraService: Disposing...");
    _isDisposed = true;
    // Σιγουρεύομαι ότι σταματάει το stream πριν το dispose
    await stopImageStream();
    await _controller?.dispose();
    _controller = null;
    _isInitialized = false;
    _isInitializing = false;
    super.dispose(); // Καλώ το dispose του ChangeNotifier
    debugPrint("CameraService: Disposed.");
  }

  // Βοηθητική μέθοδος για να καλώ το notifyListeners() μόνο αν δεν έχω κάνει dispose
  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }
}
