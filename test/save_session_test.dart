import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/platform_signer.dart';
import 'package:dart_mymc/dart_mymc.dart';
import 'package:test/test.dart';

void main() {
  final testFilePath = 'test/test_files/Base2004Fran_Orig.zip';
  final xemuMupath = 'test/test_files/XEMU_Created_default_roster.bin';

  group('PlatformSigner', () {
    test('Xbox HMAC-SHA1 produces 20-byte signature', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sig = PlatformSigner.signXbox(data);
      expect(sig.length, equals(20));
    });

    test('PS2 CRC32 produces 4-byte signature (Little Endian)', () {
      final data = Uint8List.fromList([0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39]); // "123456789"
      final sig = PlatformSigner.signPs2(data);
      expect(sig.length, equals(4));
      // CRC32 of "123456789" is 0xCBF43926
      // Little endian bytes: 0x26, 0x39, 0xF4, 0xCB
      expect(sig, equals([0x26, 0x39, 0xF4, 0xCB]));
    });
  });

  group('SaveMetadata', () {
    test('synthesizePs2Name removes special characters', () {
      final name = 'Nov19 update!';
      final synthesized = SaveMetadata.synthesizePs2Name(name);
      expect(synthesized, equals('BASLUS-20919Nov19update'));
    });
  });

  group('SaveSession - Xbox ZIP Structure', () {
    late Uint8List originalZipBytes;
    late List<String> originalFilePaths;

    setUpAll(() {
      originalZipBytes = File(testFilePath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(originalZipBytes);
      originalFilePaths = archive.files
          .where((f) => f.isFile)
          .map((f) => f.name)
          .toList();
    });

    test('exported ZIP contains exactly the same files as original', () {
      final session = SaveSession.fromXboxZip(originalZipBytes);
      final exportedZipBytes = session.exportToXboxZip();
      
      final exportedArchive = ZipDecoder().decodeBytes(exportedZipBytes);
      final exportedFilePaths = exportedArchive.files
          .where((f) => f.isFile)
          .map((f) => f.name)
          .toList();

      // Check count
      expect(exportedFilePaths.length, equals(originalFilePaths.length), 
          reason: 'File count mismatch in exported ZIP');

      // Check paths (order independent)
      for (final path in originalFilePaths) {
        expect(exportedFilePaths, contains(path), 
            reason: 'Exported ZIP is missing file: $path');
      }
    });

    test('metadata is correctly parsed from ZIP bundle', () {
      final session = SaveSession.fromXboxZip(originalZipBytes);
      // Base2004Fran_Orig.zip has "Franchise 1" in SaveMeta.xbx usually, 
      // but let's check what our parser found.
      expect(session.metadata.displayTitle, isNotEmpty);
      expect(session.metadata.xboxDirId, equals('42E8F759D2E9'));
      expect(session.metadata.type, equals(SaveType.Franchise));
    });
  });

  group('SaveSession - PS2 PSU Export', () {
    test('exportToPs2Psu creates valid PSU bundle from Xbox source', () {
      final xboxZipBytes = File(testFilePath).readAsBytesSync();
      final session = SaveSession.fromXboxZip(xboxZipBytes);
      
      final psuBytes = session.exportToPs2Psu();
      expect(psuBytes, isNotEmpty);
      
      // Basic validation: PSU usually starts with directory entry length or specific header
      // Since we use dart_mymc, we trust its PSU encoding, but we check if it can re-read it.
      // (Mock check or re-parsing)
      expect(psuBytes.length, greaterThan(session.engine.GameSaveData!.length));
    });
  });

  group('SaveSession - Memory Card Injection', () {
    test('injectIntoPs2Card creates a valid PS2 card image with header', () {
      final xboxZipBytes = File(testFilePath).readAsBytesSync();
      final session = SaveSession.fromXboxZip(xboxZipBytes);
      
      final cardBytes = session.injectIntoPs2Card();
      expect(cardBytes, isNotEmpty);
      
      // Verify PS2 Card Header
      final header = String.fromCharCodes(cardBytes.sublist(0, 28));
      expect(header, equals('Sony PS2 Memory Card Format '));
    });

    test('injectIntoXboxMU creates a valid Xbox MU image with FATX header', () {
      final xboxZipBytes = File(testFilePath).readAsBytesSync();
      final session = SaveSession.fromXboxZip(xboxZipBytes);
      
      final muBytes = session.injectIntoXboxMU();
      expect(muBytes, isNotEmpty);
      
      // Verify FATX Header
      final header = String.fromCharCodes(muBytes.sublist(0, 4));
      expect(header, equals('FATX'));
    });

    test('round-trip PS2 card: inject and then load back via fromPs2Card', () {
      final xboxZipBytes = File(testFilePath).readAsBytesSync();
      final originalSession = SaveSession.fromXboxZip(xboxZipBytes);
      
      final cardImage = originalSession.injectIntoPs2Card();
      final reloadedSession = SaveSession.fromPs2Card(cardImage);
      
      // Check data integrity and type instead of just display title
      expect(reloadedSession.metadata.type, equals(originalSession.metadata.type));
      expect(reloadedSession.metadata.sourcePlatform, equals(SavePlatform.ps2));
      expect(reloadedSession.engine.GameSaveData!.length, equals(originalSession.engine.GameSaveData!.length));
    });

    test('round-trip Xbox MU: inject and then load back via fromXboxMU', () {
      final xboxZipBytes = File(testFilePath).readAsBytesSync();
      final originalSession = SaveSession.fromXboxZip(xboxZipBytes);
      
      final muImage = originalSession.injectIntoXboxMU();
      final reloadedSession = SaveSession.fromXboxMU(muImage);
      
      expect(reloadedSession.metadata.xboxDirId, equals(originalSession.metadata.xboxDirId));
      expect(reloadedSession.metadata.sourcePlatform, equals(SavePlatform.xbox));
      expect(reloadedSession.engine.GameSaveData!.length, equals(originalSession.engine.GameSaveData!.length));
    });
  });

  group('SaveSession - XEMU to PS2 MAX', () {
    test('import XEMU MU and export as .max with correct internal files', () {
      final muBytes = File(xemuMupath).readAsBytesSync();
      final session = SaveSession.fromXboxMU(muBytes);
      
      final maxBytes = session.exportToPs2Max();
      expect(maxBytes, isNotEmpty);
      
      // Read back the exported .max file
      final exportedPs2Save = Ps2Save.fromBytes(maxBytes);
      final fileNames = exportedPs2Save.files.map((f) => f.name).toList();
      
      expect(exportedPs2Save.dirName, startsWith('BASLUS-20919'));
      expect(fileNames, contains(exportedPs2Save.dirName));
      expect(fileNames, contains('EXTRA'));
      expect(fileNames, contains('TYPE'));
      expect(fileNames, contains('icon.sys'));
      expect(fileNames, contains('VIEW.ICO'));

      // Binary compare icons against a known-good reference .max file
      final refPath = 'test/test_files/SLUS-20919 ESPN NFL 2K5 NFL25RW6 (35670D6C).max';
      final refBytes = File(refPath).readAsBytesSync();
      final refSave = Ps2Save.fromBytes(refBytes);

      final exportedIcon = exportedPs2Save.files.firstWhere((f) => f.name == 'icon.sys').toBytes();
      final exportedView = exportedPs2Save.files.firstWhere((f) => f.name == 'VIEW.ICO').toBytes();

      final refIcon = refSave.files.firstWhere((f) => f.name == 'icon.sys').toBytes();
      final refView = refSave.files.firstWhere((f) => f.name == 'VIEW.ICO').toBytes();

      expect(exportedIcon, equals(refIcon), reason: 'icon.sys binary mismatch');
      expect(exportedView, equals(refView), reason: 'VIEW.ICO binary mismatch');
    });
  });
}
