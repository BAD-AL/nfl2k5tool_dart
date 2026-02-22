import 'dart:io';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:test/test.dart';

/// Path to test data files, relative to the repo root.
String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

void main() {
  group('GamesaveTool – Base2004Fran_Orig.zip (franchise)', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      final ok = tool.LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
      expect(ok, isTrue, reason: 'LoadSaveFile should return true for a valid zip');
    });

    test('save type is Franchise', () {
      expect(tool.saveType, equals(SaveType.Franchise));
    });

    test('GameSaveData is not null and non-empty', () {
      expect(tool.GameSaveData, isNotNull);
      expect(tool.GameSaveData!.isNotEmpty, isTrue);
    });

    test('GetLeaguePlayers output matches expected file', () {
      final key = tool.GetKey(true, true);
      final players = tool.GetLeaguePlayers(true, true, false);
      final schedule = tool.GetSchedule();
      final actual = key + players + schedule;

      final expectedFile =
          File(testFile('Base2004Fran_Orig.output.ab.app.sch.txt'));
      final expected = expectedFile.readAsStringSync();

      expect(actual, equals(expected));
    });

    test('GetLeaguePlayers starts with header line', () {
      final key = tool.GetKey(true, true);
      expect(key, startsWith('#Position,'));
    });

    test('GetLeaguePlayers contains 49ers team block', () {
      final players = tool.GetLeaguePlayers(true, true, false);
      expect(players, contains('Team = 49ers'));
    });

    test('49ers have 53 players', () {
      final players = tool.GetLeaguePlayers(true, true, false);
      expect(players, contains('Team = 49ers    Players:53'));
    });

    test('GetNumPlayers returns correct count for 49ers', () {
      expect(tool.GetNumPlayers('49ers'), equals(53));
    });

    test('GetTeamIndex returns valid index for known teams', () {
      expect(tool.GetTeamIndex('49ers'), equals(0));
      expect(tool.GetTeamIndex('Bears'), equals(1));
    });

    test('GetSchedule returns non-empty string for franchise', () {
      final schedule = tool.GetSchedule();
      expect(schedule, isNotEmpty);
    });
  });

  group('GamesaveTool – Week_6_2024.zip (roster)', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      final ok = tool.LoadSaveFile(testFile('Week_6_2024.zip'));
      expect(ok, isTrue, reason: 'LoadSaveFile should return true for a valid zip');
    });

    test('save type is Roster', () {
      expect(tool.saveType, equals(SaveType.Roster));
    });

    test('GameSaveData is not null and non-empty', () {
      expect(tool.GameSaveData, isNotNull);
      expect(tool.GameSaveData!.isNotEmpty, isTrue);
    });

    test('GetLeaguePlayers + GetCoachDataAll output matches expected file', () {
      final key = tool.GetKey(true, true);
      final players = tool.GetLeaguePlayers(true, true, false);
      final coaches = tool.GetCoachDataAll();
      final actual = key + players + coaches;

      final expectedFile =
          File(testFile('Week_6_2024.ab.app.coach.txt'));
      final expected = expectedFile.readAsStringSync();

      expect(actual, equals(expected));
    });

    test('GetLeaguePlayers contains 49ers team block', () {
      final players = tool.GetLeaguePlayers(true, true, false);
      expect(players, contains('Team = 49ers'));
    });

    test('49ers have 53 players', () {
      final players = tool.GetLeaguePlayers(true, true, false);
      expect(players, contains('Team = 49ers    Players:53'));
    });

    test('Brock Purdy is QB on 49ers', () {
      final players = tool.GetTeamPlayers('49ers', true, true, false);
      expect(players, contains('QB,Brock,Purdy'));
    });

    test('GetCoachDataAll returns non-empty string', () {
      final coaches = tool.GetCoachDataAll();
      expect(coaches, isNotEmpty);
    });
  });

  group('GamesaveTool – LoadSaveFile error handling', () {
    test('returns false for non-existent file', () {
      final tool = GamesaveTool();
      expect(tool.LoadSaveFile('no_such_file.zip'), isFalse);
    });
  });

  group('GamesaveTool – GetTeamPlayers', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile('Week_6_2024.zip'));
    });

    test('FreeAgents section is returned', () {
      final fa = tool.GetTeamPlayers('FreeAgents', true, true, false);
      expect(fa, contains('Team = FreeAgents'));
    });

    test('DraftClass section is returned', () {
      final dc = tool.GetTeamPlayers('DraftClass', true, true, false);
      expect(dc, isNotEmpty);
    });
  });
}
