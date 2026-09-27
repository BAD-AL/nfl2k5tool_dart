import 'dart:io';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/gamesave_tool_io.dart';
import 'package:test/test.dart';

String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

const String _franchise = 'Base2004Fran_Orig.zip';
const String _roster = 'BaseRoster/SAVEGAME.DAT';
const String _knownBad = 'NFL27Fra.zip';

void main() {
  group('T-SFH-1 Clean files report no issues', () {
    test('stock franchise file is healthy', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final health = checkSaveFileHealth(tool);
      expect(health.hasAnyIssue, isFalse);
      expect(health.playerNamesOverBy, equals(0));
      expect(health.coachStringsOverBy, equals(0));
      expect(health.sharedNamePointers, isFalse);
    });

    test('stock roster file is healthy', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      final health = checkSaveFileHealth(tool);
      expect(health.hasAnyIssue, isFalse);
      expect(health.playerNamesOverBy, equals(0));
      expect(health.coachStringsOverBy, equals(0));
      expect(health.sharedNamePointers, isFalse);
    });
  });

  group('T-SFH-2 A known-bad file reports its real issues', () {
    test('NFL27Fra.zip shows a player-names overflow and shared pointers', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_knownBad));
      final health = checkSaveFileHealth(tool);
      expect(health.hasAnyIssue, isTrue);
      expect(health.playerNamesOverBy, greaterThan(0));
      expect(health.sharedNamePointers, isTrue);
    });
  });
}
