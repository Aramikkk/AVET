import 'package:flutter/services.dart';

/// A line for the diagnostic log (Android/data/app.avet/files/diag.log): what happens in the app, for reading after a
/// long run. Fire and forget; never throws. No addresses, keys or contents.
void diag(String text) {
  try {
    const MethodChannel(
      'avet/vpn',
    ).invokeMethod<void>('diag', {'text': text}).catchError((_) {});
  } catch (_) {}
}
