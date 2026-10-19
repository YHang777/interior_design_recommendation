import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';

typedef ARViewCreatedCallback = void Function(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager);

abstract class PlatformARView {
  factory PlatformARView(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return AndroidARView();
      case TargetPlatform.iOS:
        return IosARView();
      default:
        throw FlutterError;
    }
  }

  Widget build(
      {@required BuildContext context,
      @required ARViewCreatedCallback arViewCreatedCallback,
      @required PlaneDetectionConfig planeDetectionConfig});

  void onPlatformViewCreated(int id);
}

createManagers(
    int id,
    BuildContext? context,
    ARViewCreatedCallback? arViewCreatedCallback,
    PlaneDetectionConfig? planeDetectionConfig) {
  if (context == null ||
      arViewCreatedCallback == null ||
      planeDetectionConfig == null) {
    return;
  }
  arViewCreatedCallback(ARSessionManager(id, context, planeDetectionConfig),
      ARObjectManager(id), ARAnchorManager(id), ARLocationManager());
}

class AndroidARView implements PlatformARView {
  late BuildContext? _context;
  late ARViewCreatedCallback? _arViewCreatedCallback;
  late PlaneDetectionConfig? _planeDetectionConfig;

  @override
  void onPlatformViewCreated(int id) {
    print("Android platform view created!");
    createManagers(id, _context, _arViewCreatedCallback, _planeDetectionConfig);
  }

  @override
  Widget build(
      {BuildContext? context,
      ARViewCreatedCallback? arViewCreatedCallback,
      PlaneDetectionConfig? planeDetectionConfig}) {
    _context = context;
    _arViewCreatedCallback = arViewCreatedCallback;
    _planeDetectionConfig = planeDetectionConfig;
    final String viewType = 'ar_flutter_plugin_2';
    final Map<String, dynamic> creationParams = <String, dynamic>{};

    return AndroidView(
      viewType: viewType,
      layoutDirection: TextDirection.ltr,
      creationParams: creationParams,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: onPlatformViewCreated,
    );
  }
}

class IosARView implements PlatformARView {
  BuildContext? _context;
  ARViewCreatedCallback? _arViewCreatedCallback;
  PlaneDetectionConfig? _planeDetectionConfig;

  @override
  void onPlatformViewCreated(int id) {
    print("iOS platform view created!");
    createManagers(id, _context, _arViewCreatedCallback, _planeDetectionConfig);
  }

  @override
  Widget build(
      {BuildContext? context,
      ARViewCreatedCallback? arViewCreatedCallback,
      PlaneDetectionConfig? planeDetectionConfig}) {
    _context = context;
    _arViewCreatedCallback = arViewCreatedCallback;
    _planeDetectionConfig = planeDetectionConfig;
    final String viewType = 'ar_flutter_plugin_2';
    final Map<String, dynamic> creationParams = <String, dynamic>{};

    return UiKitView(
      viewType: viewType,
      layoutDirection: TextDirection.ltr,
      creationParams: creationParams,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: onPlatformViewCreated,
    );
  }
}

class ARView extends StatefulWidget {
  final String permissionPromptDescription;
  final String permissionPromptButtonText;
  final String permissionPromptParentalRestriction;

  final ARViewCreatedCallback onARViewCreated;

  final PlaneDetectionConfig planeDetectionConfig;

  final bool showPlatformType;

  ARView(
      {Key? key,
      required this.onARViewCreated,
      this.planeDetectionConfig = PlaneDetectionConfig.none,
      this.showPlatformType = false,
      this.permissionPromptDescription =
          "Camera permission must be given to the app for AR functions to work",
      this.permissionPromptButtonText = "Grant Permission",
      this.permissionPromptParentalRestriction =
          "Camera permission is restriced by the OS, please check parental control settings"})
      : super(key: key);
  @override
  _ARViewState createState() => _ARViewState(
      showPlatformType: this.showPlatformType,
      permissionPromptDescription: this.permissionPromptDescription,
      permissionPromptButtonText: this.permissionPromptButtonText,
      permissionPromptParentalRestriction:
          this.permissionPromptParentalRestriction);
}

class _ARViewState extends State<ARView> {
  PermissionStatus _cameraPermission = PermissionStatus.denied;
  bool showPlatformType;
  String permissionPromptDescription;
  String permissionPromptButtonText;
  String permissionPromptParentalRestriction;

  _ARViewState(
      {required this.showPlatformType,
      required this.permissionPromptDescription,
      required this.permissionPromptButtonText,
      required this.permissionPromptParentalRestriction});

  @override
  void initState() {
    super.initState();
    initCameraPermission();
  }

  initCameraPermission() async {
    requestCameraPermission();
  }

  requestCameraPermission() async {
    final cameraPermission = await Permission.camera.request();
    setState(() {
      _cameraPermission = cameraPermission;
    });
  }

  requestCameraPermissionFromSettings() async {
    final cameraPermission = await Permission.camera.request();
    if (cameraPermission == PermissionStatus.permanentlyDenied) {
      openAppSettings();
    }
    setState(() {
      _cameraPermission = cameraPermission;
    });
  }

  @override
  build(BuildContext context) {
    switch (_cameraPermission) {
      case (PermissionStatus
          .limited):
      case (PermissionStatus.granted):
        {
          return Column(children: [
            if (showPlatformType) Text(Theme.of(context).platform.toString()),
            Expanded(
                child: PlatformARView(Theme.of(context).platform).build(
                    context: context,
                    arViewCreatedCallback: widget.onARViewCreated,
                    planeDetectionConfig: widget.planeDetectionConfig)),
          ]);
        }
      case (PermissionStatus.denied):
        {
          return Center(
              child: Column(
            children: [
              Text(permissionPromptDescription),
              ElevatedButton(
                  child: Text(permissionPromptButtonText),
                  onPressed: () async => {await requestCameraPermission()})
            ],
          ));
        }
      case (PermissionStatus
          .permanentlyDenied):
        {
          return Center(
              child: Column(
            children: [
              Text(permissionPromptDescription),
              ElevatedButton(
                  child: Text(permissionPromptButtonText),
                  onPressed: () async =>
                      {await requestCameraPermissionFromSettings()})
            ],
          ));
        }
      case (PermissionStatus.restricted):
        {
          return Center(child: Text(permissionPromptParentalRestriction));
        }
      default:
        return Text('something went wrong');
    }
  }
}
