// ignore_for_file: non_constant_identifier_names

import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'logger.dart';

/// Static utility functions.
class StaticUtils {
  StaticUtils._(); // prevent instantiation

  static void WriteError(String err){
    Logger.error(err);
  }

  // #region Error functionality
  /// A place to keep all the processing errors.
  static List<String> Errors = [];

  /// Shows the errors (if any exist) to logger.
  static void ShowErrors() {
    if (Errors.isNotEmpty) {
      StringBuffer b = StringBuffer();
      for (String s in Errors) {
        b.write(s);
        b.write('\n');
      }
      Logger.error(b.toString());
      Errors = [];
    }
  }

  /// Add an error to the session.
  static void AddError(String error) {
    Errors.add(error);
  }
  // #endregion

  // #region Warning functionality
  /// Non-fatal warnings (value still written; caller may want to notify the user).
  static List<String> Warnings = [];

  /// Add a warning to the session.
  static void AddWarning(String warning) {
    Warnings.add(warning);
  }

  /// Shows warnings (if any) to logger, then clears the list.
  static void ShowWarnings() {
    if (Warnings.isNotEmpty) {
      final b = StringBuffer();
      for (final w in Warnings) {
        b.write(w);
        b.write('\n');
      }
      Logger.log(b.toString());
      Warnings = [];
    }
  }
  // #endregion

  /// Find string [str] (unicode / UTF-16LE string) in the data byte array.
  static List<int> FindStringInFile(String str, Uint8List data, int start, int end,
      [bool nullByte = false]) {
    int length = str.length * 2;
    if (nullByte) length += 2;

    Uint8List target = Uint8List(length); // initialized to 0
    int i = 0;
    for (int j = 0; j < str.length; j++) {
      target[i] = str.codeUnitAt(j) & 0xff;
      target[i + 1] = 0;
      i += 2;
    }
    return FindByesInFile(target, data, start, end);
  }

  static List<int> FindPointersToString(String searchString, Uint8List saveFile, int start, int end) {
    List<int> locs = StaticUtils.FindStringInFile(searchString, saveFile, 0, saveFile.length);
    List<int> retVal = [];

    for (int i = 0; i < locs.length; i++) {
      List<int> pointers = FindPointersForLocation(locs[i], saveFile);
      for (int dude in pointers) {
        if (dude > start && dude < end)
          retVal.add(dude);
      }
    }
    return retVal;
  }

  static List<int> FindPointersForLocation(int location, Uint8List saveFile) {
    List<int> pointerLocations = [];
    int limit = saveFile.length - 4;
    for (int i = 0; i < limit; i++) {
      int pointer = saveFile[i + 3] << 24;
      pointer += saveFile[i + 2] << 16;
      pointer += saveFile[i + 1] << 8;
      pointer += saveFile[i];
      // Sign-extend 32-bit to 64-bit (Dart int)
      if (pointer >= 0x80000000) pointer -= 0x100000000;
      int dataLocation = i + pointer - 1;

      if (dataLocation == location) {
        pointerLocations.add(i);
      }
    }
    return pointerLocations;
  }

  /// Find an array of bytes in the data byte array.
  static List<int> FindByesInFile(Uint8List target, Uint8List data, int start, int end) {
    List<int> retVal = [];

    if (data.isNotEmpty && data.length > 80) {
      if (start < 0) start = 0;
      if (end > data.length) end = data.length - 1;

      int num = end - target.length;
      for (int num3 = start; num3 < num; num3++) {
        if (_Check(target, num3, data)) {
          retVal.add(num3);
        }
      }
    }
    return retVal;
  }

  static bool _Check(Uint8List target, int location, Uint8List data) {
    int i;
    for (i = 0; i < target.length; i++) {
      if (target[i] != data[location + i]) {
        break;
      }
    }
    return i == target.length;
  }

  // #region Zip file handling

  /// Extract a specific file from zip data.
  /// Returns null if file was not found.
  static Uint8List? ExtractFileFromZipData(Uint8List zipData, String? password, String fileToExtract) {
    final archive = ZipDecoder().decodeBytes(zipData, password: password);
    for (final file in archive) {
      if (file.isFile && file.name.split('/').last == fileToExtract) {
        return file.content as Uint8List;
      }
    }
    return null;
  }

  /// Replace a file in zip data with new data.
  /// Returns the updated zip data.
  static Uint8List ReplaceFileInZipData(Uint8List zipData, String? password, String fileToReplace, Uint8List newFileData) {
    final archive = ZipDecoder().decodeBytes(zipData, password: password);
    final newArchive = Archive();
    
    bool replaced = false;
    for (final file in archive) {
      if (file.isFile && file.name.split('/').last == fileToReplace) {
        newArchive.addFile(ArchiveFile(file.name, newFileData.length, newFileData));
        replaced = true;
      } else {
        newArchive.addFile(file);
      }
    }

    if (!replaced) {
      newArchive.addFile(ArchiveFile(fileToReplace, newFileData.length, newFileData));
    }

    return Uint8List.fromList(ZipEncoder().encode(newArchive)!);
  }
  // #endregion

  // #region save signing
  // "722E7565FB841B09E938DA756393FF80"
  static final List<int> _mNFL2K5Key = [
    0x72, 0x2E, 0x75, 0x65, 0xFB, 0x84, 0x1B, 0x09,
    0xE9, 0x38, 0xDA, 0x75, 0x63, 0x93, 0xFF, 0x80
  ];

  /// Signs the NFL2K5 xbox save data.
  /// Returns the signature as bytes.
  static Uint8List SignNfl2K5SaveData(Uint8List dataToHash) {
    final hmac = Hmac(sha1, _mNFL2K5Key);
    final digest = hmac.convert(dataToHash);
    return Uint8List.fromList(digest.bytes);
  }
  // #endregion
}
