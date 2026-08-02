import 'dart:typed_data';

final RegExp _opaqueTokenPattern = RegExp(r'^[0-9a-f]{32}$');

/// Whether [token] is the canonical wire form used by the server and BLE.
///
/// Tokens must stay lowercase: peers turn the 16 advertised bytes back into
/// lowercase hex before sending them to the server for resolution.
bool isCanonicalOpaqueToken(String token) =>
    _opaqueTokenPattern.hasMatch(token);

/// Decodes a canonical 128-bit opaque token for BLE advertising.
///
/// Rejecting the entire value prevents short tokens from throwing a RangeError
/// mid-rotation and long tokens from being silently truncated to 16 bytes.
Uint8List opaqueTokenBytes(String token) {
  if (!isCanonicalOpaqueToken(token)) {
    throw const FormatException(
      'Opaque token must be exactly 32 lowercase hexadecimal characters.',
    );
  }

  return Uint8List.fromList([
    for (var i = 0; i < token.length; i += 2)
      int.parse(token.substring(i, i + 2), radix: 16),
  ]);
}
