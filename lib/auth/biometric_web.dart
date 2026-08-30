// SQL Pulse — web biometric via WebAuthn platform authenticator.
// Calls the JS bridge (window.spBio) defined in web/index.html, which uses
// navigator.credentials to trigger the device Face ID / Touch ID / fingerprint.
import 'dart:js_interop';

@JS('spBio.available')
external JSPromise<JSBoolean> _available();

@JS('spBio.authenticate')
external JSPromise<JSBoolean> _authenticate(JSString reason);

Future<bool> biometricAvailable() async {
  try {
    final r = await _available().toDart;
    return r.toDart;
  } catch (_) {
    return false;
  }
}

Future<bool> biometricAuthenticate(String reason) async {
  try {
    final r = await _authenticate(reason.toJS).toDart;
    return r.toDart;
  } catch (_) {
    return false;
  }
}
