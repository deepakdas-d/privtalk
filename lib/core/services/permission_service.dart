import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestCameraAndMic() async {
    final statuses = await [Permission.camera, Permission.microphone].request();

    return statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted;
  }

  static Future<bool> hasCameraAndMicPermission() async {
    final camera = await Permission.camera.status;
    final mic = await Permission.microphone.status;

    return camera.isGranted && mic.isGranted;
  }

  static Future<bool> isPermanentlyDenied() async {
    final camera = await Permission.camera.status;
    final mic = await Permission.microphone.status;

    return camera.isPermanentlyDenied || mic.isPermanentlyDenied;
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
