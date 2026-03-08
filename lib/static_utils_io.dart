// ignore_for_file: non_constant_identifier_names

import 'dart:io';
import 'dart:typed_data';
import 'static_utils.dart';

/// dart:io specific extensions for StaticUtils
extension StaticUtilsIo on StaticUtils {
  /// Extract a specific file from a zip file.
  static Uint8List? extractFileFromZip(String archiveFilenameIn, String? password, String fileToExtract) {
    if (!File(archiveFilenameIn).existsSync()) return null;
    final bytes = File(archiveFilenameIn).readAsBytesSync();
    return StaticUtils.ExtractFileFromZipData(bytes, password, fileToExtract);
  }

  /// Replace a file in a zip archive with new data.
  static void replaceFileInArchive(String archiveFilenameIn, String? password, String fileToReplace, String newFilePath) {
    if (!File(archiveFilenameIn).existsSync()) return;
    final zipData = File(archiveFilenameIn).readAsBytesSync();
    final newFileData = File(newFilePath).readAsBytesSync();
    
    final updatedZipData = StaticUtils.ReplaceFileInZipData(zipData, password, fileToReplace, newFileData);
    File(archiveFilenameIn).writeAsBytesSync(updatedZipData);
  }

  /// Signs the NFL2K5 xbox save file.
  static void signNfl2K5SaveForXbox(String fileToSign, Uint8List dataToHash) {
    final signature = StaticUtils.SignNfl2K5SaveData(dataToHash);
    File(fileToSign).writeAsBytesSync(signature);
  }
}
