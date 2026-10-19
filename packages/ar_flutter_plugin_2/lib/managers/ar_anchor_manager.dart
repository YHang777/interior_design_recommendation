import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

typedef AnchorUploadedHandler = void Function(ARAnchor arAnchor);
typedef AnchorDownloadedHandler = ARAnchor Function(
    Map<String, dynamic> serializedAnchor);

class ARAnchorManager {
  late MethodChannel _channel;

  final bool debug;

  List<ARAnchor> pendingAnchors = [];

  AnchorUploadedHandler? onAnchorUploaded;

  AnchorDownloadedHandler? onAnchorDownloaded;

  ARAnchorManager(int id, {this.debug = false}) {
    _channel = MethodChannel('aranchors_$id');
    _channel.setMethodCallHandler(_platformCallHandler);
    if (debug) {
      print("ARAnchorManager initialized");
    }
  }

  initGoogleCloudAnchorMode() async {
    _channel.invokeMethod<bool>('initGoogleCloudAnchorMode', {});
  }

  Future<dynamic> _platformCallHandler(MethodCall call) async {
    if (debug) {
      print('_platformCallHandler call ${call.method} ${call.arguments}');
    }
    try {
      switch (call.method) {
        case 'onError':
          print(call.arguments);
          break;
        case 'onCloudAnchorUploaded':
          final name = call.arguments["name"];
          final cloudanchorid = call.arguments["cloudanchorid"];
          print(
              "UPLOADED ANCHOR WITH ID: " + cloudanchorid + ", NAME: " + name);
          final currentAnchor =
              pendingAnchors.where((element) => element.name == name).first;
          (currentAnchor as ARPlaneAnchor).cloudanchorid = cloudanchorid;
          pendingAnchors.remove(currentAnchor);
          if (onAnchorUploaded != null) {
            onAnchorUploaded!(currentAnchor);
          }
          break;
        case "onAnchorDownloadSuccess":
          final serializedAnchor = call.arguments;
          if (onAnchorDownloaded != null) {
            ARAnchor anchor = onAnchorDownloaded!(
                Map<String, dynamic>.from(serializedAnchor));
            return anchor.name;
          } else {
            return serializedAnchor["name"];
          }
        default:
          if (debug) {
            print('Unimplemented method ${call.method} ');
          }
      }
    } catch (e) {
      print('Error caught: ' + e.toString());
    }
    return Future.value();
  }

  Future<bool?> addAnchor(ARAnchor anchor) async {
    try {
      return await _channel.invokeMethod<bool>('addAnchor', anchor.toJson());
    } on PlatformException catch (e) {
      return false;
    }
  }

  removeAnchor(ARAnchor anchor) {
    _channel.invokeMethod<String>('removeAnchor', {'name': anchor.name});
  }

  Future<bool?> uploadAnchor(ARAnchor anchor) async {
    try {
      final response =
          await _channel.invokeMethod<bool>('uploadAnchor', anchor.toJson());
      pendingAnchors.add(anchor);
      return response;
    } on PlatformException catch (e) {
      return false;
    }
  }

  Future<bool?> downloadAnchor(String cloudanchorid) async {
    print("TRYING TO DOWNLOAD ANCHOR WITH ID " + cloudanchorid);
    _channel
        .invokeMethod<bool>('downloadAnchor', {"cloudanchorid": cloudanchorid});
  }
}
