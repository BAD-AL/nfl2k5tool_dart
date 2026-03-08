import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:nfl2k5tool_dart/program.dart';
import 'package:nfl2k5tool_dart/save_session.dart';
import 'package:nfl2k5tool_dart/gamesave_tool.dart';
import 'package:dart_mymc/dart_mymc.dart';
import 'package:test/test.dart';

void main() {
  final xboxZipPath = 'test/test_files/Base2004Fran_Orig.zip';
  final xboxDatPath = 'test/test_files/years/BaseRoster/SAVEGAME.DAT';
  final xboxMuPath = 'test/test_files/XEMU_Created_default_roster.bin';
  final ps2MaxPath = 'test/test_files/SLUS-20919 ESPN NFL 2K5 NFL25RW6 (35670D6C).max';

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('nfl2k5_format_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String getTempPath(String name) => '${tempDir.path}/$name';

  group('CLI Format Support - Integration Tests', () {
    
    test('.dat (Xbox) -> .dat (Xbox)', () {
      final outPath = getTempPath('output.dat');
      // Create a dummy text file to trigger a modification
      final modFile = File(getTempPath('mod.txt'))..writeAsStringSync('Key=49ers,PBP:123\n');
      
      Program.RunMain([xboxDatPath, modFile.path, '-out:$outPath']);

      expect(File(outPath).existsSync(), isTrue);
      final extraFile = File('${tempDir.path}/EXTRA');
      expect(extraFile.existsSync(), isTrue);
      expect(extraFile.lengthSync(), equals(20)); // Xbox signature length
    });

    test('.zip (Xbox) -> .zip (Xbox)', () {
      final outPath = getTempPath('output.zip');
      Program.RunMain([xboxZipPath, '-out:$outPath']);

      expect(File(outPath).existsSync(), isTrue);
      final bytes = File(outPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      // Verify Xbox structure
      expect(archive.files.any((f) => f.name.contains('SAVEGAME.DAT')), isTrue);
      expect(archive.files.any((f) => f.name.contains('EXTRA')), isTrue);
    });

    test('.zip (Xbox) -> .ps2 (PS2)', () {
      final outPath = getTempPath('output.ps2');
      Program.RunMain([xboxZipPath, '-out:$outPath']);

      expect(File(outPath).existsSync(), isTrue);
      final bytes = File(outPath).readAsBytesSync();
      // PS2 Card Header check
      expect(String.fromCharCodes(bytes.sublist(0, 28)), equals('Sony PS2 Memory Card Format '));
    });

    test('.bin (Xbox MU) -> .zip (Xbox)', () {
      final outPath = getTempPath('output.zip');
      Program.RunMain([xboxMuPath, '-out:$outPath']);

      expect(File(outPath).existsSync(), isTrue);
      final bytes = File(outPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files.any((f) => f.name.contains('SAVEGAME.DAT')), isTrue);
    });

    test('.max (PS2) -> .psu (PS2)', () {
      final outPath = getTempPath('output.psu');
      Program.RunMain([ps2MaxPath, '-out:$outPath']);

      expect(File(outPath).existsSync(), isTrue);
      // PSU should be loadable by dart_mymc
      final psuBytes = File(outPath).readAsBytesSync();
      final ps2Save = Ps2Save.fromBytes(psuBytes);
      expect(ps2Save.dirName, startsWith('BASLUS-20919'));
    });

    test('.max (PS2) -> .dat (Xbox)', () {
      final outPath = getTempPath('output.dat');
      Program.RunMain([ps2MaxPath, '-out:$outPath']);

      expect(File(outPath).existsSync(), isTrue);
      final extraFile = File('${tempDir.path}/EXTRA');
      expect(extraFile.existsSync(), isTrue);
      expect(extraFile.lengthSync(), equals(20)); // Must be Xbox signed now
    });

    test('.psu (PS2) -> .max (PS2)', () {
      // First generate a PSU
      final psuPath = getTempPath('input.psu');
      final maxOutPath = getTempPath('output.max');
      Program.RunMain([ps2MaxPath, '-out:$psuPath']);
      
      // Then convert PSU to MAX
      Program.RunMain([psuPath, '-out:$maxOutPath']);

      expect(File(maxOutPath).existsSync(), isTrue);
      final maxBytes = File(maxOutPath).readAsBytesSync();
      // Verify MAX header (or at least that it's a valid Ps2Save)
      final ps2Save = Ps2Save.fromBytes(maxBytes);
      expect(ps2Save.dirName, startsWith('BASLUS-20919'));
    });

    test('.ps2 (PS2) -> .max (PS2)', () {
      // First generate a PS2 card
      final cardPath = getTempPath('input.ps2');
      final maxOutPath = getTempPath('output.max');
      Program.RunMain([ps2MaxPath, '-out:$cardPath']);
      
      // Then convert PS2 card to MAX
      Program.RunMain([cardPath, '-out:$maxOutPath']);

      expect(File(maxOutPath).existsSync(), isTrue);
      final ps2Save = Ps2Save.fromBytes(File(maxOutPath).readAsBytesSync());
      expect(ps2Save.dirName, startsWith('BASLUS-20919'));
    });

    test('.img (Xbox MU) -> .max (PS2)', () {
      // .img is handled same as .bin for Xbox MU in our logic
      final xboxImgPath = getTempPath('input.img');
      File(xboxMuPath).copySync(xboxImgPath);
      
      final maxOutPath = getTempPath('output.max');
      Program.RunMain([xboxImgPath, '-out:$maxOutPath']);

      expect(File(maxOutPath).existsSync(), isTrue);
      final ps2Save = Ps2Save.fromBytes(File(maxOutPath).readAsBytesSync());
      expect(ps2Save.dirName, startsWith('BASLUS-20919'));
    });

    test('.bin (Xbox MU) -> .ps2 (PS2)', () {
      final outPath = getTempPath('output.ps2');
      Program.RunMain([xboxMuPath, '-out:$outPath']);

      expect(File(outPath).existsSync(), isTrue);
      final bytes = File(outPath).readAsBytesSync();
      expect(String.fromCharCodes(bytes.sublist(0, 28)), equals('Sony PS2 Memory Card Format '));
    });

  });
}
