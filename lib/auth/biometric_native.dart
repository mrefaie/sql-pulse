// SQL Pulse — native biometric via local_auth (Touch ID / Face ID / fingerprint).
import 'package:local_auth/local_auth.dart';

Future<bool> biometricAvailable() async {
  try {
    final auth = LocalAuthentication();
    return await auth.isDeviceSupported() && await auth.canCheckBiometrics;
  } catch (_) {
    return false;
  }
}

Future<bool> biometricAuthenticate(String reason) async {
  try {
    final auth = LocalAuthentication();
    return await auth.authenticate(localizedReason: reason, biometricOnly: false);
  } catch (_) {
    return false;
  }
}
