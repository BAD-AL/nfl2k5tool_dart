// ignore_for_file: non_constant_identifier_names

import 'dart:io';
import 'dart:typed_data';
import 'gamesave_tool.dart';
import 'static_utils.dart';
import 'static_utils_io.dart';
import 'logger.dart';

/// dart:io specific extensions for GamesaveTool
extension GamesaveToolIo on GamesaveTool {
  bool LoadSaveFile(String fileName) {
    bool retVal = false;
    File f = File(fileName);
    if (f.existsSync()) {
      Uint8List? data;
      if (fileName.toLowerCase().endsWith('.dat')) {
        mZipFile = '';
        data = f.readAsBytesSync();
      } else if (fileName.toLowerCase().endsWith('.zip')) {
        data = StaticUtilsIo.extractFileFromZip(fileName, null, 'SAVEGAME.DAT');
        mZipFile = fileName;
      } else {
        return false;
      }
      if (data != null) {
        loadSaveData(data);
        retVal = true;
      }
    }
    return retVal;
  }

  void SaveFile(String fileName) {
    File f = File(fileName);
    bool isReadOnly = false;
    if (f.existsSync()) {
      try {
        RandomAccessFile raf = f.openSync(mode: FileMode.append);
        raf.closeSync();
      } catch (e) {
        isReadOnly = true;
      }
    }
    if (isReadOnly) {
      StaticUtils.AddError("File: '$fileName' is Read only");
    } else if (fileName.toLowerCase().endsWith('.dat')) {
      if (f.existsSync()) {
        f.deleteSync();
      }
      f.writeAsBytesSync(GameSaveData!);
      String extraFile = "${f.parent.path}/EXTRA";
      final signature = StaticUtils.SignNfl2K5SaveData(GameSaveData!);
      File(extraFile).writeAsBytesSync(signature);
      Logger.log('# Data successfully written to file: $fileName.');
    } else if (fileName.toLowerCase().endsWith('.zip')) {
      Uint8List zipData;
      if (mZipFile.isNotEmpty && File(mZipFile).existsSync()) {
        zipData = File(mZipFile).readAsBytesSync();
      } else if (f.existsSync()) {
        zipData = f.readAsBytesSync();
      } else {
        StaticUtils.AddError('Error! Original zip file not found.');
        return;
      }

      // Replace SAVEGAME.DAT
      zipData = StaticUtils.ReplaceFileInZipData(zipData, null, 'SAVEGAME.DAT', GameSaveData!);
      
      // Sign and replace EXTRA
      final signature = StaticUtils.SignNfl2K5SaveData(GameSaveData!);
      zipData = StaticUtils.ReplaceFileInZipData(zipData, null, 'EXTRA', signature);
      
      f.writeAsBytesSync(zipData);
      Logger.log('# Data successfully written to file: $fileName.');
    } else {
      StaticUtils.AddError('Error! Unsupported file extension: "$fileName". Use .dat or .zip for raw Xbox saves, or ensure you are using a full SaveSession for PS2/MU formats.');
    }
  }
}
