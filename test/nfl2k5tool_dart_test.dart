import 'dart:io';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:test/test.dart';

/// Path to test data files, relative to the repo root.
String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

/// Paths to every raw SAVEGAME.DAT in the years/ test tree.
/// These files are direct binary saves (not zipped), loaded via LoadSaveFile(.dat).
const Map<String, String> _yearRosters = {
  'BaseRoster':
      'years/BaseRoster/SAVEGAME.DAT',
  '2010':
      'years/2010/UDATA/53450030/2769FDD5CE60/SAVEGAME.DAT',
  '2011':
      'years/2011/UDATA/53450030/AE6C35966920/SAVEGAME.DAT',
  'Official_Update1':
      'years/Official_Update1/UDATA/53450030/A727BB490571/SAVEGAME.DAT',
  'US_ESPN_NFL_2_Roster2005_2006':
      'years/US_ESPN_NFL_2_Roster2005_2006/UDATA/53450030/75F5FD0F3723/SAVEGAME.DAT',
  '1958-1980_all_time':
      'years/1958-1980_all_time/UDATA/53450030/1ABCA121A028/SAVEGAME.DAT',
  '2026_LostsouL':
      'years/2026_LostsouL/UDATA/53450030/C4841DA032C8/SAVEGAME.DAT',
};

/// Replace the first character so the name stays the same length but differs.
/// Used by T-3 to exercise the same-length (no-shift) code path.
String _sameLengthVariant(String name) {
  if (name.isEmpty) return name;
  final ch = name[0] == 'Z' ? 'A' : 'Z';
  return ch + name.substring(1);
}

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

  // ───────────────────────────────────────────────────────────────────────────
  // Bug-fix regression tests (T-1 through T-5 from pointer_bugs_plan.md)
  // ───────────────────────────────────────────────────────────────────────────

  // T-1 — AutoPlayerStartLocation() detects the correct player-array base
  //
  // Different roster files have different player-array starting offsets.
  // Four "clean" files (BaseRoster, 2010, AllTime, 2026_LostsouL) all use
  // 0xAFA8.  Three community-edited files (2011, Official_Update1, ESPN2005)
  // have their player arrays shifted to 0xAFF0 — the game's pointer tables
  // in those files are internally consistent with 0xAFF0 and reading real
  // player names confirms that is the correct base.
  //
  // The key regression to catch: if AutoPlayerStartLocation fails to find
  // ANY valid candidate it must NOT set mPlayerStart to GameSaveData.length
  // (a latent edge-case bug that was present before the fix at the bottom of
  // that function).
  group('T-1 – AutoPlayerStartLocation detects correct player-array base', () {
    // Map from roster key to expected mPlayerStart.
    const expectedBase = <String, int>{
      'BaseRoster':                  0xAFA8,
      '2010':                        0xAFA8,
      '2011':                        0xAFF0,
      'Official_Update1':            0xAFF0,
      'US_ESPN_NFL_2_Roster2005_2006': 0xAFF0,
      '1958-1980_all_time':          0xAFA8,
      '2026_LostsouL':               0xAFA8,
    };

    for (final entry in _yearRosters.entries) {
      test('${entry.key} gives correct mPlayerStart', () {
        final tool = GamesaveTool();
        final ok = tool.LoadSaveFile(testFile(entry.value));
        expect(ok, isTrue,
            reason: '${entry.key}: LoadSaveFile must succeed');
        // mPlayerStart must never be set to the file length (latent bug guard).
        expect(tool.mPlayerStart, lessThan(tool.GameSaveData!.length),
            reason: '${entry.key}: mPlayerStart must not be set to fileSize '
                '(indicates no valid player candidate was found)');
        // Must match the known-good base for this file.
        expect(
          tool.mPlayerStart,
          equals(expectedBase[entry.key]),
          reason:
              '${entry.key}: mPlayerStart = ${tool.mPlayerStart.toRadixString(16)}, '
              'expected ${expectedBase[entry.key]!.toRadixString(16)}',
        );
      });
    }
  });

  // T-2 — Seasoned Roster (2010) reads sensible player data after Bug 1 fix
  //
  // Without Bug 1 fixed, mPlayerStart ends up at 0xAFF0, so every name lookup
  // reads garbage bytes and either crashes or returns the invalid sentinel.
  group('T-2 – Seasoned Roster (2010) reads sensible player data', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_yearRosters['2010']!));
    });

    test('player 0 first name is not the invalid sentinel', () {
      expect(tool.GetPlayerFirstName(0), isNot(contains('INVALID')));
    });

    test('player 0 last name is not the invalid sentinel', () {
      expect(tool.GetPlayerLastName(0), isNot(contains('INVALID')));
    });

    test('49ers have between 52 and 54 players', () {
      expect(tool.GetNumPlayers('49ers'), inInclusiveRange(52, 54));
    });
  });

  // T-3 — Round-trip same-length name edit (no string-table shift)
  //
  // Same-length edits don't call ShiftDataDown/Up, so they exercise the
  // pointer-resolve path without disturbing college or name pointers.
  // This baseline confirms that SetName / SaveFile / LoadSaveFile work at
  // all, independent of Bugs 2 & 3.
  group('T-3 – round-trip same-length name edit (no string-table shift)', () {
    late File tempFile;
    late GamesaveTool reloaded;
    late String originalLast;
    late String originalCollege;
    late String player1Last;
    late String newLast;

    setUpAll(() {
      final orig = GamesaveTool();
      orig.LoadSaveFile(testFile(_yearRosters['BaseRoster']!));

      originalLast   = orig.GetPlayerLastName(0);
      originalCollege = orig.GetCollege(0);
      player1Last    = orig.GetPlayerLastName(1);

      // Produce a different name with the same length so no shift occurs.
      newLast = _sameLengthVariant(originalLast);
      orig.SetPlayerLastName(0, newLast, false);

      tempFile = File(
          '${Directory.systemTemp.path}/nfl2k5_roundtrip_t3.dat');
      orig.SaveFile(tempFile.path);

      reloaded = GamesaveTool();
      reloaded.LoadSaveFile(tempFile.path);
    });

    tearDownAll(() {
      if (tempFile.existsSync()) tempFile.deleteSync();
    });

    test('player 0 has the new same-length last name', () {
      expect(reloaded.GetPlayerLastName(0), equals(newLast));
    });

    test('player 1 last name is unchanged', () {
      expect(reloaded.GetPlayerLastName(1), equals(player1Last));
    });

    test('player 0 college is unchanged', () {
      expect(reloaded.GetCollege(0), equals(originalCollege));
    });
  });

  // T-4 — Round-trip longer name edit (+4 characters = +8 string-table bytes)
  //
  // A longer name forces ShiftDataDown, which shifts all subsequent string
  // data and requires AdjustPlayerNamePointers (Bug 2) and
  // _adjustCollegeEntryPointers (Bug 3) to update every affected pointer.
  // Without Bug 2 fixed, a pointer carry out of byte 2 leaves byte 3 stale.
  // Without Bug 3 fixed, college-entry pointers still point to the old
  // (now-shifted) name bytes and GetCollege returns the wrong name.
  group('T-4 – round-trip longer name edit +4 chars (exercises Bugs 2 & 3)', () {
    late File tempFile;
    late GamesaveTool reloaded;
    late String originalLast;
    late String originalCollege;
    late String player1Last;
    late String newLast;

    setUpAll(() {
      final orig = GamesaveTool();
      orig.LoadSaveFile(testFile(_yearRosters['BaseRoster']!));

      originalLast    = orig.GetPlayerLastName(0);
      originalCollege = orig.GetCollege(0);
      player1Last     = orig.GetPlayerLastName(1);

      // Append four characters (+8 bytes in the UTF-16LE string table).
      newLast = '${originalLast}ZZZZ';
      orig.SetPlayerLastName(0, newLast, false);

      tempFile = File(
          '${Directory.systemTemp.path}/nfl2k5_roundtrip_t4.dat');
      orig.SaveFile(tempFile.path);

      reloaded = GamesaveTool();
      reloaded.LoadSaveFile(tempFile.path);
    });

    tearDownAll(() {
      if (tempFile.existsSync()) tempFile.deleteSync();
    });

    test('player 0 has the new longer last name', () {
      expect(reloaded.GetPlayerLastName(0), equals(newLast));
    });

    test('player 1 last name is unchanged after forward shift (Bug 2 path)', () {
      expect(reloaded.GetPlayerLastName(1), equals(player1Last));
    });

    test('player 0 college is unchanged after forward shift (Bug 3 path)', () {
      expect(reloaded.GetCollege(0), equals(originalCollege));
    });
  });

  // T-5 — Round-trip shorter name edit (-3 characters = -6 string-table bytes)
  //
  // A shorter name forces ShiftDataUp.  Same pointer-adjustment requirements
  // as T-4 but in the opposite direction.  Verifies that AdjustPointer
  // (Bug 2) and _adjustCollegeEntryPointers (Bug 3) also work correctly when
  // the delta is negative.
  group('T-5 – round-trip shorter name edit -3 chars (exercises Bugs 2 & 3)', () {
    late File tempFile;
    late GamesaveTool reloaded;
    late String originalLast;
    late String originalCollege;
    late String player1Last;
    late String newLast;

    setUpAll(() {
      final orig = GamesaveTool();
      orig.LoadSaveFile(testFile(_yearRosters['BaseRoster']!));

      originalLast    = orig.GetPlayerLastName(0);
      originalCollege = orig.GetCollege(0);
      player1Last     = orig.GetPlayerLastName(1);

      // Drop 3 chars (-6 bytes in the UTF-16LE string table).
      // Fall back to 1 char if the original is too short.
      newLast = originalLast.length > 3
          ? originalLast.substring(0, originalLast.length - 3)
          : originalLast.substring(0, 1);
      orig.SetPlayerLastName(0, newLast, false);

      tempFile = File(
          '${Directory.systemTemp.path}/nfl2k5_roundtrip_t5.dat');
      orig.SaveFile(tempFile.path);

      reloaded = GamesaveTool();
      reloaded.LoadSaveFile(tempFile.path);
    });

    tearDownAll(() {
      if (tempFile.existsSync()) tempFile.deleteSync();
    });

    test('player 0 has the new shorter last name', () {
      expect(reloaded.GetPlayerLastName(0), equals(newLast));
    });

    test('player 1 last name is unchanged after backward shift (Bug 2 path)', () {
      expect(reloaded.GetPlayerLastName(1), equals(player1Last));
    });

    test('player 0 college is unchanged after backward shift (Bug 3 path)', () {
      expect(reloaded.GetCollege(0), equals(originalCollege));
    });
  });

  // T-6 — SetName boundary guard (Bug 4): invalid pointer causes no data overwrite
  //
  // The 2011 Roster file contains players whose name pointers resolve to
  // addresses outside the modifiable name section [mStringTableStart,
  // mModifiableNameSectionEnd).  These are pre-existing corruptions left by a
  // prior buggy tool run.
  //
  // Without Bug 4 fixed, calling SetName for such a player would:
  //   1. Call ShiftDataDown/Up starting from the out-of-bounds address,
  //      overwriting file sections outside the string table (boundary overwrite).
  //   2. Write the new name bytes at the wrong location.
  //   3. Run AdjustPlayerNamePointers from the wrong shift origin, corrupting
  //      all subsequent valid name pointers.
  //
  // With the fix, SetName detects the out-of-bounds destination, emits a
  // diagnostic to stderr, and returns without touching any file data.
  //
  // Player 182 (0-indexed from mPlayerStart = 0xAFF0) in the 2011 file has its
  // first-name pointer resolving to 0x74A38, which is 0x1528 bytes below
  // mStringTableStart (0x75960).  That makes it the ideal trigger for this test.
  group('T-6 – SetName boundary guard: invalid pointer causes no data overwrite', () {
    late GamesaveTool tool;
    late List<int> snapshotBefore;

    // Player index whose fname pointer is known to resolve below mStringTableStart.
    const int badPlayer  = 182;
    // Region that would be overwritten by a ShiftDataDown starting at 0x74A38.
    const int riskStart  = 0x74900;
    const int riskEnd    = 0x75960; // == mStringTableStart for Roster

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_yearRosters['2011']!));
      // Snapshot the at-risk region before any write attempt.
      snapshotBefore = tool.GameSaveData!.sublist(riskStart, riskEnd).toList();
    });

    test('player $badPlayer fname pointer resolves below mStringTableStart '
        '(pre-condition)', () {
      final ptrLoc = tool.mPlayerStart + badPlayer * 84 + 0x10;
      final dest   = tool.GetPointerDestination(ptrLoc);
      expect(dest, lessThan(tool.mStringTableStart),
          reason: 'Player $badPlayer must have an out-of-bounds fname pointer '
              'for this test to exercise the boundary-guard path');
    });

    test('SetPlayerFirstName with out-of-bounds pointer leaves guarded region '
        'unchanged', () {
      tool.SetPlayerFirstName(badPlayer, 'TestGuard', false);

      final snapshotAfter =
          tool.GameSaveData!.sublist(riskStart, riskEnd).toList();
      expect(snapshotAfter, equals(snapshotBefore),
          reason: 'Region 0x${riskStart.toRadixString(16)}–'
              '0x${riskEnd.toRadixString(16)} must not be modified when '
              'player $badPlayer has an out-of-bounds name pointer');
    });
  });

  // T-7 — checkNamePointers() detects shared string-table entries
  //
  // Flying Finn's editor saves space by pointing multiple player fname/lname
  // pointers at the same string-table address.  The 2011 community roster was
  // built with that editor and contains thousands of such aliases.
  // Week_6_2024 was produced by this tool, which allocates a unique entry per
  // name, so it should have no shared pointers.
  //
  // checkNamePointers() is also called automatically inside LoadSaveFile, so
  // this test calls it a second time to verify the return value directly.
  group('T-7 – checkNamePointers detects shared string-table entries', () {
    test('2011 (community-edited) returns true – shared pointers present', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_yearRosters['2011']!));
      expect(tool.checkNamePointers(), isTrue,
          reason: 'The 2011 roster was built with Flying Finn\'s editor, '
              'which re-uses string-table entries across multiple players');
    });

    test('Week_6_2024 returns false – all pointers unique', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile('Week_6_2024.zip'));
      expect(tool.checkNamePointers(), isFalse,
          reason: 'Week_6_2024 was built with this tool, which assigns a '
              'unique string-table entry per player name');
    });
  });
}
