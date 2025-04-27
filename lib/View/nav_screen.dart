import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';

import 'package:inlib_nav/View/Painters/text_overlay_painter.dart';

class CorridorScanningScreen extends StatefulWidget {
  final String targetCorridor;
  final int targetShelf;

  const CorridorScanningScreen({
    super.key,
    required this.targetCorridor,
    required this.targetShelf,
  });

  @override
  State<CorridorScanningScreen> createState() => _CorridorScanningScreenState();
}

class _CorridorScanningScreenState extends State<CorridorScanningScreen> {
  List<CameraDescription>? _cameras;
  CameraController? _controller;
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  bool _isPermissionGranted = false;
  bool _isProcessing = false;
  // Κρατάω τα αναγνωρισμένα blocks για πιθανή μελλοντική χρήση ή debug
  //final List<TextBlock> _recognizedTextBlocks = [];

  bool _targetFound = false;
  bool _targetFoundSoundPlayed = false;
  Rect? _targetBoundingBox;
  Size? _imageSize;
  InputImageRotation? _imageRotation;

  // --- Για τον ήχο ---
  final _audioPlayer = AudioPlayer();
  bool _isPlayingCorridorSound = false;
  bool _isPlayingShelfSound = false;
  StreamSubscription? _playerCompleteSubscription;
  StreamSubscription? _playerStateSubscription;

  // Ορίζω τις διαδρομές των αρχείων ήχου εδώ
  static const String _soundPathShelfLeft = 'sounds/left_shelf.mp3';
  static const String _soundPathShelfRight = 'sounds/right_shelf.mp3';

  String? _lastDetectedIncorrectCorridor;

  // --- Μεταβλητές για τα εικονίδια ---
  ui.Image? _correctIcon;
  ui.Image? _wrongIcon;
  bool _iconsLoaded = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _setupAudioPlayerListeners();
    // Ξεκινάω τη φόρτωση των εικονιδίων
    _loadIcons();
    _requestCameraPermission();
  }

  // --- Νέα μέθοδος για φόρτωση εικονιδίων ---
  Future<void> _loadIcons() async {
    try {
      // Υποθέτουμε ότι τα εικονίδια είναι στον φάκελο assets/images/
      // Προσάρμοσε τις διαδρομές αν είναι αλλού
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
      //! Θα πρέπει να χειριστώ το σφάλμα(π.χ., μην εμφανίζεις εικονίδια)
    }
  }

  @override
  void dispose() {
    _playerCompleteSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    _stopCamera();
    _textRecognizer.close();
    _correctIcon?.dispose();
    _wrongIcon?.dispose();
    super.dispose();
  }

  // Ρυθμίζω τους listeners για τον audio player
  void _setupAudioPlayerListeners() {
    _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((event) {
      debugPrint("Audio playback completed.");
      // Αν έπαιζε ο ήχος του διαδρόμου και τελείωσε, παίζω τον ήχο του ραφιού
      if (_isPlayingCorridorSound) {
        _isPlayingCorridorSound = false;
        _playShelfSound();
      } else if (_isPlayingShelfSound) {
        // Αν έπαιζε ο ήχος του ραφιού, απλά σημειώνω ότι τελείωσε
        _isPlayingShelfSound = false;
      }
    });

    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((
      state,
    ) {
      debugPrint('AudioPlayer state changed: $state');
      // Αν ο player σταματήσει για κάποιο λόγο, ενημερώνω τις σημαίες μου
      if (state == PlayerState.stopped || state == PlayerState.completed) {
        if (_isPlayingCorridorSound) _isPlayingCorridorSound = false;
        if (_isPlayingShelfSound) _isPlayingShelfSound = false;
      }
    });
  }

  // Σταματάω την κάμερα και απελευθερώνω τον controller
  Future<void> _stopCamera() async {
    if (_controller != null) {
      try {
        // Πρέπει να ελέγξω αν το widget είναι ακόμα "mounted" πριν σταματήσω το stream
        if (mounted && _controller!.value.isStreamingImages) {
          await _controller!.stopImageStream();
        }
      } catch (e) {
        debugPrint("Error stopping image stream: $e");
      }
      // Και πάλι ελέγχω αν είναι mounted πριν κάνω dispose
      if (mounted && _controller!.value.isInitialized) {
        await _controller!.dispose();
      }
      _controller = null;
    }
  }

  // Ζητάω άδεια χρήσης της κάμερας
  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    // Ελέγχω αν το widget υπάρχει ακόμα πριν αλλάξω το state
    if (mounted) {
      setState(() {
        _isPermissionGranted = status == PermissionStatus.granted;
        if (_isPermissionGranted) {
          // Αν η άδεια δόθηκε, αρχικοποιώ την κάμερα
          _initializeCamera();
        }
      });
    }
  }

  // Αρχικοποιώ την κάμερα
  Future<void> _initializeCamera() async {
    // Σταματάω την προηγούμενη κάμερα πρώτα, αν υπάρχει
    await _stopCamera();

    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('Error: No cameras available');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Δεν βρέθηκαν διαθέσιμες κάμερες.')),
          );
        }
        return;
      }

      // Προτιμώ την πίσω κάμερα
      var camera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      // Δημιουργώ τον controller με υψηλή ανάλυση και χωρίς ήχο
      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        // Χρησιμοποιώ το κατάλληλο format ανάλογα την πλατφόρμα
        imageFormatGroup:
            Platform.isAndroid
                ? ImageFormatGroup.nv21
                : ImageFormatGroup.bgra8888,
      );

      await _controller!.initialize();

      // Παίρνω τον προσανατολισμό του αισθητήρα για το ML Kit
      _imageRotation = InputImageRotationValue.fromRawValue(
        camera.sensorOrientation,
      );
      if (_imageRotation == null) {
        debugPrint(
          "Warning: Could not get image rotation. Using default 0deg.",
        );
        _imageRotation = InputImageRotation.rotation0deg;
      }

      if (!mounted) return;
      // Ξεκινάω το stream των εικόνων για επεξεργασία
      await _controller!.startImageStream(_processCameraImage);

      if (mounted) {
        setState(() {}); // Ανανεώνω το UI για να δείξει την προεπισκόπηση
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Σφάλμα κατά την έναρξη της κάμερας: $e')),
        );
      }
      await _stopCamera(); // Σταματάω την κάμερα σε περίπτωση σφάλματος
      if (mounted) setState(() {});
    }
  }

  // Επεξεργάζομαι κάθε καρέ (frame) από την κάμερα
  Future<void> _processCameraImage(CameraImage image) async {
    // Αν γίνεται ήδη επεξεργασία ή το widget/controller δεν είναι έτοιμο, επιστρέφω
    if (_isProcessing ||
        !mounted ||
        _controller == null ||
        !_controller!.value.isInitialized ||
        !_iconsLoaded) {
      return;
    }

    _isProcessing = true;
    // Αποθηκεύω το μέγεθος της εικόνας για τον painter
    _imageSize = Size(image.width.toDouble(), image.height.toDouble());

    // Μετατρέπω την CameraImage σε InputImage για το ML Kit
    final inputImage = _inputImageFromCameraImage(
      image,
      _controller!.description.sensorOrientation,
    );

    if (inputImage != null) {
      try {
        // Καλώ το ML Kit για αναγνώριση κειμένου
        final RecognizedText recognizedText = await _textRecognizer
            .processImage(inputImage);
        if (mounted) {
          // Ενημερώνω τα αποτελέσματα στο UI
          _updateRecognitionResults(recognizedText);
        }
      } catch (e) {
        debugPrint("Error processing image with ML Kit: $e");
      } finally {
        // Σημειώνω ότι η επεξεργασία τελείωσε
        if (mounted) {
          _isProcessing = false;
        }
      }
    } else {
      // Αν το inputImage είναι null, απλά τελειώνω την επεξεργασία
      if (mounted) {
        _isProcessing = false;
      }
    }
  }

  // Ενημερώνω το state με βάση τα αποτελέσματα της αναγνώρισης κειμένου
  void _updateRecognitionResults(RecognizedText recognizedText) {
    if (!mounted || _isPlayingCorridorSound || _isPlayingShelfSound) {
      return;
    }

    String? detectedCorridorInFrame;
    Rect? detectedRectInFrame;
    bool targetFoundInFrame = false;

    // Ψάχνω για κείμενο της μορφής "UOWM <αριθμός>"
    final RegExp corridorRegex = RegExp(r'UOWM\s*(\d+)', caseSensitive: false);
    int? targetNumber;
    // Βρίσκω τον αριθμό-στόχο από το widget.targetCorridor
    final targetMatch = corridorRegex.firstMatch(widget.targetCorridor);
    if (targetMatch != null && targetMatch.group(1) != null) {
      targetNumber = int.tryParse(targetMatch.group(1)!);
    }

    if (targetNumber == null) {
      debugPrint(
        "Error: Could not parse target corridor number from ${widget.targetCorridor}",
      );
      // Αν δεν μπορώ να βρω τον αριθμό-στόχο, μηδενίζω τις μεταβλητές state
      setState(() {
        _targetFound = false;
        _targetBoundingBox = null;
        _lastDetectedIncorrectCorridor = null;
        _targetFoundSoundPlayed = false;
      });
      return;
    }

    // Ψάχνω σε κάθε block και γραμμή του αναγνωρισμένου κειμένου
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        final match = corridorRegex.firstMatch(line.text);
        if (match != null && match.group(1) != null) {
          detectedCorridorInFrame = match.group(0)!.toUpperCase().trim();
          detectedRectInFrame = line.boundingBox;
          int? detectedNumber = int.tryParse(match.group(1)!);

          // Ελέγχω αν ο αριθμός που βρήκα είναι ο στόχος μου
          if (detectedNumber != null && detectedNumber == targetNumber) {
            targetFoundInFrame = true;
          }
          break; // Βρήκα μια πιθανή σήμανση, σταματάω την αναζήτηση στη γραμμή
        }
      }
      if (detectedCorridorInFrame != null) {
        break; // Βρήκα μια πιθανή σήμανση, σταματάω την αναζήτηση στο block
      }
    }

    // --- Λογική για την κατάσταση και τον ήχο ---
    bool updateStateNeeded = false;

    if (targetFoundInFrame) {
      // ΒΡΗΚΑ ΤΟΝ ΣΤΟΧΟ
      // Αν τον βρήκα τώρα ή αν άλλαξε η θέση του, χρειάζομαι update
      if (!_targetFound || _targetBoundingBox != detectedRectInFrame) {
        updateStateNeeded = true;
      }
      _targetFound = true;
      _targetBoundingBox = detectedRectInFrame;
      _lastDetectedIncorrectCorridor = null; // Δεν βλέπω πια λάθος διάδρομο

      // Παίζω τους ήχους ΜΟΝΟ αν δεν έχουν ήδη παιχτεί γι' αυτόν τον εντοπισμό
      if (!_targetFoundSoundPlayed) {
        _playCorridorSound(targetNumber); // Παίζω πρώτα τον ήχο του διαδρόμου
        // --- Προσθήκη Δόνησης ---
        Vibration.hasVibrator().then((hasVibrator) {
          if (hasVibrator) {
            Vibration.vibrate(
              duration: 200,
              amplitude: 128,
            ); // Πειραματίσου με duration/amplitude
            debugPrint("Vibrated!");
          }
        });
        _targetFoundSoundPlayed = true; // Σημειώνω ότι οι ήχοι παίχτηκαν
        updateStateNeeded = true; // Χρειάζεται update για να δείξει το πλαίσιο
      }
    } else {
      // ΔΕΝ ΒΡΕΘΗΚΕ Ο ΣΤΟΧΟΣ (είτε βρέθηκε λάθος είτε τίποτα)
      if (_targetFound) {
        // Αν *μόλις* τον έχασα, χρειάζομαι update
        updateStateNeeded = true;
      }
      _targetFound = false;
      _targetFoundSoundPlayed =
          false; // Μηδενίζω τη σημαία για να ξαναπαίξουν όταν βρεθεί

      if (detectedCorridorInFrame != null) {
        // Βρέθηκε λάθος διάδρομος, ενημερώνω το πλαίσιο αν είναι νέος ή σε άλλη θέση
        if (_targetBoundingBox != detectedRectInFrame ||
            _lastDetectedIncorrectCorridor != detectedCorridorInFrame) {
          _targetBoundingBox = detectedRectInFrame;
          _lastDetectedIncorrectCorridor = detectedCorridorInFrame;
          updateStateNeeded = true;
        }
      } else {
        // Δεν βρέθηκε κανένας διάδρομος, καθαρίζω το πλαίσιο αν υπήρχε
        if (_targetBoundingBox != null) {
          _targetBoundingBox = null;
          _lastDetectedIncorrectCorridor = null;
          updateStateNeeded = true;
        }
      }
    }

    // Ενημερώνω το state (και το UI) μόνο αν χρειάζεται
    if (updateStateNeeded && mounted) {
      setState(() {});
    }
  }

  // Μετατρέπω το CameraImage σε InputImage
  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    int sensorOrientation,
  ) {
    try {
      // Συνδυάζω τα bytes από όλα τα planes της εικόνας
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(
        image.width.toDouble(),
        image.height.toDouble(),
      );
      // Παίρνω τον προσανατολισμό από τον αισθητήρα
      final InputImageRotation imageRotation =
          InputImageRotationValue.fromRawValue(sensorOrientation) ??
          InputImageRotation.rotation0deg;
      // Παίρνω το format της εικόνας
      final InputImageFormat inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;
      // Παίρνω τα bytes per row (σημαντικό για το ML Kit)
      final int bytesPerRow =
          image.planes.isNotEmpty ? image.planes[0].bytesPerRow : 0;
      if (bytesPerRow == 0) {
        // Αυτό μπορεί να προκαλέσει προβλήματα στο ML Kit
        debugPrint("Warning: bytesPerRow is 0. ML Kit might fail.");
      }

      // Δημιουργώ τα metadata
      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: bytesPerRow,
      );

      // Δημιουργώ το InputImage
      final InputImage inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageData,
      );

      return inputImage;
    } catch (e) {
      debugPrint("Error creating InputImage: $e");
      return null;
    }
  }

  // Παίζω τον ήχο για τον διάδρομο που βρέθηκε
  Future<void> _playCorridorSound(int corridorNumber) async {
    // Αν παίζει ήδη κάποιος ήχος, δεν κάνω τίποτα
    if (_isPlayingCorridorSound || _isPlayingShelfSound) {
      return;
    }

    // Φτιάχνω το path του αρχείου ήχου δυναμικά
    final String corridorSoundPath =
        'sounds/go_to_corridor_$corridorNumber.mp3';
    debugPrint("Attempting to play corridor sound: $corridorSoundPath");

    // ΣΗΜ: Ο έλεγχος ύπαρξης αρχείου για assets δεν είναι τόσο απλός,
    // οπότε απλά προσπαθώ να παίξω τον ήχο.

    try {
      await _audioPlayer.stop(); // Σταματάω ό,τι έπαιζε πριν
      await _audioPlayer.play(AssetSource(corridorSoundPath));
      if (mounted) {
        // Σημειώνω ότι παίζει ο ήχος του διαδρόμου
        setState(() {
          _isPlayingCorridorSound = true;
          _isPlayingShelfSound = false;
        });
      }
      debugPrint("Playing corridor sound: $corridorSoundPath");
    } catch (e) {
      debugPrint("Error playing corridor sound '$corridorSoundPath': $e");
      if (mounted) {
        // Σημειώνω ότι απέτυχε η αναπαραγωγή
        setState(() {
          _isPlayingCorridorSound = false;
        });
      }
    }
  }

  // Παίζω τον ήχο για το ράφι (αφού τελειώσει ο ήχος του διαδρόμου)
  Future<void> _playShelfSound() async {
    // Έξτρα έλεγχος για να είμαι σίγουρος ότι δεν παίζει κάτι άλλο
    if (_isPlayingShelfSound || _isPlayingCorridorSound) {
      return;
    }

    // Βρίσκω ποιον ήχο θα παίξω (αριστερό/δεξιό ράφι)
    String shelfSoundPath;
    if (widget.targetShelf % 2 != 0) {
      // Μονός αριθμός = Αριστερό ράφι
      shelfSoundPath = _soundPathShelfLeft;
    } else {
      // Ζυγός αριθμός = Δεξιό ράφι
      shelfSoundPath = _soundPathShelfRight;
    }
    debugPrint("Attempting to play shelf sound: $shelfSoundPath");

    try {
      // Δεν χρειάζεται stop() εδώ, καλείται μόνο αφού τελειώσει ο προηγούμενος ήχος
      await _audioPlayer.play(AssetSource(shelfSoundPath));
      if (mounted) {
        // Σημειώνω ότι παίζει ο ήχος του ραφιού
        setState(() {
          _isPlayingShelfSound = true;
          _isPlayingCorridorSound = false;
        });
      }
      debugPrint("Playing shelf sound: $shelfSoundPath");
    } catch (e) {
      debugPrint("Error playing shelf sound '$shelfSoundPath': $e");
      if (mounted) {
        // Σημειώνω ότι απέτυχε η αναπαραγωγή
        setState(() {
          _isPlayingShelfSound = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Αναζήτηση: ${widget.targetCorridor} / Ράφι ${widget.targetShelf}",
        ),
      ),
      // Χρησιμοποιώ ξεχωριστή μέθοδο για το κυρίως περιεχόμενο (body)
      body: _buildBody(),
    );
  }

  // Δημιουργώ το περιεχόμενο του Scaffold (body)
  Widget _buildBody() {
    // Αν δεν έχω άδεια κάμερας, δείχνω μήνυμα και κουμπί
    if (!_isPermissionGranted) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Απαιτείται άδεια κάμερας.'),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _requestCameraPermission,
              child: const Text('Χορήγηση Άδειας'),
            ),
          ],
        ),
      );
    }
    // Αν η κάμερα δεν έχει αρχικοποιηθεί, δείχνω indicator
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        !_iconsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    // Αν υπάρχει σφάλμα στην κάμερα, το δείχνω
    if (_controller!.value.hasError) {
      return Center(
        child: Text('Σφάλμα κάμερας: ${_controller!.value.errorDescription}'),
      );
    }

    // Χρησιμοποιώ LayoutBuilder για να πάρω τα constraints του χώρου
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size previewSize = _controller!.value.previewSize ?? Size.zero;
        if (previewSize.isEmpty) {
          return const Center(child: Text("Σφάλμα μεγέθους προεπισκόπησης"));
        }

        // Υπολογίζω το scale για να χωράει η προεπισκόπηση στα constraints
        double scale = constraints.maxWidth / previewSize.width;
        var cameraWidgetHeight = previewSize.height * scale;
        if (cameraWidgetHeight > constraints.maxHeight) {
          cameraWidgetHeight = constraints.maxHeight;
          scale = cameraWidgetHeight / previewSize.height;
        }
        var cameraWidgetWidth = previewSize.width * scale;

        // Χρησιμοποιώ Stack για να βάλω την προεπισκόπηση και το overlay
        return Stack(
          alignment: Alignment.center,
          children: [
            // Το widget της προεπισκόπησης της κάμερας
            SizedBox(
              width: cameraWidgetWidth,
              height: cameraWidgetHeight,
              child: CameraPreview(_controller!),
            ),

            // Το CustomPaint για το overlay (πλαίσιο γύρω από το κείμενο)
            if (_imageSize != null && previewSize != Size.zero)
              SizedBox(
                width: cameraWidgetWidth,
                height: cameraWidgetHeight,
                child: CustomPaint(
                  painter: TextOverlayPainter(
                    // recognisedTextBlocks δεν χρησιμοποιείται πια για ζωγραφική
                    targetBoundingBox: _targetBoundingBox,
                    imageSize: _imageSize!,
                    previewSize: previewSize,
                    scale: scale,
                    isTargetFound: _targetFound,
                    // Περνάω τα φορτωμένα εικονίδια στον painter
                    correctIcon: _correctIcon,
                    wrongIcon: _wrongIcon,
                    // Περνάω και τη σημαία για το αν βρέθηκε λάθος στόχος
                    isWrongTargetFound:
                        !_targetFound && _lastDetectedIncorrectCorridor != null,
                  ),
                ),
              ),
            // Ένα κείμενο στο κάτω μέρος που δείχνει την κατάσταση
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
                  color: Colors.black.withValues(), // Ημιδιαφανές μαύρο φόντο
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  _targetFound
                      ? 'ΒΡΕΘΗΚΕ: ${widget.targetCorridor}!' // Μήνυμα επιτυχίας
                      : _lastDetectedIncorrectCorridor != null
                      ? 'Βλέπω: $_lastDetectedIncorrectCorridor. Ψάχνω: ${widget.targetCorridor}' // Βλέπω λάθος διάδρομο
                      : 'Σάρωση για ${widget.targetCorridor}...', // Μήνυμα αναζήτησης
                  style: TextStyle(
                    color:
                        _targetFound
                            ? Colors.lightGreenAccent
                            : Colors.white, // Πράσινο αν βρέθηκε, άσπρο αλλιώς
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
}
