import 'package:ar_flutter_plugin_updated/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_updated/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_updated/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_updated/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_updated/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_updated/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_updated/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_updated/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_updated/models/ar_node.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class ObjectRecognitionWidget extends StatefulWidget {
  const ObjectRecognitionWidget({super.key});

  @override
  State<ObjectRecognitionWidget> createState() =>
      _ObjectRecognitionWidgetState();
}

class _ObjectRecognitionWidgetState extends State<ObjectRecognitionWidget> {
  ARSessionManager? arSessionManager;
  ARObjectManager? arObjectManager;
  ARAnchorManager? arAnchorManager;

  List<ARNode> nodes = [];
  List<ARAnchor> anchors = [];

  late CameraController _cameraController;
  late List<CameraDescription> _cameras;
  late ImageLabeler imageLabeler; // Αλλαγή εδώ
  bool isRecognizing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    imageLabeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.8),
    ); // Αρχικοποίηση εδώ
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    _cameraController = CameraController(_cameras[0], ResolutionPreset.medium);
    await _cameraController.initialize();
    _cameraController.startImageStream(_processImage);
  }

  Future<void> _processImage(CameraImage image) async {
    if (isRecognizing) return;
    isRecognizing = true;

    final inputImage = InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        // Αλλαγή εδώ
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.yuv420, // Αλλαγή εδώ
        bytesPerRow: image.planes[0].bytesPerRow, // Αλλαγή εδώ
      ),
    );

    final labels = await imageLabeler.processImage(inputImage);

    for (final label in labels) {
      if (label.label == '1') {
        _showARNode();
        break;
      }
    }

    isRecognizing = false;
  }

  void _showARNode() {
    var newAnchor = ARPlaneAnchor(transformation: Matrix4.identity());
    arAnchorManager!.addAnchor(newAnchor);
    anchors.add(newAnchor);

    var newNode = ARNode(
      type: NodeType.localGLTF2,
      uri: "assets/models/arrow/scene.gltf",
      scale: Vector3(0.2, 0.2, 0.2),
      position: Vector3(0.0, 0.0, 0.0),
      rotation: Vector4(1.0, 0.0, 0.0, 0.0),
    );
    arObjectManager!.addNode(newNode, planeAnchor: newAnchor);
    nodes.add(newNode);
  }

  @override
  void dispose() {
    super.dispose();
    arSessionManager?.dispose();
    _cameraController.dispose();
    imageLabeler.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Object Recognition AR')),
      body: Stack(
        children: [
          ARView(
            onARViewCreated: onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          ),
          // CameraPreview(_cameraController),
        ],
      ),
    );
  }

  void onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    this.arSessionManager = arSessionManager;
    this.arObjectManager = arObjectManager;
    this.arAnchorManager = arAnchorManager;

    this.arSessionManager!.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      customPlaneTexturePath: "images/triangle.png",
      showWorldOrigin: true,
      handlePans: true,
      handleRotation: true,
    );
    this.arObjectManager!.onInitialize();
  }
}
