import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService with ChangeNotifier {
  CameraController? _controller;
  List<CameraDescription>? _cameras;

  bool _isPermissionGranted = false;
  bool _isInitializing = false;
  bool _isInitialized = false;
  bool _isDisposed = false;
  String? _errorMessage;

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

  Future<void> initializeController({
    ResolutionPreset resolutionPreset = ResolutionPreset.high,
    ImageFormatGroup? imageFormatGroup,
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

      final formatGroup =
          imageFormatGroup ??
          (Platform.isAndroid
              ? ImageFormatGroup
                  .nv21 //android
              : ImageFormatGroup.bgra8888); //  iOS

      _controller = CameraController(
        selectedCamera,
        resolutionPreset,
        enableAudio: false,
        imageFormatGroup: formatGroup,
      );

      await _controller!.initialize();

      // Ξεκινάω το stream
      if (onImageAvailable != null) {
        await startImageStream(onImageAvailable);
      }

      _isInitialized = true;
      _errorMessage = null;
      debugPrint("CameraService: Controller initialized successfully.");
    } on CameraException catch (e) {
      _errorMessage = "Camera Error: ${e.code} - ${e.description}";
      debugPrint("CameraService: Error initializing camera: $_errorMessage");
      _controller = null;
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
      return;
    }
    try {
      await _controller!.stopImageStream();
      debugPrint("CameraService: Image stream stopped.");
      _notify();
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
    super.dispose();
    debugPrint("CameraService: Disposed.");
  }

  // Βοηθητική μέθοδος για να καλώ το notifyListeners() μόνο αν δεν έχω κάνει dispose
  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }
}
