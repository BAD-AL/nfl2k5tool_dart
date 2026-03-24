import 'dart:io';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/gamesave_tool_io.dart';
import 'package:nfl2k5tool_dart/program.dart';
import 'package:test/test.dart';

/// Runs [Program.RunMain] with [args], captures Logger output, and returns it.
String runCapture(List<String> args) {
  final buf = StringBuffer();
  final prev = Logger.logHandler;
  Logger.logHandler = buf.write;
  try {
    Program.RunMain(args);
  } finally {
    Logger.logHandler = prev;
  }
  return buf.toString();
}

String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

const String _baseRoster = 'years/BaseRoster/SAVEGAME.DAT';

// Roster-mode team-block base addresses (m49ersPlayerPointersStart = 0x41C8,
// _cTeamDiff = 0x1F4):
//   team 0 block = 0x41C8
//   +0x118 (stadium byte)          = 0x42E0
//   +0x154 (stadium byte duplicate) = 0x431C
const int _team0StadiumByte1 = 0x42E0;
const int _team0StadiumByte2 = 0x431C;

void main() {
  group('T-S15–T-S23: Team data and stadium operations (roster save)', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      final ok = tool.LoadSaveFile(testFile(_baseRoster));
      expect(ok, isTrue, reason: 'BaseRoster SAVEGAME.DAT must load');
    });

    // T-S15 — GetTeamString reads correct S3a data for all 32 teams
    test('T-S15 GetTeamString returns correct Nickname/Abbrev/City/AbbrAlt', () {
      // 49ers
      expect(tool.GetTeamString(0, TeamDataOffsets.Nickname), equals('49ers'));
      expect(tool.GetTeamString(0, TeamDataOffsets.Abbrev),   equals('SF'));
      expect(tool.GetTeamString(0, TeamDataOffsets.City),     equals('San Francisco'));
      expect(tool.GetTeamString(0, TeamDataOffsets.AbbrAlt),  equals('SF'));
      // Bears
      expect(tool.GetTeamString(1, TeamDataOffsets.Nickname), equals('Bears'));
      expect(tool.GetTeamString(1, TeamDataOffsets.City),     equals('Chicago'));
      // All 32 teams return non-empty, non-error values
      for (int i = 0; i < 32; i++) {
        for (final attr in [
          TeamDataOffsets.Nickname,
          TeamDataOffsets.Abbrev,
          TeamDataOffsets.City,
          TeamDataOffsets.AbbrAlt,
        ]) {
          final v = tool.GetTeamString(i, attr);
          expect(v, isNotEmpty,
              reason: 'Team $i ${attr.name} should not be empty');
          expect(v, isNot(equals('!!!!Invalid!!!!')),
              reason: 'Team $i ${attr.name} returned invalid sentinel');
        }
      }
    });

    // T-S16 — GetStadiumName / GetStadiumNameByIndex correct for all 32 teams
    test('T-S16 GetStadiumName and GetStadiumNameByIndex return correct names', () {
      // 49ers → index 25 → "San Francisco Park"
      expect(tool.GetStadiumName(0), equals('San Francisco Park'));
      // Bears → index 5 → "Chicago Field"
      expect(tool.GetStadiumName(1), equals('Chicago Field'));
      // Direct index lookups
      expect(tool.GetStadiumNameByIndex(25), equals('San Francisco Park'));
      expect(tool.GetStadiumNameByIndex(0),  equals('Arizona Stadium'));
      // Stadium via GetTeamString delegates to GetStadiumName
      expect(tool.GetTeamString(0, TeamDataOffsets.Stadium),
          equals('San Francisco Park'));
      // No team returns error sentinel
      for (int i = 0; i < 32; i++) {
        expect(tool.GetStadiumName(i), isNot(equals('!!!!Invalid!!!!')),
            reason: 'Team $i stadium name should be valid');
      }
    });

    // T-S17 — SetTeamString same-length Nickname round-trip, save → reload
    test('T-S17 SetTeamString same-length Nickname persists through save/reload',
        () async {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile(_baseRoster));

      fresh.SetTeamString(0, TeamDataOffsets.Nickname, 'SF49s');
      expect(fresh.GetTeamString(0, TeamDataOffsets.Nickname), equals('SF49s'));
      expect(fresh.GetTeamString(1, TeamDataOffsets.Nickname), equals('Bears'),
          reason: 'Team 1 should be unaffected');

      final tempPath =
          '${Directory.systemTemp.path}/nfl2k5_team_ts17.dat';
      fresh.SaveFile(tempPath);

      final reloaded = GamesaveTool();
      reloaded.LoadSaveFile(tempPath);
      expect(reloaded.GetTeamString(0, TeamDataOffsets.Nickname), equals('SF49s'));
      expect(reloaded.GetTeamString(1, TeamDataOffsets.Nickname), equals('Bears'));

      File(tempPath).deleteSync();
    });

    // T-S18 — SetStadiumIndex updates byte, duplicate, and S3a text; save → reload
    test('T-S18 SetStadiumIndex writes both bytes and GetStadiumName reflects change',
        () async {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile(_baseRoster));

      fresh.SetStadiumIndex(0, 5); // 5 → Chicago Field
      expect(fresh.GetStadiumName(0), equals('Chicago Field'));
      // Lookup table should be unaffected
      expect(fresh.GetStadiumNameByIndex(5), equals('Chicago Field'));
      // Both raw bytes updated
      expect(fresh.GameSaveData![_team0StadiumByte1], equals(5),
          reason: 'Primary stadium byte at +0x118 should be 5');
      expect(fresh.GameSaveData![_team0StadiumByte2], equals(5),
          reason: 'Duplicate stadium byte at +0x154 should be 5');

      final tempPath =
          '${Directory.systemTemp.path}/nfl2k5_team_ts18.dat';
      fresh.SaveFile(tempPath);

      final reloaded = GamesaveTool();
      reloaded.LoadSaveFile(tempPath);
      expect(reloaded.GetStadiumName(0), equals('Chicago Field'));
      expect(reloaded.GameSaveData![_team0StadiumByte1], equals(5));
      expect(reloaded.GameSaveData![_team0StadiumByte2], equals(5));

      File(tempPath).deleteSync();
    });

    // T-S19 — SetTeamString Stadium brackets round-trip via name, save → reload
    test('T-S19 SetTeamString Stadium by name matches SetStadiumIndex result',
        () async {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile(_baseRoster));

      // Caller strips brackets before passing to SetTeamString.
      fresh.SetTeamString(0, TeamDataOffsets.Stadium, 'Chicago Field');
      expect(fresh.GetStadiumName(0), equals('Chicago Field'));
      expect(fresh.GameSaveData![_team0StadiumByte1], equals(5));
      expect(fresh.GameSaveData![_team0StadiumByte2], equals(5));

      final tempPath =
          '${Directory.systemTemp.path}/nfl2k5_team_ts19.dat';
      fresh.SaveFile(tempPath);

      final reloaded = GamesaveTool();
      reloaded.LoadSaveFile(tempPath);
      expect(reloaded.GetStadiumName(0), equals('Chicago Field'));

      File(tempPath).deleteSync();
    });

    // T-S20 — SetTeamString length handling
    group('T-S20 SetTeamString length handling', () {
      setUp(() => StaticUtils.Errors.clear());

      test('value too long adds error and leaves value unchanged', () {
        // "49ers" = 5 chars; "Fortyniners" = 11 chars — must fail
        tool.SetTeamString(0, TeamDataOffsets.Nickname, 'Fortyniners');
        expect(StaticUtils.Errors, isNotEmpty,
            reason: 'Too-long value must add an error');
        expect(tool.GetTeamString(0, TeamDataOffsets.Nickname), equals('49ers'),
            reason: 'Nickname must be unchanged after rejected write');
      });

      test('shorter value is padded with trailing spaces to match current length', () {
        final fresh = GamesaveTool();
        fresh.LoadSaveFile(testFile(_baseRoster));

        // "Bears" = 5 chars; "Wolf" = 4 chars — should be stored as "Wolf "
        fresh.SetTeamString(1, TeamDataOffsets.Nickname, 'Wolf');
        expect(StaticUtils.Errors, isEmpty,
            reason: 'Shorter value must succeed (padded to same length)');
        expect(fresh.GetTeamString(1, TeamDataOffsets.Nickname), equals('Wolf '),
            reason: 'Stored value must be right-padded to original length');
      });

      test('padded shorter value survives save/reload', () async {
        final fresh = GamesaveTool();
        fresh.LoadSaveFile(testFile(_baseRoster));

        fresh.SetTeamString(1, TeamDataOffsets.Nickname, 'Wolf');
        final tmp = '${Directory.systemTemp.path}/nfl2k5_team_ts20.dat';
        fresh.SaveFile(tmp);
        final r = GamesaveTool()..LoadSaveFile(tmp);
        expect(r.GetTeamString(1, TeamDataOffsets.Nickname), equals('Wolf '));
        File(tmp).deleteSync();
      });
    });

    // T-S21 — SetTeamString Stadium rejects unknown stadium name
    group('T-S21 SetTeamString Stadium rejects unknown name', () {
      setUp(() => StaticUtils.Errors.clear());

      test('Unknown stadium name adds error and leaves stadium unchanged', () {
        final before = tool.GetStadiumName(0);
        tool.SetTeamString(0, TeamDataOffsets.Stadium, 'Fake Arena');
        expect(StaticUtils.Errors, isNotEmpty,
            reason: 'Unknown stadium must add an error');
        expect(tool.GetStadiumName(0), equals(before),
            reason: 'Stadium must be unchanged after rejected write');
      });
    });

    // T-S22 — InputParser TeamDataKey + TeamData round-trip, save → reload
    test('T-S22 InputParser TeamDataKey/TeamData line sets Nickname and Stadium',
        () async {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile(_baseRoster));

      final parser = InputParser(fresh);
      parser.ProcessLine('TeamDataKey=TeamData,Team,Nickname,Stadium');
      parser.ProcessLine('TeamData,49ers,SF49s,[Chicago Field]');

      expect(fresh.GetTeamString(0, TeamDataOffsets.Nickname), equals('SF49s'));
      expect(fresh.GetStadiumName(0), equals('Chicago Field'));
      expect(fresh.GetTeamString(1, TeamDataOffsets.Nickname), equals('Bears'),
          reason: 'Team 1 should be unaffected');

      final tempPath =
          '${Directory.systemTemp.path}/nfl2k5_team_ts22.dat';
      fresh.SaveFile(tempPath);

      final reloaded = GamesaveTool();
      reloaded.LoadSaveFile(tempPath);
      expect(reloaded.GetTeamString(0, TeamDataOffsets.Nickname), equals('SF49s'));
      expect(reloaded.GetStadiumName(0), equals('Chicago Field'));
      expect(reloaded.GetTeamString(1, TeamDataOffsets.Nickname), equals('Bears'));

      File(tempPath).deleteSync();
    });

    // T-S23 — Player name shift does not disturb S3a (team metadata)
    test('T-S23 Player name shift leaves all 32 team Nicknames unchanged', () {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile(_baseRoster));

      // Snapshot all 32 nicknames before the shift
      final before = [
        for (int i = 0; i < 32; i++)
          fresh.GetTeamString(i, TeamDataOffsets.Nickname)
      ];

      // Grow player 0 last name by 4 chars (triggers ShiftDataDown in S3b)
      final origLast = fresh.GetPlayerLastName(0);
      fresh.SetPlayerLastName(0, origLast + 'ZZZZ', false);

      // All 32 team Nicknames must be unchanged
      for (int i = 0; i < 32; i++) {
        expect(fresh.GetTeamString(i, TeamDataOffsets.Nickname), equals(before[i]),
            reason: 'Team $i Nickname should be unaffected by S3b shift');
      }
    });
  });

  // ─── CLI -teams flag ────────────────────────────────────────────────────────

  group('T-S24 CLI -teams flag prints TeamData output', () {
    test('output contains TeamDataKey= header and 32 TeamData lines', () {
      final out = runCapture([testFile(_baseRoster), '-teams']);

      expect(out, contains('TeamDataKey='));
      final teamLines =
          out.split('\n').where((l) => l.startsWith('TeamData,')).toList();
      expect(teamLines, hasLength(32),
          reason: 'Expected exactly 32 TeamData, lines');
    });

    test('output contains known 49ers values', () {
      final out = runCapture([testFile(_baseRoster), '-teams']);

      final line = out
          .split('\n')
          .firstWhere((l) => l.startsWith('TeamData,49ers,'));
      expect(line, contains('49ers'));
      expect(line, contains('San Francisco'));
      expect(line, contains('[San Francisco Park]'),
          reason: 'Stadium must be wrapped in brackets');
    });

    test('-TeamDataKey: flag selects specific columns', () {
      final out = runCapture([
        testFile(_baseRoster),
        '-teams',
        '-TeamDataKey:TeamData,Team,Nickname,Stadium',
      ]);

      expect(out, contains('TeamDataKey=TeamData,Team,Nickname,Stadium'));
      final teamLines =
          out.split('\n').where((l) => l.startsWith('TeamData,')).toList();
      expect(teamLines, hasLength(32));
      for (final l in teamLines) {
        // TeamData,<team>,<nickname>,[<stadium>] → 4 parts
        expect(l.split(',').length, equals(4),
            reason: 'Nickname+Stadium key → 4 parts per line: $l');
      }
    });
  });

  // ─── T-QR-3: CLI -coach / -coach_all standalone ─────────────────────────────
  //
  // B-6 fix moved showCoaches outside the if(showAbilities||showAppearance) block.
  // Without this test a regression would be silent — -coach would produce no output.

  group('T-QR-3 CLI -coach and -coach_all standalone', () {
    test('-coach without -ab or -app produces 32 Coach, lines', () {
      final out = runCapture([testFile(_baseRoster), '-coach']);
      final coachLines =
          out.split('\n').where((l) => l.startsWith('Coach,')).toList();
      expect(coachLines.length, equals(32),
          reason: '-coach must produce 32 output lines without -ab or -app');
    });

    test('-coach_all produces 32 Coach, lines with all fields', () {
      final out = runCapture([testFile('Base2004Fran_Orig.zip'), '-coach_all']);

      final coachLines =
          out.split('\n').where((l) => l.startsWith('Coach,')).toList();
      expect(coachLines.length, equals(32),
          reason: '-coach_all must produce one line per team');

      // CoachKEY= header must be present and contain all known field names.
      final keyLine = out.split('\n')
          .firstWhere((l) => l.startsWith('CoachKEY='), orElse: () => '');
      expect(keyLine, isNotEmpty, reason: 'CoachKEY= header must be present');
      for (final field in ['Overall', 'QB', 'RB', 'Wins', 'Losses', 'Photo', 'Info3']) {
        expect(keyLine, contains(field),
            reason: 'CoachKEY= must include $field in -coach_all output');
      }

      // Spot-check known values for coach 0 (Erickson / 49ers): string and
      // numeric fields both present.
      final ericksonsLine = coachLines.first;
      expect(ericksonsLine, contains('Dennis'));
      expect(ericksonsLine, contains('Erickson'));
      // Overall=60, Wins=38 were confirmed during binary investigation.
      expect(ericksonsLine, contains('60'));
      expect(ericksonsLine, contains('38'));
    });

    test('-coach_all overrides a partial -CoachKey: flag', () {
      // Even when -CoachKey: selects only 2 fields, -coach_all must use the full set.
      final out = runCapture([
        testFile('Base2004Fran_Orig.zip'),
        '-CoachKey:Coach,Team,Overall',
        '-coach_all',
      ]);
      final coachLines =
          out.split('\n').where((l) => l.startsWith('Coach,')).toList();
      expect(coachLines.length, equals(32));
      // Full set has many more fields than just Overall.
      expect(coachLines.first.split(',').length, greaterThan(5),
          reason: '-coach_all must ignore the partial -CoachKey: and use all fields');
    });
  });

  // ─── T-QR-4: Team data in franchise mode ────────────────────────────────────
  //
  // All T-S15–T-S26 use the roster file.  The franchise file has different
  // m49ersPlayerPointersStart and S3a base addresses; this test ensures the
  // team data feature works in both save types.

  group('T-QR-4 Team data and stadium lookup work in franchise mode', () {
    late GamesaveTool franchiseTool;

    setUpAll(() {
      franchiseTool = GamesaveTool();
      franchiseTool.LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
    });

    test('GetTeamString returns correct S3a data for franchise mode', () {
      expect(franchiseTool.GetTeamString(0, TeamDataOffsets.Nickname), equals('49ers'));
      expect(franchiseTool.GetTeamString(0, TeamDataOffsets.Abbrev),   equals('SF'));
      expect(franchiseTool.GetTeamString(0, TeamDataOffsets.City),     equals('San Francisco'));
      expect(franchiseTool.GetTeamString(1, TeamDataOffsets.Nickname), equals('Bears'));
      expect(franchiseTool.GetTeamString(1, TeamDataOffsets.City),     equals('Chicago'));
    });

    test('GetStadiumName returns valid names for all 32 franchise teams', () {
      for (int i = 0; i < 32; i++) {
        final name = franchiseTool.GetStadiumName(i);
        expect(name, isNot(equals('!!!!Invalid!!!!')),
            reason: 'Team $i stadium must resolve in franchise mode');
        expect(name, isNotEmpty);
      }
    });

    test('GetTeamDataAll produces 32 TeamData lines in franchise mode', () {
      final out = franchiseTool.GetTeamDataAll();
      final lines = out.split('\n').where((l) => l.startsWith('TeamData,')).toList();
      expect(lines.length, equals(32),
          reason: 'GetTeamDataAll must produce 32 lines in franchise mode');
    });

    test('GetTeamString returns non-error values for all 32 teams × all attrs', () {
      for (int i = 0; i < 32; i++) {
        for (final attr in [
          TeamDataOffsets.Nickname,
          TeamDataOffsets.Abbrev,
          TeamDataOffsets.City,
          TeamDataOffsets.AbbrAlt,
        ]) {
          final v = franchiseTool.GetTeamString(i, attr);
          expect(v, isNotEmpty,
              reason: 'Franchise team $i ${attr.name} should not be empty');
          expect(v, isNot(equals('!!!!Invalid!!!!')),
              reason: 'Franchise team $i ${attr.name} returned invalid sentinel');
        }
      }
    });
  });

  // ─── CLI -show_stadium_names flag ───────────────────────────────────────────

  group('T-S26 CLI -show_stadium_names lists all stadiums', () {
    test('output contains header and at least 32 stadium entries', () {
      final out = runCapture([testFile(_baseRoster), '-show_stadium_names']);

      expect(out, contains('Stadium names:'));
      // Count "NN: <name>" lines — expect all 53 entries (s00–s59 with gaps)
      final entries =
          out.split('\n').where((l) => RegExp(r'^\s+\d+:').hasMatch(l)).toList();
      expect(entries.length, greaterThanOrEqualTo(32),
          reason: 'At least one entry per NFL team stadium');
    });

    test('output contains known stadium names in brackets', () {
      final out = runCapture([testFile(_baseRoster), '-show_stadium_names']);

      expect(out, contains('[San Francisco Park]'));
      expect(out, contains('[Chicago Field]'));
      expect(out, contains('[Arizona Stadium]'));
    });

    test('entries are sorted by index', () {
      final out = runCapture([testFile(_baseRoster), '-show_stadium_names']);

      final indices = out
          .split('\n')
          .where((l) => RegExp(r'^\s+\d+:').hasMatch(l))
          .map((l) => int.parse(l.trim().split(':').first))
          .toList();
      expect(indices, equals([...indices]..sort()),
          reason: 'Stadium entries must be in ascending index order');
    });
  });

  // ─── CLI -teams round-trip ──────────────────────────────────────────────────

  group('T-S25 CLI -teams round-trip: extract → apply → verify', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('nfl2k5_teams_rt');
      StaticUtils.Errors.clear();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    String tmp(String name) => '${tempDir.path}/$name';

    test('GetTeamDataAll output can be re-applied to produce identical values',
        () {
      // Step 1 — extract with full key
      final extracted = runCapture([
        testFile(_baseRoster),
        '-ab', '-teams',
        '-TeamDataKey:TeamData,Team,Nickname,Abbrev,Stadium,City,AbbrAlt',
      ]);

      // Isolate the TeamDataKey= block (key line + 32 data lines)
      final lines = extracted.split('\n');
      final keyIdx =
          lines.indexWhere((l) => l.startsWith('TeamDataKey='));
      expect(keyIdx, isNot(equals(-1)), reason: 'TeamDataKey= line must exist');
      final teamBlock = lines
          .skip(keyIdx)
          .take(33) // key line + 32 data lines
          .join('\n');

      // Write the block as a .txt file to apply
      final txtPath = tmp('teams.txt');
      File(txtPath).writeAsStringSync(teamBlock);

      // Step 2 — apply the extracted text back to a fresh copy and save
      final outDat = tmp('output.dat');
      Program.RunMain([testFile(_baseRoster), txtPath, '-out:$outDat']);
      expect(File(outDat).existsSync(), isTrue);

      // Step 3 — reload and verify spot-check values
      final tool = GamesaveTool();
      tool.LoadSaveFile(outDat);

      expect(tool.GetTeamString(0, TeamDataOffsets.Nickname), equals('49ers'));
      expect(tool.GetTeamString(0, TeamDataOffsets.City),     equals('San Francisco'));
      expect(tool.GetStadiumName(0), equals('San Francisco Park'));
      expect(tool.GetTeamString(1, TeamDataOffsets.Nickname), equals('Bears'));
      expect(tool.GetTeamString(1, TeamDataOffsets.City),     equals('Chicago'));

      expect(StaticUtils.Errors, isEmpty,
          reason: 'Round-trip must produce no errors');
    });

    test('stadium reassignment survives save/reload cycle', () {
      // Write a TeamData file that swaps 49ers → Chicago Field
      final txtPath = tmp('swap.txt');
      File(txtPath).writeAsStringSync(
          'TeamDataKey=TeamData,Team,Stadium\n'
          'TeamData,49ers,[Chicago Field]\n');

      final outDat = tmp('swapped.dat');
      Program.RunMain([testFile(_baseRoster), txtPath, '-out:$outDat']);
      expect(File(outDat).existsSync(), isTrue);

      final tool = GamesaveTool();
      tool.LoadSaveFile(outDat);
      expect(tool.GetStadiumName(0), equals('Chicago Field'));
      // Other teams untouched
      expect(tool.GetStadiumName(1), equals('Chicago Field'),
          reason: 'Bears still at Chicago Field (unchanged)');
      expect(StaticUtils.Errors, isEmpty);
    });

    test('shorter nickname via CLI is padded and reads back correctly via -teams', () {
      // Step 1 — apply "Wolf" (4 chars) as the Bears nickname (5 chars).
      // The .txt line has no trailing space; ProcessLine trims the line, so the
      // tool must pad the value itself.
      final txtPath = tmp('wolf.txt');
      File(txtPath).writeAsStringSync(
          'TeamDataKey=TeamData,Team,Nickname\n'
          'TeamData,Bears,Wolf\n');

      final outDat = tmp('wolf_out.dat');
      Program.RunMain([testFile(_baseRoster), txtPath, '-out:$outDat']);
      expect(File(outDat).existsSync(), isTrue);
      expect(StaticUtils.Errors, isEmpty,
          reason: 'Shorter nickname must not produce errors');

      // Step 2 — read the result back via the -teams CLI flag.
      final out = runCapture([outDat, '-teams']);
      // The stored value is "Wolf " (space-padded to 5 chars).
      // In CSV output it appears as "Wolf ," — the trailing space is before the
      // next comma, confirming the padding was actually stored.
      final bearLine = out.split('\n')
          .firstWhere((l) => l.startsWith('TeamData,Bears,'), orElse: () => '');
      expect(bearLine, isNotEmpty,
          reason: 'A TeamData,Bears, line must appear in -teams output');
      expect(bearLine, contains('Wolf ,'),
          reason: 'Nickname must be "Wolf " (padded to 5 chars) in CSV output');
    });
  });

  // ─── T-QR-6: S1a data unchanged after S2 and S3a writes ─────────────────────
  //
  // S1a (stadium short-name strings) is read-only from our tool's perspective.
  // Verify that coach string (S2) edits and team metadata (S3a) same-length writes
  // do not accidentally overwrite the S1a section.

  group('T-QR-6 S1a stadium names unchanged after S2 and S3a writes', () {
    test('all 32 stadium names survive a S2 shrink + S3a same-length edit', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_baseRoster));

      // Snapshot all 32 stadium names from S1a.
      final namesBefore = [for (int i = 0; i < 32; i++) tool.GetStadiumName(i)];

      // S2 write: shorten team 0 coach LastName — triggers ShiftDataUp in S2.
      tool.SetCoachAttribute(0, CoachOffsets.LastName, 'E');

      // S3a write: same-length Nickname change for team 0.
      tool.SetTeamString(0, TeamDataOffsets.Nickname, 'SF49s');

      final namesAfter = [for (int i = 0; i < 32; i++) tool.GetStadiumName(i)];
      for (int i = 0; i < 32; i++) {
        expect(namesAfter[i], equals(namesBefore[i]),
            reason: 'Team $i stadium name must survive S2/S3a writes (S1a is read-only)');
      }
    });
  });
}
