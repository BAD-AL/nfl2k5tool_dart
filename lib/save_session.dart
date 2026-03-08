// ignore_for_file: non_constant_identifier_names

import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:dart_mymc/dart_mymc.dart';
import 'package:xbox_memory_unit_tool/xbox_memory_unit_tool.dart';

import 'gamesave_tool.dart';
import 'save_metadata.dart';
import 'platform_signer.dart';
import 'static_utils.dart';
import 'enum_definitions.dart';
import 'ps2_save_templates.dart';

/// A high-level session representing an open save bundle (Xbox or PS2).
class SaveSession {
  final GamesaveTool engine;
  final SaveMetadata metadata;
  
  /// Files from the original bundle that aren't modified (icons, etc).
  final Map<String, Uint8List> passthroughFiles = {};

  SaveSession(this.engine, this.metadata);

  // #region Factory methods (Memory-Safe)
  
  /// Creates a session from a Map of filename -> bytes (e.g. from an unzipped Xbox bundle).
  static SaveSession fromBundle(Map<String, Uint8List> bundle, {SavePlatform source = SavePlatform.unknown}) {
    Uint8List? mainData;
    final metadata = SaveMetadata(sourcePlatform: source);
    final engine = GamesaveTool();
    final session = SaveSession(engine, metadata);

    // 1. Identify files
    for (final entry in bundle.entries) {
      final fileName = entry.key.split('/').last.toUpperCase();
      if (fileName == 'SAVEGAME.DAT' || fileName.startsWith('BASLUS-20919')) {
        mainData = entry.value;
      } else if (fileName == 'SAVEMETA.XBX') {
        final content = String.fromCharCodes(entry.value);
        final match = RegExp(r'Name=(.*)').firstMatch(content);
        if (match != null) metadata.displayTitle = match.group(1)!.trim();
        session.passthroughFiles[entry.key] = entry.value;
      } else if (fileName == 'TYPE') {
        final content = String.fromCharCodes(entry.value);
        if (content.contains('FXG')) metadata.type = SaveType.Franchise;
        else if (content.contains('ROS')) metadata.type = SaveType.Roster;
        session.passthroughFiles[entry.key] = entry.value;
      } else {
        session.passthroughFiles[entry.key] = entry.value;
      }
    }

    // 2. Identify directory ID from path if possible
    for (final key in bundle.keys) {
      final parts = key.split('/');
      if (parts.length >= 2) {
        final possibleId = parts[parts.length - 2];
        if (RegExp(r'^[0-9A-F]{12}$').hasMatch(possibleId.toUpperCase())) {
          metadata.xboxDirId = possibleId.toUpperCase();
          break;
        }
      }
    }

    if (mainData == null) {
      throw Exception('Missing SAVEGAME.DAT in bundle.');
    }

    engine.loadSaveData(mainData);
    return session;
  }

  /// Creates a session from a raw Xbox SAVEGAME.DAT.
  static SaveSession fromRawDat(Uint8List datBytes) {
    final engine = GamesaveTool();
    engine.loadSaveData(datBytes);
    final metadata = SaveMetadata(sourcePlatform: SavePlatform.xbox);
    return SaveSession(engine, metadata);
  }

  /// Opens an Xbox ZIP bundle.
  static SaveSession fromXboxZip(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final bundle = <String, Uint8List>{};
    for (final file in archive) {
      if (file.isFile) {
        bundle[file.name] = file.content as Uint8List;
      }
    }
    return fromBundle(bundle, source: SavePlatform.xbox);
  }

  /// Opens a PS2 save (MAX or PSU).
  static SaveSession fromPs2Save(Uint8List saveBytes) {
    final ps2Save = Ps2Save.fromBytes(saveBytes);
    final bundle = <String, Uint8List>{};
    for (final file in ps2Save.files) {
      bundle[file.name] = file.toBytes();
    }
    
    final session = fromBundle(bundle, source: SavePlatform.ps2);
    session.metadata.displayTitle = ps2Save.title;
    session.metadata.ps2DirName = ps2Save.dirName;
    return session;
  }

  /// Finds and opens the first NFL2K5 save on a PS2 memory card image.
  static SaveSession fromPs2Card(Uint8List cardImage) {
    final card = Ps2Card.openMemory(cardImage);
    final saves = card.listSaves();
    
    // Look for NFL2K5 directory prefix
    final nflSave = saves.where((s) => s.dirName.startsWith('BASLUS-20919')).toList();
    if (nflSave.isEmpty) {
      throw Exception('No NFL2K5 save found on PS2 card.');
    }

    final psuBytes = card.exportSave(nflSave.first.dirName);
    return fromPs2Save(psuBytes);
  }

  /// Finds and opens the first NFL2K5 save on an Xbox MU image.
  static SaveSession fromXboxMU(Uint8List muImage) {
    final mu = XboxMemoryUnit.fromBytes(muImage);
    
    // Look for NFL2K5 Title ID via the id property (directory name)
    final titles = mu.titles.where((t) => t.id == '53450030').toList();
    if (titles.isEmpty || titles.first.saves.isEmpty) {
      throw Exception('No NFL2K5 save found on Xbox MU.');
    }

    // exportZip() returns a ZIP buffer representing the save bundle
    final zipBytes = titles.first.saves.first.exportZip();
    return fromXboxZip(zipBytes);
  }

  // #endregion

  // #region Export methods (Memory-Safe)

  /// Exports the session to a raw Xbox ZIP.
  Uint8List exportToXboxZip() {
    final archive = Archive();
    final hexId = metadata.xboxDirId;
    final saveSubfolder = 'UDATA/53450030/$hexId';

    // Track which files we've handled to avoid duplicates and ensure we replace the right ones
    final handledFiles = <String>{};

    // 1. Add modified SAVEGAME.DAT
    final data = engine.GameSaveData!;
    final datPath = '$saveSubfolder/SAVEGAME.DAT';
    archive.addFile(ArchiveFile(datPath, data.length, data));
    handledFiles.add(datPath.toUpperCase());

    // 2. Add signed EXTRA
    final extra = PlatformSigner.signXbox(data);
    final extraPath = '$saveSubfolder/EXTRA';
    archive.addFile(ArchiveFile(extraPath, extra.length, extra));
    handledFiles.add(extraPath.toUpperCase());

    // 3. Add passthrough files, maintaining their original structure
    // But we need to handle the case where the user changed the directory ID
    for (final entry in passthroughFiles.entries) {
      String path = entry.key;
      final upperPath = path.toUpperCase();
      
      // Skip the ones we manually added
      if (handledFiles.contains(upperPath)) continue;

      // If the file was in the OLD save subfolder, move it to the NEW one
      // (This handles directory ID changes)
      final parts = path.split('/');
      if (parts.length >= 2) {
        final possibleOldId = parts[parts.length - 2];
        if (RegExp(r'^[0-9A-F]{12}$').hasMatch(possibleOldId.toUpperCase())) {
          // Replace the old hex ID with the new one if it's different
          if (possibleOldId.toUpperCase() != hexId.toUpperCase()) {
            parts[parts.length - 2] = hexId;
            path = parts.join('/');
          }
        }
      }

      final content = entry.value;
      archive.addFile(ArchiveFile(path, content.length, content));
    }

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  /// Exports the session to a PS2 PSU save.
  Uint8List exportToPs2Psu() {
    return _exportToPs2(Ps2SaveFormat.psu);
  }

  /// Exports the session to a PS2 MAX save.
  Uint8List exportToPs2Max() {
    return _exportToPs2(Ps2SaveFormat.max);
  }

  Uint8List _exportToPs2(Ps2SaveFormat format) {
    final data = engine.GameSaveData!;
    final extra = PlatformSigner.signPs2(data);
    
    // Ensure PS2 specific name for the directory AND the main file
    final dirName = metadata.ps2DirName.startsWith('BASLUS-20919') 
        ? metadata.ps2DirName 
        : SaveMetadata.synthesizePs2Name(metadata.displayTitle);

    final fileMap = <String, Uint8List>{};
    fileMap[dirName] = data; // PS2 main file is named same as directory
    fileMap['EXTRA'] = extra;

    // Add other files from passthrough
    for (final entry in passthroughFiles.entries) {
      final name = entry.key.split('/').last;
      // Skip the ones we manually handled or Xbox-specific ones
      if (name == 'SAVEGAME.DAT' || name == 'EXTRA' || name == 'SAVEMETA.XBX' || name == dirName) continue;
      fileMap[name] = entry.value;
    }

    // Ensure icon.sys, TYPE, and VIEW.ICO are present (Minimal Synthesis)
    if (!fileMap.containsKey('TYPE')) {
      final type = metadata.type == SaveType.Franchise ? 'FXG\x00' : 'ROS\x00';
      fileMap['TYPE'] = Uint8List.fromList([
        type.codeUnitAt(0), 0,
        type.codeUnitAt(1), 0,
        type.codeUnitAt(2), 0,
        0, 0,
      ]);
    }

    if (!fileMap.containsKey('icon.sys')) {
      fileMap['icon.sys'] = Ps2SaveTemplates.iconSys;
    }

    if (!fileMap.containsKey('VIEW.ICO')) {
      fileMap['VIEW.ICO'] = Ps2SaveTemplates.viewIco;
    }

    final ps2Save = Ps2Save.fromFiles(dirName, fileMap);
    return ps2Save.toBytes(format: format);
  }

  /// Injects this save into a PS2 memory card image.
  Uint8List injectIntoPs2Card() {
    final card = Ps2Card.format();
    final psu = exportToPs2Psu();
    card.importSave(psu, overwrite: true);
    return card.toBytes();
  }

  /// Injects this save into an Xbox Memory Unit image.
  Uint8List injectIntoXboxMU() {
    final mu = XboxMemoryUnit.format();
    final zip = exportToXboxZip();
    mu.importZip(zip);
    return mu.bytes;
  }

  // #endregion
}
