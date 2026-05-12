// Stress tests for string section boundary safety and data integrity.
//
// Four groups:
//   ST-1  S3b overflow guard    — add 2 chars to every player; verify depth
//                                 chart unchanged and errors reported
//   ST-2  S3b grow/shrink cycle — grow then shrink 50 player names; verify
//                                 surrounding data untouched
//   ST-3  S2 grow/shrink cycle  — shorten then restore all 32 coach last names
//   ST-4  Cross-section safety  — interleaved S2 + S3b edits; verify neither
//                                 section corrupts the other
import 'dart:io';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/gamesave_tool_io.dart';
import 'package:test/test.dart';

String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

const String _baseRoster = 'BaseRoster/SAVEGAME.DAT';
const String _franchise  = 'Base2004Fran_Orig.zip';

/// Snapshot [count] bytes starting at [start] from [tool]'s GameSaveData.
List<int> snapshot(GamesaveTool tool, int start, int count) =>
    tool.GameSaveData!.sublist(start, start + count).toList();

void main() {
  // ─── ST-1: S3b overflow guard ────────────────────────────────────────────────
  //
  // BaseRoster S3b has ~1,515 bytes of slack.  Adding 2 chars (+4 bytes each)
  // to every player's last name requires 1,943 × 4 = 7,772 bytes — far more
  // than available.  The overflow guard must:
  //   • fire StaticUtils.AddError for each rejected write
  //   • leave the depth-chart section (immediately after mModifiableNameSectionEnd)
  //     completely unchanged
  //   • successfully extend names while slack remains, stop once it runs out

  group('ST-1 S3b overflow guard — add 2 chars to every player', () {
    late GamesaveTool tool;
    late List<int> depthChartBefore;
    late int boundary;
    late List<String> originalLastNames;
    const int depthSnapSize = 256;

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_baseRoster));
      boundary = tool.mModifiableNameSectionEnd;

      // Snapshot the section immediately after S3b (depth chart area)
      depthChartBefore = snapshot(tool, boundary, depthSnapSize);

      // Record all last names before edits
      originalLastNames = [
        for (int i = 0; i < tool.mMaxPlayers; i++)
          tool.GetPlayerLastName(i)
      ];

      StaticUtils.Errors.clear();

      // Attempt to add "ZZ" to every player's last name
      for (int i = 0; i < tool.mMaxPlayers; i++) {
        tool.SetPlayerLastName(i, originalLastNames[i] + 'ZZ', false);
      }
    });

    test('depth chart bytes are unchanged after attempted overflow', () {
      final depthChartAfter = snapshot(tool, boundary, depthSnapSize);
      expect(depthChartAfter, equals(depthChartBefore),
          reason: 'Bytes immediately after mModifiableNameSectionEnd must not '
              'be modified by player name writes');
    });

    test('overflow guard fired — StaticUtils.Errors is non-empty', () {
      expect(StaticUtils.Errors, isNotEmpty,
          reason: 'Guard must add errors when the name section is full');
    });

    test('some players got their names extended (slack was used)', () {
      final extended = [
        for (int i = 0; i < tool.mMaxPlayers; i++)
          if (tool.GetPlayerLastName(i) == originalLastNames[i] + 'ZZ') i
      ];
      expect(extended, isNotEmpty,
          reason: 'Players within available slack must have been extended');
    });

    test('players whose write was rejected have their original name unchanged', () {
      // Once the guard fires, all subsequent writes are rejected.
      // Every rejected player must still have their original last name.
      int rejected = 0;
      for (int i = 0; i < tool.mMaxPlayers; i++) {
        final current = tool.GetPlayerLastName(i);
        if (current != originalLastNames[i] + 'ZZ') {
          expect(current, equals(originalLastNames[i]),
              reason: 'Player $i: rejected write must leave name unchanged');
          rejected++;
        }
      }
      expect(rejected, greaterThan(0),
          reason: 'At least some writes must have been rejected (not enough slack)');
    });

    test('errors count matches number of rejected writes', () {
      int rejected = 0;
      for (int i = 0; i < tool.mMaxPlayers; i++) {
        if (tool.GetPlayerLastName(i) != originalLastNames[i] + 'ZZ') {
          rejected++;
        }
      }
      expect(StaticUtils.Errors.length, equals(rejected),
          reason: 'One error per rejected write');
    });
  });

  // ─── ST-2: S3b grow/shrink cycle ─────────────────────────────────────────────
  //
  // Grow 50 player last names by 2 chars, then shrink them back.
  // Verify surrounding players are undisturbed throughout, and that the
  // depth chart section is clean after both operations.

  group('ST-2 S3b grow/shrink cycle', () {
    const int kFirst = 10;   // first player index to edit
    const int kCount = 50;   // number of players to edit
    const int kLast  = kFirst + kCount; // exclusive upper bound

    late GamesaveTool tool;
    late List<int> depthChartBefore;
    late int boundary;

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_baseRoster));
      boundary = tool.mModifiableNameSectionEnd;
      depthChartBefore = snapshot(tool, boundary, 256);
      StaticUtils.Errors.clear();
    });

    test('grow: extend players $kFirst–${kLast - 1} by 2 chars', () {
      // Snapshot neighbours outside the edit range
      final before0 = tool.GetPlayerLastName(kFirst - 1);
      final beforeEnd = tool.GetPlayerLastName(kLast);

      for (int i = kFirst; i < kLast; i++) {
        final orig = tool.GetPlayerLastName(i);
        tool.SetPlayerLastName(i, orig + 'ZZ', false);
        expect(tool.GetPlayerLastName(i), equals(orig + 'ZZ'),
            reason: 'Player $i last name must be extended');
      }
      expect(StaticUtils.Errors, isEmpty,
          reason: 'No errors expected — $kCount × 4 bytes is well within 1,515-byte slack');
      expect(tool.GetPlayerLastName(kFirst - 1), equals(before0),
          reason: 'Player ${kFirst - 1} must be unaffected by grow');
      expect(tool.GetPlayerLastName(kLast), equals(beforeEnd),
          reason: 'Player $kLast must be unaffected by grow');
    });

    test('shrink: restore players $kFirst–${kLast - 1} to original names', () {
      for (int i = kFirst; i < kLast; i++) {
        final extended = tool.GetPlayerLastName(i);
        final original = extended.substring(0, extended.length - 2);
        tool.SetPlayerLastName(i, original, false);
        expect(tool.GetPlayerLastName(i), equals(original),
            reason: 'Player $i last name must be restored');
      }
      expect(StaticUtils.Errors, isEmpty);
    });

    test('depth chart unchanged after grow/shrink cycle', () {
      final after = snapshot(tool, boundary, 256);
      expect(after, equals(depthChartBefore),
          reason: 'Depth chart bytes must be unchanged after a full grow/shrink cycle');
    });

    test('save/reload: all 50 restored names persist', () async {
      // Reload a fresh grow to verify round-trip (shrink restored to original)
      final originals = [
        for (int i = kFirst; i < kLast; i++) tool.GetPlayerLastName(i)
      ];
      final tmp = '${Directory.systemTemp.path}/nfl2k5_stress_st2.dat';
      tool.SaveFile(tmp);
      final r = GamesaveTool()..LoadSaveFile(tmp);
      for (int i = kFirst; i < kLast; i++) {
        expect(r.GetPlayerLastName(i), equals(originals[i - kFirst]),
            reason: 'Player $i restored name must survive save/reload');
      }
      File(tmp).deleteSync();
    });
  });

  // ─── ST-3: S2 coach string grow/shrink cycle ─────────────────────────────────
  //
  // Shorten every coach's last name by 1 char (building up slack), then grow
  // them all back to their original length.  Verify all 32 coaches are intact
  // and that S3a (immediately after S2) is undisturbed throughout.

  group('ST-3 S2 coach string grow/shrink cycle (all 32 coaches)', () {
    late GamesaveTool tool;
    late List<String> originalFirst;
    late List<String> originalLast;
    late List<String> s3aSnapshotBefore;

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));
      StaticUtils.Errors.clear();

      originalFirst = [
        for (int i = 0; i < 32; i++)
          tool.GetCoachAttribute(i, CoachOffsets.FirstName)
      ];
      originalLast = [
        for (int i = 0; i < 32; i++)
          tool.GetCoachAttribute(i, CoachOffsets.LastName)
      ];
      // Snapshot S3a (all 32 team nicknames) — sits right after S2
      s3aSnapshotBefore = [
        for (int i = 0; i < 32; i++)
          tool.GetTeamString(i, TeamDataOffsets.Nickname)
      ];
    });

    test('shrink: drop last char from every coach last name', () {
      for (int i = 0; i < 32; i++) {
        final orig = originalLast[i];
        if (orig.length < 2) continue; // skip if already 1 char
        tool.SetCoachAttribute(i, CoachOffsets.LastName,
            orig.substring(0, orig.length - 1));
      }
      expect(StaticUtils.Errors, isEmpty,
          reason: 'Shortening must never fail');
      // First names must be untouched
      for (int i = 0; i < 32; i++) {
        expect(tool.GetCoachAttribute(i, CoachOffsets.FirstName),
            equals(originalFirst[i]),
            reason: 'Coach $i FirstName must be unaffected by shrink');
      }
    });

    test('S3a (team nicknames) unchanged after S2 shrink', () {
      for (int i = 0; i < 32; i++) {
        expect(tool.GetTeamString(i, TeamDataOffsets.Nickname),
            equals(s3aSnapshotBefore[i]),
            reason: 'Team $i Nickname must be unchanged after S2 shrink');
      }
    });

    test('grow: restore every coach last name to original', () {
      for (int i = 0; i < 32; i++) {
        tool.SetCoachAttribute(i, CoachOffsets.LastName, originalLast[i]);
        expect(tool.GetCoachAttribute(i, CoachOffsets.LastName),
            equals(originalLast[i]),
            reason: 'Coach $i LastName must be restored');
      }
      expect(StaticUtils.Errors, isEmpty,
          reason: 'Growing back within freed slack must not fail');
    });

    test('S3a unchanged after full S2 grow/shrink cycle', () {
      for (int i = 0; i < 32; i++) {
        expect(tool.GetTeamString(i, TeamDataOffsets.Nickname),
            equals(s3aSnapshotBefore[i]),
            reason: 'Team $i Nickname must survive S2 grow/shrink cycle');
      }
    });

    test('save/reload: all 32 coach names intact after cycle', () async {
      final tmp = '${Directory.systemTemp.path}/nfl2k5_stress_st3.dat';
      tool.SaveFile(tmp);
      final r = GamesaveTool()..LoadSaveFile(tmp);
      for (int i = 0; i < 32; i++) {
        expect(r.GetCoachAttribute(i, CoachOffsets.FirstName),
            equals(originalFirst[i]),
            reason: 'Coach $i FirstName must survive save/reload');
        expect(r.GetCoachAttribute(i, CoachOffsets.LastName),
            equals(originalLast[i]),
            reason: 'Coach $i LastName must survive save/reload');
      }
      File(tmp).deleteSync();
    });
  });

  // ─── ST-4: Cross-section safety ──────────────────────────────────────────────
  //
  // Interleave S2 (coach string) and S3b (player name) edits in the same
  // session.  Verify that neither section corrupts the other and that S3a
  // (team nicknames) is undisturbed throughout.

  group('ST-4 Cross-section safety — interleaved S2 and S3b edits', () {
    late GamesaveTool tool;
    late int boundary;
    late List<int> depthChartBefore;

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));
      boundary = tool.mModifiableNameSectionEnd;
      depthChartBefore = snapshot(tool, boundary, 256);
      StaticUtils.Errors.clear();
    });

    test('S2 edit does not disturb S3b player names', () {
      // Snapshot 10 player names before touching S2
      final playersBefore = [
        for (int i = 0; i < 10; i++) tool.GetPlayerLastName(i)
      ];

      // Shorten coach 0 last name (S2 edit)
      final origLast = tool.GetCoachAttribute(0, CoachOffsets.LastName);
      tool.SetCoachAttribute(0, CoachOffsets.LastName,
          origLast.substring(0, origLast.length - 1));

      for (int i = 0; i < 10; i++) {
        expect(tool.GetPlayerLastName(i), equals(playersBefore[i]),
            reason: 'Player $i last name must be unchanged after S2 edit');
      }
    });

    test('S3b edit does not disturb S2 coach names', () {
      // Snapshot all 32 coach first names before touching S3b
      final coachesBefore = [
        for (int i = 0; i < 32; i++)
          tool.GetCoachAttribute(i, CoachOffsets.FirstName)
      ];

      // Grow player 0 last name by 4 chars (S3b edit)
      final origPlayer0 = tool.GetPlayerLastName(0);
      tool.SetPlayerLastName(0, origPlayer0 + 'ZZZZ', false);
      expect(StaticUtils.Errors, isEmpty);

      for (int i = 0; i < 32; i++) {
        expect(tool.GetCoachAttribute(i, CoachOffsets.FirstName),
            equals(coachesBefore[i]),
            reason: 'Coach $i FirstName must be unchanged after S3b edit');
      }
    });

    test('S3a team nicknames unchanged after both S2 and S3b edits', () {
      // Load fresh baseline nicknames (franchise file values)
      final fresh = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      for (int i = 0; i < 32; i++) {
        expect(
          tool.GetTeamString(i, TeamDataOffsets.Nickname),
          equals(fresh.GetTeamString(i, TeamDataOffsets.Nickname)),
          reason: 'Team $i Nickname must be unchanged after S2+S3b edits',
        );
      }
    });

    test('depth chart bytes unchanged after interleaved edits', () {
      final after = snapshot(tool, boundary, 256);
      expect(after, equals(depthChartBefore),
          reason: 'Depth chart bytes must survive interleaved S2 and S3b edits');
    });
  });
}
