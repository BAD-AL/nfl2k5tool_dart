// Translated from DataMap.cs
// ignore_for_file: non_constant_identifier_names

import 'dart:io';
import 'static_utils.dart';
import 'enf_photo_index.dart';
import 'enf_name_index.dart';

class DataMap {
  static Map<String, String>? sPhotoMap;
  static Map<String, String>? sPBPMap;

  static const String cPhotoMapPath = './PlayerData/ENFPhotoIndex.txt';
  static const String cPBPMapPath = './PlayerData/ENFNameIndex.txt';

  static void EnsureFiles() {
    if (!File(cPhotoMapPath).existsSync()) {
      if (!Directory('./PlayerData/').existsSync())
        Directory('./PlayerData/').createSync(recursive: true);
      stderr.writeln("Couldn't find 'ENFPhotoIndex.txt', using embedded file...");
      File(cPhotoMapPath).writeAsStringSync(kEnfPhotoIndexContent);
    }
    if (!File(cPBPMapPath).existsSync()) {
      if (!Directory('./PlayerData/').existsSync())
        Directory('./PlayerData/').createSync(recursive: true);
      stderr.writeln("Couldn't find 'ENFNameIndex.txt', using embedded file...");
      File(cPBPMapPath).writeAsStringSync(kEnfNameIndexContent);
    }
  }

  static Map<String, String> get PhotoMap {
    if (sPhotoMap == null) {
      EnsureFiles();
      sPhotoMap = _ReadIntoMap(cPhotoMapPath, false);
    }
    return sPhotoMap!;
  }

  static Map<String, String> get PBPMap {
    if (sPBPMap == null) {
      EnsureFiles();
      sPBPMap = _ReadIntoMap(cPBPMapPath, false);
    }
    return sPBPMap!;
  }

  /// Returns a Map of the file contents.
  /// [lookupByNumber] true to lookup by number, false to lookup by name
  static Map<String, String> _ReadIntoMap(String fileName, bool lookupByNumber) {
    Map<String, String> retVal;
    const String sep = '=';
    int key = 0;
    int value = 1;
    if (lookupByNumber) {
      key = 1;
      value = 0;
    }
    if (File(cPhotoMapPath).existsSync()) {
      List<String> contents = File(fileName).readAsLinesSync();
      retVal = {};
      for (int i = 0; i < contents.length; i++) {
        String line = contents[i];
        if (line.isNotEmpty && line[0] != ';') {
          List<String> parts = line.split(sep);
          if (parts.length >= 2 && !retVal.containsKey(parts[key])) {
            retVal[parts[key]] = parts[value];
          }
        }
      }
    } else {
      retVal = {}; // create an empty one so we don't crash
    }
    return retVal;
  }

  static Map<String, String>? sReversePhotoMap;

  static Map<String, String> get ReversePhotoMap {
    if (sReversePhotoMap == null) {
      EnsureFiles();
      sReversePhotoMap = _ReadIntoMap(cPhotoMapPath, true);
    }
    return sReversePhotoMap!;
  }

  /// Returns the player's name the number maps to.
  /// [number] the Photo number
  static String GetPlayerNameForPhoto(String number) {
    switch (number.length) {
      case 1: number = '000' + number; break;
      case 2: number = '00' + number; break;
      case 3: number = '0' + number; break;
    }
    if (ReversePhotoMap.containsKey(number))
      return ReversePhotoMap[number]!;
    return 'UNKNOWN!';
  }

  static Map<String, String>? sReversePBPMap;

  static Map<String, String> get ReversePBPMap {
    if (sReversePBPMap == null) {
      EnsureFiles();
      sReversePBPMap = _ReadIntoMap(cPBPMapPath, true);
    }
    return sReversePBPMap!;
  }

  /// Returns the player's PBP the number maps to.
  /// [number] the PBP number
  static String GetPlayerNameForPBP(String number) {
    switch (number.length) {
      case 1: number = '000' + number; break;
      case 2: number = '00' + number; break;
      case 3: number = '0' + number; break;
    }
    if (ReversePBPMap.containsKey(number))
      return ReversePBPMap[number]!;
    return 'UNKNOWN!';
  }
}
