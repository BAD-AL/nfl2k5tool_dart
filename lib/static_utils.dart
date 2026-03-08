// Translated from StaticUtils.cs
// Uses package:archive for zip operations and package:crypto for HMAC-SHA1
// ignore_for_file: non_constant_identifier_names

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

/// Static utility functions.
class StaticUtils {
  StaticUtils._(); // prevent instantiation

  static void WriteError(String err){
    stderr.writeln(err);
  }

  // #region Error functionality
  /// A place to keep all the processing errors.
  static List<String> Errors = [];

  /// Shows the errors (if any exist) to stderr.
  static void ShowErrors() {
    if (Errors.isNotEmpty) {
      StringBuffer b = StringBuffer();
      for (String s in Errors) {
        b.write(s);
        b.write('\n');
      }
      stderr.writeln(b.toString());
      Errors = [];
    }
  }

  /// Add an error to the session.
  static void AddError(String error) {
    Errors.add(error);
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

  /// Extracts all files from a zip to the specified output folder.
  static void ExtractZipFile(String archiveFilenameIn, String? password, String outFolder) {
    final bytes = File(archiveFilenameIn).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes, password: password);
    for (final file in archive) {
      if (!file.isFile) continue;
      final outPath = '$outFolder/${file.name}';
      final dir = File(outPath).parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(outPath).writeAsBytesSync(file.content as List<int>);
    }
  }

  static String _UnzipToTempFolder(String archiveFilenameIn, String? password) {
    String dirName = '${Directory.systemTemp.path}/NFL2K5ToolTmpZipUnpack';
    final dir = Directory(dirName);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    ExtractZipFile(archiveFilenameIn, password, dirName);
    return dirName;
  }

  /// Extract a specific file from a zip file.
  /// Returns null if file was not found.
  static Uint8List? ExtractFileFromZip(String archiveFilenameIn, String? password, String fileToExtract) {
    Uint8List? retVal;
    String dirName = _UnzipToTempFolder(archiveFilenameIn, password);
    // Search recursively for the file
    final dir = Directory(dirName);
    if (dir.existsSync()) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.split('/').last == fileToExtract) {
          retVal = entity.readAsBytesSync();
          break;
        }
      }
      dir.deleteSync(recursive: true);
    }
    return retVal;
  }

  static void ReplaceFileInArchive(String archiveFilenameIn, String? password, String fileToReplace, String newFilePath) {
    String dirName = _UnzipToTempFolder(archiveFilenameIn, password);
    // Find and replace the file
    final dir = Directory(dirName);
    if (dir.existsSync()) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.split('/').last == fileToReplace) {
          File(newFilePath).copySync(entity.path);
          break;
        }
      }
    }

    // Repack the directory into a zip
    String outPathname = '${Directory.systemTemp.path}/nfl2k5tool_tmp_${DateTime.now().millisecondsSinceEpoch}.zip';
    final encoder = ZipFileEncoder();
    encoder.create(outPathname);
    _CompressFolder(dir, encoder, dirName.length + 1);
    encoder.close();

    File(outPathname).copySync(archiveFilenameIn);
    File(outPathname).deleteSync();
    dir.deleteSync(recursive: true);
  }

  static void _CompressFolder(Directory dir, ZipFileEncoder zipEncoder, int folderOffset) {
    for (final entity in dir.listSync()) {
      if (entity is File) {
        final entryName = entity.path.substring(folderOffset).replaceAll('\\', '/');
        zipEncoder.addFile(entity, entryName);
      } else if (entity is Directory) {
        _CompressFolder(entity, zipEncoder, folderOffset);
      }
    }
  }
  // #endregion

  // #region save signing
  // "722E7565FB841B09E938DA756393FF80"
  static final List<int> _mNFL2K5Key = [
    0x72, 0x2E, 0x75, 0x65, 0xFB, 0x84, 0x1B, 0x09,
    0xE9, 0x38, 0xDA, 0x75, 0x63, 0x93, 0xFF, 0x80
  ];

  /// Signs the NFL2K5 xbox save file.
  /// The EXTRA file is signed/hashed with the SAVEGAME.DAT data and the 2K5 key.
  static void SignNfl2K5SaveForXbox(String fileToSign, Uint8List dataToHash) {
    _SignFile(_mNFL2K5Key, fileToSign, dataToHash);
  }

  static void _SignFile(List<int> key, String fileToSign, Uint8List dataToHash) {
    try {
      final hmac = Hmac(sha1, key);
      final digest = hmac.convert(dataToHash);
      File(fileToSign).writeAsBytesSync(Uint8List.fromList(digest.bytes));
    } catch (e) {
      Errors.add('Error signing file! $fileToSign');
    }
  }
  // #endregion
}
