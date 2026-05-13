import 'dart:io';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/gamesave_tool_io.dart';
import 'package:test/test.dart';

/// Path to test data files, relative to the repo root.
String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

/// Paths to every raw SAVEGAME.DAT in the years/ test tree.
/// These files are direct binary saves (not zipped), loaded via LoadSaveFile(.dat).
const Map<String, String> _yearRosters = {
  'BaseRoster':
      'BaseRoster/SAVEGAME.DAT',
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

  // T-8 — setupForSaveType() initialises correctly when GameSaveData is
  //        assigned directly (rather than via loadSaveData / LoadSaveFile).
  //
  // The C# refactor extracted this logic so AutoFixSkinFromPhoto could create
  // a second GamesaveTool, assign raw bytes, and then call setupForSaveType().
  // This test verifies that the Dart equivalent works the same way.
  group('T-8 – setupForSaveType() with direct GameSaveData assignment', () {
    test('roster magic bytes → SaveType.Roster', () {
      final bytes = File(testFile(_yearRosters['BaseRoster']!)).readAsBytesSync();
      final tool = GamesaveTool();
      tool.GameSaveData = bytes;
      tool.setupForSaveType();
      expect(tool.saveType, equals(SaveType.Roster));
    });

    test('franchise magic bytes → SaveType.Franchise', () {
      // Extract raw bytes from the franchise zip the same way LoadSaveFile does.
      final zip = File(testFile('Base2004Fran_Orig.zip')).readAsBytesSync();
      final bytes = StaticUtils.ExtractFileFromZipData(zip, null, 'SAVEGAME.DAT');
      expect(bytes, isNotNull);
      final tool = GamesaveTool();
      tool.GameSaveData = bytes;
      tool.setupForSaveType();
      expect(tool.saveType, equals(SaveType.Franchise));
    });

    test('mPlayerStart is sane after direct assignment + setupForSaveType', () {
      final bytes = File(testFile(_yearRosters['BaseRoster']!)).readAsBytesSync();
      final tool = GamesaveTool();
      tool.GameSaveData = bytes;
      tool.setupForSaveType();
      expect(tool.mPlayerStart, equals(0xAFA8));
    });
  });

  // T-9 — Team player-control methods (franchise mode only)
  //
  // These methods read/write a byte table at 0x913CC in franchise saves.
  // Tests operate on a fresh in-memory copy so they don't interfere with
  // each other or with other groups.
  group('T-9 – team player-control (franchise save)', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
    });

    test('setTeamPlayerControlled / isTeamPlayerControlled round-trip', () {
      // Capture original value, then toggle, then restore.
      final original = tool.isTeamPlayerControlled('49ers');
      tool.setTeamPlayerControlled('49ers', !original);
      expect(tool.isTeamPlayerControlled('49ers'), equals(!original));
      tool.setTeamPlayerControlled('49ers', original);
      expect(tool.isTeamPlayerControlled('49ers'), equals(original));
    });

    test('setAllTeamsPlayerControlled sets all 32 teams to user-controlled', () {
      tool.setAllTeamsPlayerControlled();
      for (int i = 0; i < 32; i++) {
        expect(tool.isTeamPlayerControlled(GamesaveTool.sTeamsDataOrder[i]),
            isTrue,
            reason: '${GamesaveTool.sTeamsDataOrder[i]} should be user-controlled');
      }
    });

    test('setPlayerControlledTeams with team list controls only listed teams', () {
      // Set all to CPU first, then re-enable two.
      for (int i = 0; i < 32; i++)
        tool.setTeamPlayerControlled(GamesaveTool.sTeamsDataOrder[i], false);

      tool.setPlayerControlledTeams('PlayerControlled=[49ers,Bears,]');

      expect(tool.isTeamPlayerControlled('49ers'), isTrue);
      expect(tool.isTeamPlayerControlled('Bears'), isTrue);
      expect(tool.isTeamPlayerControlled('Bengals'), isFalse);
    });

    test('setPlayerControlledTeams with All sets every team', () {
      // First CPU-out all teams.
      for (int i = 0; i < 32; i++)
        tool.setTeamPlayerControlled(GamesaveTool.sTeamsDataOrder[i], false);

      tool.setPlayerControlledTeams('PlayerControlled=All');

      for (int i = 0; i < 32; i++) {
        expect(tool.isTeamPlayerControlled(GamesaveTool.sTeamsDataOrder[i]),
            isTrue);
      }
    });

    test('getPlayerControlledTeams output contains controlled team names', () {
      for (int i = 0; i < 32; i++)
        tool.setTeamPlayerControlled(GamesaveTool.sTeamsDataOrder[i], false);
      tool.setTeamPlayerControlled('49ers', true);
      tool.setTeamPlayerControlled('Cowboys', true);

      final output = tool.getPlayerControlledTeams();
      expect(output, contains('PlayerControlled=['));
      expect(output, contains('49ers'));
      expect(output, contains('Cowboys'));
      expect(output, contains('PlayerControlledTeams=2'));
    });

    test('getPlayerControlledTeams includes roster note when save type is Roster', () {
      // Use a separate roster-mode tool to check the type annotation.
      final rosterTool = GamesaveTool();
      rosterTool.LoadSaveFile(testFile('Week_6_2024.zip'));
      final output = rosterTool.getPlayerControlledTeams();
      expect(output, contains('not applicable to Type = Roster'));
    });

    test('SAVEGAME14uc.DAT has exactly 14 user-controlled teams', () {
      final tool14 = GamesaveTool();
      final ok = tool14.LoadSaveFile(testFile('SAVEGAME14uc.DAT'));
      expect(ok, isTrue, reason: 'SAVEGAME14uc.DAT must load successfully');
      expect(tool14.saveType, equals(SaveType.Franchise),
          reason: 'Player-control table only exists in Franchise saves');
      final output = tool14.getPlayerControlledTeams();
      expect(output, contains('PlayerControlledTeams=14'));
    });
  });

  // T-10 — autoFixSkinFromPhoto()
  //
  // Verifies the null-guard path (no baseRosterData → silent skip) and the
  // happy path (valid base data → runs without throwing, makes no spurious
  // changes when base and current are identical).
  group('T-10 – autoFixSkinFromPhoto', () {
    test('no-ops gracefully when baseRosterData is null', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile('Week_6_2024.zip'));
      // Must not throw; baseRosterData defaults to null.
      expect(() => tool.autoFixSkinFromPhoto(), returnsNormally);
    });

    test('runs without throwing when given valid base roster bytes', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile('Week_6_2024.zip'));

      final baseBytes =
          File(testFile(_yearRosters['BaseRoster']!)).readAsBytesSync();
      expect(() => tool.autoFixSkinFromPhoto(baseBytes), returnsNormally);
    });

    test('identity case: same file as base and current leaves data unchanged', () {
      // When the base and current file are identical every photo→skin/face
      // mapping already matches, so no bytes should be modified.
      final bytes =
          File(testFile(_yearRosters['BaseRoster']!)).readAsBytesSync();

      final tool = GamesaveTool();
      tool.loadSaveData(bytes);
      final before = tool.GameSaveData!.toList();

      tool.autoFixSkinFromPhoto(bytes);
      expect(tool.GameSaveData!.toList(), equals(before));
    });
  });

  // T-11 — InputParser PlayerLookupAndVerify mode
  //
  // _lookupPlayerAndVerify() finds a player by name and checks that the input
  // line is a substring of GetPlayerData output.  If not, it adds to
  // StaticUtils.Errors.  Tests use a key of "FName,LName,Speed" so that
  // FindPlayer searches without a position filter (no Position column) and the
  // Speed field gives us a controlled mismatch value.
  group('T-11 – InputParser PlayerLookupAndVerify mode', () {
    late GamesaveTool tool;
    late String player0First;
    late String player0Last;
    late String player0Speed; // actual speed from the save file

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile('Week_6_2024.zip'));
      // Key with no Position column so FindPlayer gets pos=null and searches
      // all positions — guarantees the name lookup succeeds.
      // GetAttributeValue expects lowercase 'fname'/'lname'; enum names are
      // case-sensitive for other attributes (e.g. 'Speed' not 'speed').
      tool.SetKey('fname,lname,Speed');
      player0First = tool.GetPlayerFirstName(0);
      player0Last  = tool.GetPlayerLastName(0);
      // Extract speed from GetPlayerData output: "FName,LName,Speed,"
      final raw = tool.GetPlayerData(0, true, true); // e.g. "Brock,Purdy,78,"
      final parts = raw.split(',');
      player0Speed = parts.length >= 3 ? parts[2] : '50';
    });

    setUp(() => StaticUtils.Errors.clear());

    test('matching player line adds no error', () {
      // Line is exactly what GetPlayerData produces (minus trailing comma).
      final line = '$player0First,$player0Last,$player0Speed';
      final parser = InputParser(tool);
      parser.ProcessLine('LookupAndVerify');
      parser.ProcessLine(line);
      expect(StaticUtils.Errors, isEmpty,
          reason: 'Exact attribute values should verify cleanly');
    });

    test('mismatched Speed value adds a verify error', () {
      // Build a line with correct name but a speed that cannot match.
      // Speed is stored as 0–99; any value outside 0–99 or clearly different
      // from the real value will not appear in GetPlayerData output.
      final actualSpeed = int.tryParse(player0Speed) ?? 50;
      final wrongSpeed  = (actualSpeed + 1) % 100; // guaranteed ≠ actual
      final line = '$player0First,$player0Last,$wrongSpeed';
      final parser = InputParser(tool);
      parser.ProcessLine('LookupAndVerify');
      parser.ProcessLine(line);
      expect(StaticUtils.Errors, isNotEmpty,
          reason: 'Wrong Speed value should trigger a verify error');
      expect(StaticUtils.Errors.first, contains('Fail! LookupAndVerify'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // T-C: Coach non-string data (franchise save) — CoachTestPlan.md
  // ───────────────────────────────────────────────────────────────────────────

  // T-C1 — GetCoachDataAll smoke test (read-only)
  //
  // Loads the base franchise file with the full CoachKey and verifies that
  // GetCoachDataAll returns data for exactly 32 coaches including known
  // ground-truth values for Coach 0 (Dennis Erickson / 49ers).
  group('T-C: Coach non-string data (franchise save)', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      final ok = tool.LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
      expect(ok, isTrue, reason: 'Base2004Fran_Orig.zip must load');
    });

    // T-C1
    test('T-C1 GetCoachDataAll returns all 32 coaches with known values', () {
      tool.CoachKey = tool.CoachKeyAll;
      final all = tool.GetCoachDataAll();
      expect(all, isNotEmpty);

      final coachLines =
          all.split('\n').where((l) => l.startsWith('Coach,')).toList();
      expect(coachLines, hasLength(32),
          reason: 'Expected exactly 32 Coach, lines');

      // Coach 0 is Erickson / 49ers
      expect(coachLines[0], contains('Dennis'));
      expect(coachLines[0], contains('Erickson'));
      // Ground-truth numeric values
      expect(coachLines[0], contains('38'));  // Wins
      expect(coachLines[0], contains('42'));  // Losses
      expect(coachLines[0], contains('7025')); // Photo
      expect(coachLines[0], contains('60'));   // Overall
    });

    // T-C2 — Set/Get 1-byte rating fields, in-memory
    test('T-C2 Set/Get 1-byte rating fields round-trip in memory', () {
      tool.SetCoachAttribute(0, CoachOffsets.Overall, '99');
      tool.SetCoachAttribute(0, CoachOffsets.QB, '1');
      tool.SetCoachAttribute(0, CoachOffsets.Professionalism, '50');

      expect(tool.GetCoachAttribute(0, CoachOffsets.Overall), equals('99'));
      expect(tool.GetCoachAttribute(0, CoachOffsets.QB), equals('1'));
      expect(tool.GetCoachAttribute(0, CoachOffsets.Professionalism),
          equals('50'));
    });

    // T-C3 — Set/Get Photo (2-byte LE), in-memory
    test('T-C3 Set/Get Photo 2-byte field round-trip (value requires high byte)', () {
      tool.SetCoachAttribute(0, CoachOffsets.Photo, '512');
      // GetCoachAttribute pads Photo to 4 digits
      expect(tool.GetCoachAttribute(0, CoachOffsets.Photo), equals('0512'));
    });

    // T-C4 — Set/Get 2-byte stat field — documents Issue B
    test('T-C4 Wins ≤255 round-trips correctly (Issue B: low byte only)', () {
      tool.SetCoachAttribute(0, CoachOffsets.Wins, '200');
      expect(tool.GetCoachAttribute(0, CoachOffsets.Wins), equals('200'));
    });

    test('T-C4 Wins=256 loses high byte — documents Issue B known limitation', () {
      tool.SetCoachAttribute(0, CoachOffsets.Wins, '256');
      // Issue B — known limitation: only low byte stored/retrieved
      expect(tool.GetCoachAttribute(0, CoachOffsets.Wins), equals('0'));
    });

    // T-C5 — Set/Get Body field (coach-model enum)
    group('T-C5 Body field (coach-model enum)', () {
      setUp(() => StaticUtils.Errors.clear());

      test('original Body for team 0 is a known coach-model key', () {
        // Fresh load to get pristine value (T-C2 didn't touch Body)
        final fresh = GamesaveTool();
        fresh.LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
        final body = fresh.GetCoachAttribute(0, CoachOffsets.Body);
        expect(body, isNot(equals('!!!!Invalid!!!!')));
      });

      test('set Body to Bill Belichick, get returns Bill Belichick', () {
        tool.SetCoachAttribute(0, CoachOffsets.Body, '[Bill Belichick]');
        expect(tool.GetCoachAttribute(0, CoachOffsets.Body),
            equals('Bill Belichick'));
        expect(StaticUtils.Errors, isEmpty);
      });

      test('set Body to invalid coach name adds an error', () {
        tool.SetCoachAttribute(0, CoachOffsets.Body, '[InvalidCoachName]');
        expect(StaticUtils.Errors, isNotEmpty);
      });
    });

    // T-C12 — CoachKey validation
    group('T-C12 CoachKey validation', () {
      setUp(() => StaticUtils.Errors.clear());

      test('bogus field in CoachKey adds an error', () {
        tool.CoachKey = 'Coach,Team,Overall,BOGUSFIELD';
        expect(StaticUtils.Errors, isNotEmpty);
      });

      test('valid partial CoachKey sets key and GetCoachData contains only those fields', () {
        tool.CoachKey = 'Coach,Team,Overall,QB';
        expect(StaticUtils.Errors, isEmpty);
        final data = tool.GetCoachData(0);
        // Should start with "Coach,49ers," and have Overall + QB values, then end
        expect(data, startsWith('Coach,49ers,'));
        // Trailing comma stripped by GetCoachData: "Coach,49ers,<Overall>,<QB>" → 4 parts
        final parts = data.split(',');
        expect(parts.length, equals(4),
            reason: 'Coach,Team,Overall,QB → 4 comma-separated parts (no trailing comma)');
      });
    });

    // T-C13 — Playcalling fields have independent offsets (Issue C fixed)
    test('T-C13 ShotgunRun and IFormRun are independent (offset bug fixed)', () {
      tool.SetCoachAttribute(0, CoachOffsets.ShotgunRun, '99');
      tool.SetCoachAttribute(0, CoachOffsets.IFormRun, '11');
      expect(tool.GetCoachAttribute(0, CoachOffsets.ShotgunRun), equals('99'));
      expect(tool.GetCoachAttribute(0, CoachOffsets.IFormRun), equals('11'));
    });

    test('T-C13 SplitbackRun and EmptyRun are independent (offset bug fixed)', () {
      tool.SetCoachAttribute(0, CoachOffsets.SplitbackRun, '77');
      tool.SetCoachAttribute(0, CoachOffsets.EmptyRun, '33');
      expect(tool.GetCoachAttribute(0, CoachOffsets.SplitbackRun), equals('77'));
      expect(tool.GetCoachAttribute(0, CoachOffsets.EmptyRun), equals('33'));
    });

    // T-C14 — InputParser non-string fields round-trip
    test('T-C14 InputParser Coach line sets numeric fields; save→reload verifies', () async {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
      fresh.CoachKey = 'Coach,Team,Overall,QB,Wins,Losses';
      expect(StaticUtils.Errors, isEmpty,
          reason: 'CoachKey setup must not produce errors');

      final parser = InputParser(fresh);
      parser.ProcessLine('CoachKEY=Coach,Team,Overall,QB,Wins,Losses');
      parser.ProcessLine('Coach,49ers,75,88,12,5');

      expect(fresh.GetCoachAttribute(0, CoachOffsets.Overall), equals('75'));
      expect(fresh.GetCoachAttribute(0, CoachOffsets.QB), equals('88'));
      expect(fresh.GetCoachAttribute(0, CoachOffsets.Wins), equals('12'));

      // Save → reload → verify
      final tempPath =
          '${Directory.systemTemp.path}/nfl2k5_coach_tc14.dat';
      fresh.SaveFile(tempPath);

      final reloaded = GamesaveTool();
      reloaded.LoadSaveFile(tempPath);

      expect(reloaded.GetCoachAttribute(0, CoachOffsets.Overall), equals('75'));
      expect(reloaded.GetCoachAttribute(0, CoachOffsets.QB), equals('88'));
      expect(reloaded.GetCoachAttribute(0, CoachOffsets.Wins), equals('12'));

      File(tempPath).deleteSync();
    });
  });

  // T-C15 — Ground-truth coach values (Base2004Fran_Orig.zip)
  //
  // Manually gathered expected values for every numeric coach field for two
  // coaches: Dennis Erickson (49ers, idx 0) and Tony Dungy (Colts, idx 10).
  // Exercises all playcalling fields whose offsets were fixed in Issue C
  // (SplitbackRun 0x84, IFormRun 0x85 — were both wrongly set to 0x83/0x87).
  group('T-C15 – Ground-truth coach values – Base2004Fran_Orig.zip', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      final ok = tool.LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
      expect(ok, isTrue, reason: 'Base2004Fran_Orig.zip must load successfully');
      tool.CoachKey = tool.CoachKeyAll;
    });

    // Convenience: team index 0 is always 49ers.
    const int niners = 0;

    test('Wins = 38', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.Wins), equals('38'));
    });

    test('Losses = 42', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.Losses), equals('42'));
    });

    test('Ties = 0', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.Ties), equals('0'));
    });

    test('SeasonsWithTeam = 1', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.SeasonsWithTeam), equals('1'));
    });

    test('totalSeasons = 5', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.totalSeasons), equals('5'));
    });

    test('WinningSeasons = 0', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.WinningSeasons), equals('0'));
    });

    test('SuperBowls = 0', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.SuperBowls), equals('0'));
    });

    test('SuperBowlWins = 0', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.SuperBowlWins), equals('0'));
    });

    test('SuperBowlLosses = 0', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.SuperBowlLosses), equals('0'));
    });

    test('PlayoffWins = 0', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.PlayoffWins), equals('0'));
    });

    test('PlayoffLosses = 0', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.PlayoffLosses), equals('0'));
    });

    test('Overall = 60', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.Overall), equals('60'));
    });

    test('OvrallOffense = 69', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.OvrallOffense), equals('69'));
    });

    test('RushFor = 61', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.RushFor), equals('61'));
    });

    test('PassFor = 76', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.PassFor), equals('76'));
    });

    test('OverallDefense = 69', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.OverallDefense), equals('69'));
    });

    test('PassRush = 69', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.PassRush), equals('69'));
    });

    test('PassCoverage = 76', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.PassCoverage), equals('76'));
    });

    test('QB = 72', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.QB), equals('72'));
    });

    test('RB = 76', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.RB), equals('76'));
    });

    test('TE = 75', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.TE), equals('75'));
    });

    test('WR = 74', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.WR), equals('74'));
    });

    test('OL = 68', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.OL), equals('68'));
    });

    test('DL = 77', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.DL), equals('77'));
    });

    test('LB = 80', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.LB), equals('80'));
    });

    test('SpecialTeams = 76', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.SpecialTeams), equals('76'));
    });

    test('Professionalism = 84', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.Professionalism), equals('84'));
    });

    test('Preparation = 83', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.Preparation), equals('83'));
    });

    test('Conditioning = 76', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.Conditioning), equals('76'));
    });

    test('Motivation = 75', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.Motivation), equals('75'));
    });

    test('Leadership = 76', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.Leadership), equals('76'));
    });

    test('Discipline = 69', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.Discipline), equals('69'));
    });

    test('Respect = 70', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.Respect), equals('70'));
    });

    test('PlaycallingRun = 45', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.PlaycallingRun), equals('45'));
    });

    // The following two pairs share enum offsets (Issue C / potential bug):
    // ShotgunRun and IFormRun both map to 0x83 — expected values differ (15 vs 14).
    // If these fail it confirms the offsets in CoachOffsets are wrong.
    test('ShotgunRun = 15', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.ShotgunRun), equals('15'));
    });

    test('IFormRun = 14', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.IFormRun), equals('14'));
    });

    // SplitbackRun and EmptyRun both map to 0x87 — expected values differ (10 vs 9).
    test('SplitbackRun = 10', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.SplitbackRun), equals('10'));
    });

    test('EmptyRun = 9', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.EmptyRun), equals('9'));
    });

    test('ShotgunPass = 3', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.ShotgunPass), equals('3'));
    });

    test('SplitbackPass = 12', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.SplitbackPass), equals('12'));
    });

    test('IFormPass = 40', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.IFormPass), equals('40'));
    });

    test('LoneBackPass = 38', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.LoneBackPass), equals('38'));
    });

    test('EmptyPass = 7', () {
      expect(tool.GetCoachAttribute(niners, CoachOffsets.EmptyPass), equals('7'));
    });
  });

  // T-C16 — Tony Dungy (Colts, idx 10) ground-truth values – Base2004Fran_Orig.zip
  group('T-C16 – Tony Dungy (Colts) ground-truth values – Base2004Fran_Orig.zip', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      final ok = tool.LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
      expect(ok, isTrue, reason: 'Base2004Fran_Orig.zip must load successfully');
      tool.CoachKey = tool.CoachKeyAll;
    });

    const int colts = 10;

    test('Wins = 76', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.Wins), equals('76'));
    });

    test('Losses = 52', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.Losses), equals('52'));
    });

    test('Ties = 0', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.Ties), equals('0'));
    });

    test('SeasonsWithTeam = 2', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.SeasonsWithTeam), equals('2'));
    });

    test('totalSeasons = 8', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.totalSeasons), equals('8'));
    });

    test('WinningSeasons = 6', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.WinningSeasons), equals('6'));
    });

    test('SuperBowls = 0', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.SuperBowls), equals('0'));
    });

    test('SuperBowlWins = 0', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.SuperBowlWins), equals('0'));
    });

    test('SuperBowlLosses = 0', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.SuperBowlLosses), equals('0'));
    });

    test('PlayoffWins = 4', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.PlayoffWins), equals('4'));
    });

    test('PlayoffLosses = 6', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.PlayoffLosses), equals('6'));
    });

    test('Overall = 84', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.Overall), equals('84'));
    });

    test('OvrallOffense = 89', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.OvrallOffense), equals('89'));
    });

    test('RushFor = 84', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.RushFor), equals('84'));
    });

    test('PassFor = 97', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.PassFor), equals('97'));
    });

    test('OverallDefense = 88', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.OverallDefense), equals('88'));
    });

    test('PassRush = 83', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.PassRush), equals('83'));
    });

    test('PassCoverage = 80', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.PassCoverage), equals('80'));
    });

    test('QB = 91', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.QB), equals('91'));
    });

    test('RB = 84', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.RB), equals('84'));
    });

    test('TE = 84', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.TE), equals('84'));
    });

    test('WR = 91', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.WR), equals('91'));
    });

    test('OL = 84', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.OL), equals('84'));
    });

    test('DL = 77', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.DL), equals('77'));
    });

    test('LB = 82', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.LB), equals('82'));
    });

    test('SpecialTeams = 62', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.SpecialTeams), equals('62'));
    });

    test('Professionalism = 92', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.Professionalism), equals('92'));
    });

    test('Preparation = 92', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.Preparation), equals('92'));
    });

    test('Conditioning = 91', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.Conditioning), equals('91'));
    });

    test('Motivation = 83', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.Motivation), equals('83'));
    });

    test('Leadership = 84', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.Leadership), equals('84'));
    });

    test('Discipline = 83', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.Discipline), equals('83'));
    });

    test('Respect = 91', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.Respect), equals('91'));
    });

    test('PlaycallingRun = 40', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.PlaycallingRun), equals('40'));
    });

    test('ShotgunRun = 40', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.ShotgunRun), equals('40'));
    });

    test('IFormRun = 1', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.IFormRun), equals('1'));
    });

    test('SplitbackRun = 12', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.SplitbackRun), equals('12'));
    });

    test('EmptyRun = 1', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.EmptyRun), equals('1'));
    });

    test('ShotgunPass = 40', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.ShotgunPass), equals('40'));
    });

    test('SplitbackPass = 5', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.SplitbackPass), equals('5'));
    });

    test('IFormPass = 7', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.IFormPass), equals('7'));
    });

    test('LoneBackPass = 37', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.LoneBackPass), equals('37'));
    });

    test('EmptyPass = 11', () {
      expect(tool.GetCoachAttribute(colts, CoachOffsets.EmptyPass), equals('11'));
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

  // ---------------------------------------------------------------------------
  // T-SCH – Schedule round-trip: apply 2025 regular-season schedule and read
  // it back, verifying teams and time slots are preserved.
  // ---------------------------------------------------------------------------
  group('T-SCH – Schedule round-trip (2025 regular season)', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
      final input =
          File(testFile('2025_schedule.nfl2k5')).readAsStringSync();
      tool.ApplySchedule(input.split('\n'));
    });

    test('T-SCH1: output contains all 17 regular-season week headers', () {
      final out = tool.GetSchedule();
      for (int wk = 1; wk <= 17; wk++) {
        expect(out, contains('WEEK $wk '),
            reason: 'WEEK $wk header missing from GetSchedule output');
      }
    });

    test('T-SCH2: week 1 has 16 games', () {
      final out = tool.GetSchedule();
      expect(out, contains('WEEK 1  [16 games]'));
    });

    /*test('T-SCH3: every input game (teams + day + hour) appears in output', () {
      SchedulerHelper.showDateTime = true;
      addTearDown(() => SchedulerHelper.showDateTime = false);

      // Normalize output: collapse runs of whitespace to a single space.
      String output = tool.GetSchedule().replaceAll(RegExp(r' {2,}'), ' ');

      // Strip minutes from every time token so "4:25" and "4:00" both become "4".
      // The last real game before null-filled bye slots has its minute zeroed
      // by the null-game writer (ScheduleGameByIndex writes 0x00 two bytes
      // before the null slot, landing on the previous game's minute field).
      // Matching on teams + day-of-week + hour is still a strong verification.
      String stripMinutes(String s) => s.replaceAllMapped(
          RegExp(r'(\d{1,2}):\d{2}'), (m) => m.group(1)!);

      output = stripMinutes(output);

      final inputLines = File(testFile('2025_schedule.nfl2k5'))
          .readAsStringSync()
          .split('\n')
          .map((l) => stripMinutes(l.trim()))
          .where((l) => l.contains(' at '))
          .toList();

      for (final game in inputLines) {
        expect(output.contains(game), isTrue,
            reason: 'Input game "$game" not found in schedule output');
        // Remove this occurrence so the same output line cannot satisfy
        // two different input games.
        output = output.replaceFirst(game, '');
      }
    });

    // T-SCH4: empty playoff weeks are hidden by default.
    test('T-SCH4: no playoff section in output by default (empty playoff weeks hidden)', () {
      expect(tool.GetSchedule(), isNot(contains('--- PLAYOFFS ---')));
    });

    // T-SCH5: showAllPlayoffGames=true forces the playoff section to appear.
    test('T-SCH5: showAllPlayoffGames=true shows playoff section even when empty', () {
      SchedulerHelper.showAllPlayoffGames = true;
      addTearDown(() => SchedulerHelper.showAllPlayoffGames = false);
      expect(tool.GetSchedule(), contains('--- PLAYOFFS ---'));
    });*/
  });

  // ---------------------------------------------------------------------------
  // T-SCH-PO – Playoff schedule display with real playoff data
  // ---------------------------------------------------------------------------
  /*
  group('T-SCH-PO – Playoff schedule display', () {
    // poW1: Wild Card games scheduled; weeks 19–22 are unresolved.
    // poW4: Through Pro Bowl; week 22 (Super Bowl) has 0 games.

    // T-SCH-PO1: default — a save with real playoff games shows the playoff section.
    test('T-SCH-PO1: playoff section shown by default when games are present', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile('playoffSchedule/poW1.zip'));
      expect(tool.GetSchedule(), contains('--- PLAYOFFS ---'));
    });

    // T-SCH-PO2: default — Wild Card game content is visible.
    test('T-SCH-PO2: Wild Card games appear in default output', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile('playoffSchedule/poW1.zip'));
      final out = tool.GetSchedule();
      expect(out, contains('texans at ravens'));
      expect(out, contains('chiefs at colts'));
      expect(out, contains('seahawks at cowboys'));
      expect(out, contains('eagles at packers'));
    });

    // T-SCH-PO3: default — week 22 (Super Bowl, 0 games) is hidden.
    test('T-SCH-PO3: Super Bowl week hidden by default when no game is set', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile('playoffSchedule/poW4.zip'));
      expect(tool.GetSchedule(), isNot(contains('WEEK 22')));
    });

    // T-SCH-PO4: showAllPlayoffGames=true — week 22 is shown even with 0 games.
    test('T-SCH-PO4: showAllPlayoffGames=true shows empty Super Bowl week', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile('playoffSchedule/poW4.zip'));
      SchedulerHelper.showAllPlayoffGames = true;
      addTearDown(() => SchedulerHelper.showAllPlayoffGames = false);
      expect(tool.GetSchedule(), contains('WEEK 22'));
    });
  });
*/
  // ---------------------------------------------------------------------------
  // T-APF – ApplyFormula / GetPlayersByFormula correctness
  // ---------------------------------------------------------------------------
  group('T-APF – GetPlayersByFormula attribute substitution', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile('Week_6_2024.zip'));
    });

    // T-APF-1: REGRESSION — SubstituteRandom must receive evaluationString (the
    // result of SubstituteAttributesForValues), not the raw formula. With the bug
    // the literal string "Strength" is never replaced with the player's value, so
    // _EvaluateExpression returns false for every player → empty list.
    test('T-APF-1: Strength > -1 matches all QBs (attribute substitution regression)', () {
      final allQBs = tool.GetPlayersByFormula('true', ['QB']);
      final strQBs = tool.GetPlayersByFormula('Strength > -1', ['QB']);
      expect(strQBs, isNotEmpty,
          reason: 'attribute substitution discarded by bug → empty list');
      expect(strQBs.length, equals(allQBs.length),
          reason: 'every QB has Strength > -1 so counts must match');
    });

    // T-APF-2: a more restrictive threshold returns fewer matches than a loose one.
    test('T-APF-2: Strength < 50 returns fewer players than Strength < 100', () {
      final low = tool.GetPlayersByFormula('Strength < 50', []);
      final high = tool.GetPlayersByFormula('Strength < 100', []);
      expect(low.length, lessThan(high.length));
    });

    // T-APF-3: complementary thresholds partition the full roster exactly.
    test('T-APF-3: Strength < 50 and Strength >= 50 partition all players', () {
      final low  = tool.GetPlayersByFormula('Strength < 50', []);
      final high = tool.GetPlayersByFormula('Strength >= 50', []);
      final all  = tool.GetPlayersByFormula('true', []);
      expect(low.length + high.length, equals(all.length));
    });

    // T-APF-4: position filter reduces the result set vs. no filter.
    test('T-APF-4: QB filter produces fewer results than no filter', () {
      final qbs = tool.GetPlayersByFormula('true', ['QB']);
      final all = tool.GetPlayersByFormula('true', []);
      expect(qbs.length, lessThan(all.length));
    });

    // T-APF-5: ApplyFormula dry run returns a non-null CSV-style result.
    // Use Strength < 80 — several QBs in the Week_6_2024 roster fall below 80.
    test('T-APF-5: ApplyFormula dry run returns result string', () {
      final result = tool.ApplyFormula(
          'Strength < 80', 'Strength', '80', ['QB'], FormulaMode.Normal, false);
      expect(result, isNotNull);
      expect(result, contains('#Players affected'));
    });

    // T-APF-6: 'always' is an alias for 'true' inside ApplyFormula.
    test('T-APF-6: always alias selects same players as true', () {
      final viaAlways = tool.ApplyFormula(
          'always', 'Strength', '60', ['QB'], FormulaMode.Normal, false);
      final viaTrue = tool.ApplyFormula(
          'true', 'Strength', '60', ['QB'], FormulaMode.Normal, false);
      expect(viaAlways, isNotNull);
      expect(viaTrue, isNotNull);
      final countAlways = RegExp(r'#Players affected = (\d+)').firstMatch(viaAlways!)!.group(1);
      final countTrue  = RegExp(r'#Players affected = (\d+)').firstMatch(viaTrue!)!.group(1);
      expect(countAlways, equals(countTrue));
    });

    // T-APF-7: compound 'and' selects the intersection of two individual filters.
    test('T-APF-7: compound and formula selects intersection', () {
      final speedHigh    = tool.GetPlayersByFormula('Speed > 80', []);
      final agilityHigh  = tool.GetPlayersByFormula('Agility > 80', []);
      final both         = tool.GetPlayersByFormula('Speed > 80 and Agility > 80', []);
      expect(both.length, lessThanOrEqualTo(speedHigh.length));
      expect(both.length, lessThanOrEqualTo(agilityHigh.length));
      for (final p in both) {
        expect(speedHigh, contains(p));
        expect(agilityHigh, contains(p));
      }
    });

    // T-APF-8: '&&' is preprocessed to 'and' and produces the same result.
    test('T-APF-8: && preprocesses to and — same result as and', () {
      final andResult  = tool.GetPlayersByFormula('Speed > 80 and Agility > 80', []);
      final ampResult  = tool.GetPlayersByFormula('Speed > 80&&Agility > 80', []);
      expect(ampResult.length, equals(andResult.length));
    });

    // T-APF-9: compound 'or' selects the union — at least as large as either alone.
    test('T-APF-9: compound or formula selects union', () {
      final speedLow   = tool.GetPlayersByFormula('Speed < 50', []);
      final agilityLow = tool.GetPlayersByFormula('Agility < 50', []);
      final either     = tool.GetPlayersByFormula('Speed < 50 or Agility < 50', []);
      expect(either.length, greaterThanOrEqualTo(speedLow.length));
      expect(either.length, greaterThanOrEqualTo(agilityLow.length));
    });

    // T-APF-10: '||' preprocesses to 'or' and produces the same result.
    test('T-APF-10: || preprocesses to or — same result as or', () {
      final orResult   = tool.GetPlayersByFormula('Speed < 50 or Agility < 50', []);
      final pipeResult = tool.GetPlayersByFormula('Speed < 50||Agility < 50', []);
      expect(pipeResult.length, equals(orResult.length));
    });

    // T-APF-11: empty formula → GetPlayersByFormula returns empty list.
    test('T-APF-11: empty formula returns empty list', () {
      expect(tool.GetPlayersByFormula('', []), isEmpty);
    });

    // T-APF-12: formula that matches nobody → ApplyFormula returns null.
    test('T-APF-12: no-match formula returns null from ApplyFormula', () {
      // No player has Strength > 200 (byte attribute, max 255, game values 0–99).
      final result = tool.ApplyFormula(
          'Strength > 200', 'Strength', '50', [], FormulaMode.Normal, false);
      expect(result, isNull);
    });

    // T-APF-13: Random_min_max is substituted with a value in [min, max) before
    // evaluation. A formula 'Random_1_100 > 0' should always be true, so every
    // player in the roster matches.
    test('T-APF-13: Random_min_max substitution produces values in range', () {
      final all    = tool.GetPlayersByFormula('true', []);
      final random = tool.GetPlayersByFormula('Random_1_100 > 0', []);
      expect(random.length, equals(all.length),
          reason: 'Random_1_100 picks 1–99, always > 0');
    });

    // T-APF-14: '>=' works and matches the same set as '> (threshold-1)'.
    test('T-APF-14: >= matches same players as > threshold-1', () {
      final geResult  = tool.GetPlayersByFormula('Strength >= 50', []);
      final gtResult  = tool.GetPlayersByFormula('Strength > 49', []);
      expect(geResult.length, equals(gtResult.length));
      expect(geResult.toSet(), equals(gtResult.toSet()));
    });

    // T-APF-15: '<=' works and matches the same set as '< (threshold+1)'.
    test('T-APF-15: <= matches same players as < threshold+1', () {
      final leResult  = tool.GetPlayersByFormula('Strength <= 49', []);
      final ltResult  = tool.GetPlayersByFormula('Strength < 50', []);
      expect(leResult.length, equals(ltResult.length));
      expect(leResult.toSet(), equals(ltResult.toSet()));
    });

    // T-APF-16: '!=' works — the union of '< N' and '> N' equals '!= N'.
    test('T-APF-16: != matches all players except those with exactly that value', () {
      // Pick a threshold that some players actually hit so != excludes someone.
      // Use Strength < 50 count to confirm != 50 matches everyone except Strength=50.
      final neResult  = tool.GetPlayersByFormula('Strength != 50', []);
      final eqResult  = tool.GetPlayersByFormula('Strength > 49 and Strength < 51', []);
      final all       = tool.GetPlayersByFormula('true', []);
      expect(neResult.length + eqResult.length, equals(all.length));
    });

    // T-APF-17: FormulaMode.Add increments each matched player's attribute by the
    // given integer (applyChanges=true on a fresh copy of the roster).
    test('T-APF-17: FormulaMode.Add increments attribute value per player', () {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile('Week_6_2024.zip'));
      final qbs = fresh.GetPlayersByFormula('true', ['QB']);
      final firstQB = qbs.first;
      final before = int.parse(fresh.GetPlayerField(firstQB, 'Strength'));
      fresh.ApplyFormula('true', 'Strength', '5', ['QB'], FormulaMode.Add, true);
      final after = int.parse(fresh.GetPlayerField(firstQB, 'Strength'));
      expect(after, equals(before + 5));
    });

    // T-APF-18: FormulaMode.Percent multiplies each player's attribute by the given
    // percentage (applyChanges=true on a fresh copy of the roster).
    test('T-APF-18: FormulaMode.Percent scales attribute by percentage', () {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile('Week_6_2024.zip'));
      final qbs = fresh.GetPlayersByFormula('true', ['QB']);
      final firstQB = qbs.first;
      final before = int.parse(fresh.GetPlayerField(firstQB, 'Strength'));
      fresh.ApplyFormula('true', 'Strength', '50', ['QB'], FormulaMode.Percent, true);
      final after = int.parse(fresh.GetPlayerField(firstQB, 'Strength'));
      expect(after, equals((before * 0.50).toInt()));
    });

    // T-APF-19: FormulaMode.Percent multiplies each player's attribute by the given
    // percentage 
    test('T-APF-19: FormulaMode.Percent scales attribute by percentage', () {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile('Week_6_2024.zip'));
      final qbs = fresh.GetPlayersByFormula('true', ['QB']);
      final firstQB = qbs.first;
      final before = int.parse(fresh.GetPlayerField(firstQB, 'Strength'));
      InputParser parser = InputParser(fresh);
      parser.ProcessLine("ApplyFormula('Strength > 5','Strength',50, [QB], Percent)");
      final after = int.parse(fresh.GetPlayerField(firstQB, 'Strength'));
      expect(after, equals((before * 0.50).toInt()));
    });

    // T-APF-20: FormulaMode.Percent multiplies each player's attribute by the given
    // percentage 
    test('T-APF-20: FormulaMode.Percent scales speed attribute by percentage', () {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile('Week_6_2024.zip'));
      final cbs = fresh.GetPlayersByFormula('Speed > 5', ['CB']);
      final firstCB = cbs.first;
      final before = int.parse(fresh.GetPlayerField(firstCB, 'Speed'));
      fresh.ApplyFormula('Speed > 5', 'Speed', '50', ['CB'], FormulaMode.Percent, true);
      final after = int.parse(fresh.GetPlayerField(firstCB, 'Speed'));
      expect(after, equals((before * 0.50).toInt()));
    });

    // T-APF-21: FormulaMode.Percent multiplies each player's attribute by the given
    // percentage 
    test('T-APF-21: FormulaMode.Percent scales speed attribute by percentage', () {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile('Week_6_2024.zip'));
      final cbs = fresh.GetPlayersByFormula('Speed > 5', ['CB']);
      final firstCB = cbs.first;
      final before = int.parse(fresh.GetPlayerField(firstCB, 'Speed'));
      InputParser parser = InputParser(fresh);
      parser.ProcessLine("ApplyFormula('Speed > 20','Speed',50, [CB], Percent)");
      //fresh.ApplyFormula('Speed > 5', 'Speed', '50', ['CB'], FormulaMode.Percent, true);
      final after = int.parse(fresh.GetPlayerField(firstCB, 'Speed'));
      expect(after, equals((before * 0.50).toInt()));
    });


    // T-APF-22: FormulaMode Increment adds each player's attribute by the given
    // amount
    test('T-APF-22: FormulaMode Increment Adds to the player value', () {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile('Week_6_2024.zip'));
      final cbs = fresh.GetPlayersByFormula('Speed > 5', ['CB']);
      final firstCB = cbs.first;
      final before = int.parse(fresh.GetPlayerField(firstCB, 'Speed'));
      InputParser parser = InputParser(fresh);
      parser.ProcessLine("ApplyFormula('Speed > 20','Speed',1, [CB], Increment)");
      final after = int.parse(fresh.GetPlayerField(firstCB, 'Speed'));
      expect(after, equals((before + 1 ).toInt()));
    });
   
    // T-APF-23: FormulaMode Increment adds each player's attribute by the given
    // amount
    test('T-APF-23: FormulaMode Increment Adds to the player value', () {
      final fresh = GamesaveTool();
      fresh.LoadSaveFile(testFile('Week_6_2024.zip'));
      final cbs = fresh.GetPlayersByFormula('Speed > 5', ['CB']);
      final firstCB = cbs.first;
      final before = int.parse(fresh.GetPlayerField(firstCB, 'Speed'));
      InputParser parser = InputParser(fresh);
      parser.ProcessLine("ApplyFormula('Speed > 20','Speed',-1, [CB], Increment)");
      final after = int.parse(fresh.GetPlayerField(firstCB, 'Speed'));
      expect(after, equals((before - 1 ).toInt()));
    });
   

  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Parses a schedule string into week-indexed lists of normalized game strings.
/// Each entry: "away at home" or "away at home dow H:MM".
/// Normalises whitespace so both input (single space) and output (double space
/// before dow) produce the same string for comparison.
Map<int, List<String>> _parseScheduleGames(String text) {
  final result = <int, List<String>>{};
  int currentWeek = 0;
  final weekRe = RegExp(r'WEEK\s+(\d+)', caseSensitive: false);
  // [0-9a-z_]+ covers team tokens including '49ers' and 'free_agents'.
  final gameRe = RegExp(
    r'([0-9a-z_]+)\s+at\s+([0-9a-z_]+)'
    r'(?:\s+(sun|mon|tue|wed|thu|fri|sat))?'
    r'(?:\s+(\d{1,2}):(\d{2}))?',
  );
  for (final line in text.split('\n')) {
    final wm = weekRe.firstMatch(line);
    if (wm != null) {
      currentWeek = int.parse(wm.group(1)!);
      continue;
    }
    final gm = gameRe.firstMatch(line);
    if (gm == null || currentWeek == 0) continue;
    final away = gm.group(1)!;
    final home = gm.group(2)!;
    final dow  = gm.group(3);
    final hr   = gm.group(4);
    final min  = gm.group(5);
    String entry = '$away at $home';
    if (dow != null) entry += ' $dow';
    if (hr  != null) entry += ' $hr:$min';
    result.putIfAbsent(currentWeek, () => []).add(entry);
  }
  return result;
}
