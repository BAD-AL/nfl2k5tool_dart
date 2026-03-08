// ignore_for_file: non_constant_identifier_names

import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Handles platform-specific signing/hashing for Xbox and PS2 saves.
class PlatformSigner {
  PlatformSigner._();

  // #region Xbox (HMAC-SHA1)
  static final List<int> _mXboxKey = [
    0x72, 0x2E, 0x75, 0x65, 0xFB, 0x84, 0x1B, 0x09,
    0xE9, 0x38, 0xDA, 0x75, 0x63, 0x93, 0xFF, 0x80
  ];

  /// Signs Xbox save data using HMAC-SHA1.
  static Uint8List signXbox(Uint8List data) {
    final hmac = Hmac(sha1, _mXboxKey);
    final digest = hmac.convert(data);
    return Uint8List.fromList(digest.bytes);
  }
  // #endregion

  // #region PS2 (CRC32)
  static final Uint32List _crc32Table = _buildCrc32Table();

  static Uint32List _buildCrc32Table() {
    final table = Uint32List(256);
    for (int i = 0; i < 256; i++) {
      int entry = i;
      for (int j = 0; j < 8; j++) {
        if ((entry & 1) == 1) {
          entry = (entry >>> 1) ^ 0xEDB88320;
        } else {
          entry = entry >>> 1;
        }
      }
      table[i] = entry;
    }
    return table;
  }

  /// Signs PS2 save data using CRC32.
  static Uint8List signPs2(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (final b in data) {
      crc = (crc >>> 8) ^ _crc32Table[(crc ^ b) & 0xFF];
    }
    crc = crc ^ 0xFFFFFFFF;
    
    // Return as 4-byte little-endian array
    final result = ByteData(4);
    result.setUint32(0, crc, Endian.little);
    return result.buffer.asUint8List();
  }
  // #endregion
}
