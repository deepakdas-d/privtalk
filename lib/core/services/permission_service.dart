import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestCorePermissions() async {
    final statuses = await [
      Permission.camera, 
      Permission.microphone,
      Permission.notification,
    ].request();

    // We mainly care if camera and mic are granted for calls to work,
    // but we request notifications here so the prompt appears after login.
    return statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted;
  }

  static Future<bool> hasCorePermissions() async {
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
