// SQL Pulse — biometric auth abstraction.
// Native (desktop/mobile): real Touch ID / Face ID / fingerprint via local_auth.
// Web (mobile browser): the platform authenticator via WebAuthn (Face ID/Touch
// ID/fingerprint prompt provided by the browser/OS).
import 'biometric_native.dart' if (dart.library.html) 'biometric_web.dart' as impl;

/// True if the platform can do biometric verification.
Future<bool> biometricAvailable() => impl.biometricAvailable();

/// Prompt the device biometric. Returns true only if the user passed it.
Future<bool> biometricAuthenticate(String reason) => impl.biometricAuthenticate(reason);
