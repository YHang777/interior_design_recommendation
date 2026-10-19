import 'dart:async';
import 'package:geolocator/geolocator.dart';

class ARLocationManager {
  late Position currentLocation;
  late StreamSubscription<Position> locationStream;

  Future<Position?> getLastKnownPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services disabled');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions permanently denied');
    }

    return await Geolocator.getLastKnownPosition();
  }

  Future<bool> startLocationUpdates() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services disabled');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions permanently denied');
    }

    locationStream =
        Geolocator.getPositionStream(locationSettings: LocationSettings(accuracy: LocationAccuracy.high))
            .listen((Position position) {
      currentLocation = position;
    });

    return true;
  }

  void stopLocationUpdates() {
    locationStream.cancel();
  }

  void openAppPermissionSettings() async {
    await Geolocator.openAppSettings();
  }

  void openLocationServicesSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services disabled');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions permanently denied');
    }

    return await Geolocator.getCurrentPosition();
  }
}
