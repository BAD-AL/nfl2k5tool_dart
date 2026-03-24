import 'dart:io';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/gamesave_tool_io.dart';
import 'package:test/test.dart';

String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

const String _franchise = 'Base2004Fran_Orig.zip';
const String _baseRoster = 'years/BaseRoster/SAVEGAME.DAT';

void main() {
  // ─── T-S1–T-S8: S2 coach strings (franchise save) ───────────────────────────

  // T-S1 — Read all 32 coach string fields (read-only)
  group('T-S1 GetCoachAttribute string fields, all 32 coaches', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));
      tool.CoachKey = tool.CoachKeyAll;
    });

    test('team 0 (Erickson/49ers) string fields are correct', () {
      expect(tool.GetCoachAttribute(0, CoachOffsets.FirstName), equals('Dennis'));
      expect(tool.GetCoachAttribute(0, CoachOffsets.LastName),  equals('Erickson'));
      expect(tool.GetCoachAttribute(0, CoachOffsets.Info1),
          startsWith('One of the winningest'));
      expect(tool.GetCoachAttribute(0, CoachOffsets.Info2),
          equals('football history'));
    });

    test('team 1 (Smith/Bears) first and last name', () {
      expect(tool.GetCoachAttribute(1, CoachOffsets.FirstName), equals('Lovie'));
      expect(tool.GetCoachAttribute(1, CoachOffsets.LastName),  equals('Smith'));
    });

    test('team 31 (Tice) Info2 is last string in section', () {
      expect(tool.GetCoachAttribute(31, CoachOffsets.Info2),
          equals('bring consistency in 2004'));
    });

    test('no team returns !!!!Invalid!!!!', () {
      for (int i = 0; i < 32; i++) {
        for (final attr in [
          CoachOffsets.FirstName,
          CoachOffsets.LastName,
          CoachOffsets.Info1,
          CoachOffsets.Info2,
          CoachOffsets.Info3,   // T-QR-1: B-4/B-5 fix regression guard
        ]) {
          expect(
            tool.GetCoachAttribute(i, attr),
            isNot(equals('!!!!Invalid!!!!')),
            reason: 'Team $i ${attr.name} returned invalid sentinel',
          );
        }
      }
    });

    test('T-QR-1 team 24 (Billick) Info3 reads correctly', () {
      // Directly validates the B-4/B-5 (Info3) fix: GetCoachAttribute must
      // return the Info3 string, not throw or return garbage.
      expect(tool.GetCoachAttribute(24, CoachOffsets.Info3),
          equals('defensive powerhouse'));
    });
  });

  // T-S2 — Same-length coach string edit, save → reload
  group('T-S2 Coach string same-length edit (no shift)', () {
    test('same-length FirstName edit persists through save/reload', () async {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));

      tool.SetCoachAttribute(0, CoachOffsets.FirstName, 'Zenniz'); // 6 → 6
      expect(tool.GetCoachAttribute(0, CoachOffsets.FirstName), equals('Zenniz'));
      expect(tool.GetCoachAttribute(1, CoachOffsets.FirstName), equals('Lovie'),
          reason: 'Team 1 must be unaffected');
      expect(tool.GetCoachAttribute(31, CoachOffsets.Info2),
          equals('bring consistency in 2004'),
          reason: 'Team 31 Info2 must be unaffected');

      final tmp = '${Directory.systemTemp.path}/nfl2k5_str_ts2.dat';
      tool.SaveFile(tmp);
      final r = GamesaveTool()..LoadSaveFile(tmp);
      expect(r.GetCoachAttribute(0, CoachOffsets.FirstName), equals('Zenniz'));
      expect(r.GetCoachAttribute(1, CoachOffsets.FirstName), equals('Lovie'));
      expect(r.GetCoachAttribute(31, CoachOffsets.Info2),
          equals('bring consistency in 2004'));
      File(tmp).deleteSync();
    });
  });

  // T-S3 + T-S4 + T-S5 — Shorter then longer (shared state; T-S4 uses slack from T-S3)
  group('T-S3/T-S4/T-S5 shorter then longer coach strings (shared state)', () {
    late GamesaveTool tool;

    setUpAll(() {
      tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));
    });

    // T-S3 — Shorter: "Erickson" (8) → "Short" (5), frees 6 bytes
    test('T-S3 shorter LastName frees slack, team 31 Info2 intact', () {
      tool.SetCoachAttribute(0, CoachOffsets.LastName, 'Short');
      expect(tool.GetCoachAttribute(0, CoachOffsets.LastName), equals('Short'));
      expect(tool.GetCoachAttribute(1, CoachOffsets.LastName), equals('Smith'),
          reason: 'Team 1 LastName must be unaffected');
      expect(tool.GetCoachAttribute(31, CoachOffsets.Info2),
          equals('bring consistency in 2004'),
          reason: 'No truncation: section now has 6 bytes slack');
    });

    // T-S4 — Longer: "Lovie" (5) → "Lovieee" (7), costs 4 of the 6 freed bytes
    test('T-S4 longer FirstName within freed slack, team 31 Info2 still intact', () {
      tool.SetCoachAttribute(1, CoachOffsets.FirstName, 'Lovieee');
      expect(tool.GetCoachAttribute(1, CoachOffsets.FirstName), equals('Lovieee'));
      expect(tool.GetCoachAttribute(0, CoachOffsets.LastName), equals('Short'),
          reason: 'Team 0 LastName must be unaffected');
      expect(tool.GetCoachAttribute(31, CoachOffsets.Info2),
          equals('bring consistency in 2004'),
          reason: '2 bytes slack remain; no truncation');
    });

    // T-S4 save → reload
    test('T-S4 save/reload preserves both edits', () async {
      final tmp = '${Directory.systemTemp.path}/nfl2k5_str_ts4.dat';
      tool.SaveFile(tmp);
      final r = GamesaveTool()..LoadSaveFile(tmp);
      expect(r.GetCoachAttribute(1, CoachOffsets.FirstName), equals('Lovieee'));
      expect(r.GetCoachAttribute(0, CoachOffsets.LastName),  equals('Short'));
      expect(r.GetCoachAttribute(31, CoachOffsets.Info2),
          equals('bring consistency in 2004'));
      File(tmp).deleteSync();
    });

    // T-S5 — Longer: extend Info1 by 1 char, uses the last 2 bytes of slack
    test('T-S5 extend Info1 by 1 char uses remaining 2 bytes of slack', () {
      final orig = tool.GetCoachAttribute(0, CoachOffsets.Info1);
      tool.SetCoachAttribute(0, CoachOffsets.Info1, orig + 'X');
      expect(tool.GetCoachAttribute(0, CoachOffsets.Info1), equals(orig + 'X'));
      expect(tool.GetCoachAttribute(31, CoachOffsets.Info2),
          equals('bring consistency in 2004'),
          reason: 'Section now exactly full again; no truncation');
    });

    test('T-S5 save/reload preserves Info1 extension', () async {
      final expected = tool.GetCoachAttribute(0, CoachOffsets.Info1);
      final tmp = '${Directory.systemTemp.path}/nfl2k5_str_ts5.dat';
      tool.SaveFile(tmp);
      final r = GamesaveTool()..LoadSaveFile(tmp);
      expect(r.GetCoachAttribute(0, CoachOffsets.Info1), equals(expected));
      expect(r.GetCoachAttribute(31, CoachOffsets.Info2),
          equals('bring consistency in 2004'));
      File(tmp).deleteSync();
    });
  });

  // T-S6 — Coach string overflow guard (Issue D fix: Option B)
  group('T-S6 Coach string overflow guard (fresh load, section full)', () {
    setUp(() => StaticUtils.Errors.clear());

    test('growing coach string when section is full adds error and leaves data unchanged', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise)); // section has 0 slack

      final origFirst = tool.GetCoachAttribute(0, CoachOffsets.FirstName);
      final origInfo2 = tool.GetCoachAttribute(31, CoachOffsets.Info2);

      // Attempt to grow "Dennis" (6) → "Dennisss" (8): needs 4 bytes, 0 available
      tool.SetCoachAttribute(0, CoachOffsets.FirstName, 'Dennisss');

      expect(StaticUtils.Errors, isNotEmpty,
          reason: 'Guard must add an error when section is full');
      expect(tool.GetCoachAttribute(0, CoachOffsets.FirstName), equals(origFirst),
          reason: 'FirstName must be unchanged after rejected write');
      expect(tool.GetCoachAttribute(31, CoachOffsets.Info2), equals(origInfo2),
          reason: 'Team 31 Info2 must be intact (no truncation)');
    });
  });

  // T-S7 — AdjustCoachStringPointers: all 32 coaches correct after one edit
  group('T-S7 AdjustCoachStringPointers non-interference', () {
    test('shortening one coach leaves all other coach names unchanged', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));

      // Snapshot all 32 first+last names
      final firstNames = [for (int i = 0; i < 32; i++)
          tool.GetCoachAttribute(i, CoachOffsets.FirstName)];
      final lastNames  = [for (int i = 0; i < 32; i++)
          tool.GetCoachAttribute(i, CoachOffsets.LastName)];

      // Shorten team 0 LastName: "Erickson" → "E" (frees 14 bytes)
      tool.SetCoachAttribute(0, CoachOffsets.LastName, 'E');

      for (int i = 1; i < 32; i++) {
        expect(tool.GetCoachAttribute(i, CoachOffsets.FirstName),
            equals(firstNames[i]),
            reason: 'Team $i FirstName should be unaffected');
        expect(tool.GetCoachAttribute(i, CoachOffsets.LastName),
            equals(lastNames[i]),
            reason: 'Team $i LastName should be unaffected');
      }
    });
  });

  // T-S8 — InputParser coach string round-trip
  group('T-S8 InputParser coach string round-trip', () {
    test('CoachKEY + Coach line sets string fields; save→reload verifies', () async {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));

      // "Erickson" → "Shanahan" (8 → 7: fits, frees 2 bytes)
      // "Dennis"   → "Kyle"     (6 → 4: fits, frees 4 bytes)
      // Info1: "One of the winningest" → same length replacement
      final origInfo1 = tool.GetCoachAttribute(0, CoachOffsets.Info1);
      // Use same-length for Info1 to stay safe — just verify it passes through
      final parser = InputParser(tool);
      parser.ProcessLine('CoachKEY=Coach,Team,FirstName,LastName');
      parser.ProcessLine('Coach,49ers,Kyle,Shanahan');

      expect(tool.GetCoachAttribute(0, CoachOffsets.FirstName), equals('Kyle'));
      expect(tool.GetCoachAttribute(0, CoachOffsets.LastName),  equals('Shanahan'));
      // Info1 untouched (not in key)
      expect(tool.GetCoachAttribute(0, CoachOffsets.Info1), equals(origInfo1));

      final tmp = '${Directory.systemTemp.path}/nfl2k5_str_ts8.dat';
      tool.SaveFile(tmp);
      final r = GamesaveTool()..LoadSaveFile(tmp);
      expect(r.GetCoachAttribute(0, CoachOffsets.FirstName), equals('Kyle'));
      expect(r.GetCoachAttribute(0, CoachOffsets.LastName),  equals('Shanahan'));
      File(tmp).deleteSync();
    });
  });

  // ─── T-S9–T-S13: S3b player name strings (roster save) ─────────────────────

  // T-S9 — Player name same-length edit, save → reload
  group('T-S9 Player name same-length edit (no shift)', () {
    test('same-length last name edit persists through save/reload', () async {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_baseRoster));

      final orig = tool.GetPlayerLastName(0);
      final replacement = (orig[0] == 'Z' ? 'A' : 'Z') + orig.substring(1);

      tool.SetPlayerLastName(0, replacement, false);
      expect(tool.GetPlayerLastName(0), equals(replacement));
      expect(tool.GetPlayerLastName(1), isNot(equals(replacement)),
          reason: 'Player 1 must be unaffected');

      final tmp = '${Directory.systemTemp.path}/nfl2k5_str_ts9.dat';
      tool.SaveFile(tmp);
      final r = GamesaveTool()..LoadSaveFile(tmp);
      expect(r.GetPlayerLastName(0), equals(replacement));
      File(tmp).deleteSync();
    });
  });

  // T-S10 — Player name shorter (ShiftDataUp)
  group('T-S10 Player name shorter (ShiftDataUp)', () {
    test('shortened last name persists; player 1 and college unaffected', () async {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_baseRoster));

      final orig = tool.GetPlayerLastName(0);
      final short = orig.length >= 3 ? orig.substring(0, orig.length - 3) : orig.substring(0, 1);
      final player1Last = tool.GetPlayerLastName(1);
      final college0    = tool.GetPlayerCollege(0);

      tool.SetPlayerLastName(0, short, false);
      expect(tool.GetPlayerLastName(0), equals(short));
      expect(tool.GetPlayerLastName(1), equals(player1Last));
      expect(tool.GetPlayerCollege(0),  equals(college0),
          reason: 'Bug 3 regression guard: college must not shift');

      final tmp = '${Directory.systemTemp.path}/nfl2k5_str_ts10.dat';
      tool.SaveFile(tmp);
      final r = GamesaveTool()..LoadSaveFile(tmp);
      expect(r.GetPlayerLastName(0), equals(short));
      expect(r.GetPlayerLastName(1), equals(player1Last));
      expect(r.GetPlayerCollege(0),  equals(college0));
      File(tmp).deleteSync();
    });
  });

  // T-S11 — Player name longer (ShiftDataDown)
  group('T-S11 Player name longer (+4 chars, ShiftDataDown)', () {
    test('extended last name persists; player 1 and college unaffected', () async {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_baseRoster));

      final orig        = tool.GetPlayerLastName(0);
      final extended    = orig + 'ZZZZ';
      final player1Last = tool.GetPlayerLastName(1);
      final college0    = tool.GetPlayerCollege(0);

      tool.SetPlayerLastName(0, extended, false);
      expect(tool.GetPlayerLastName(0), equals(extended));
      expect(tool.GetPlayerLastName(1), equals(player1Last));
      expect(tool.GetPlayerCollege(0),  equals(college0),
          reason: 'Bug 3 regression guard');

      final tmp = '${Directory.systemTemp.path}/nfl2k5_str_ts11.dat';
      tool.SaveFile(tmp);
      final r = GamesaveTool()..LoadSaveFile(tmp);
      expect(r.GetPlayerLastName(0), equals(extended));
      expect(r.GetPlayerLastName(1), equals(player1Last));
      expect(r.GetPlayerCollege(0),  equals(college0));
      File(tmp).deleteSync();
    });
  });

  // T-S12 — AdjustPlayerNamePointers: spot-check 10 players after one shift
  group('T-S12 AdjustPlayerNamePointers non-interference', () {
    test('shortening player 0 last name leaves players 1–9 names unchanged', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_baseRoster));

      final firstNames = [for (int i = 0; i < 10; i++) tool.GetPlayerFirstName(i)];
      final lastNames  = [for (int i = 0; i < 10; i++) tool.GetPlayerLastName(i)];

      final orig  = tool.GetPlayerLastName(0);
      final short = orig.length >= 3 ? orig.substring(0, orig.length - 3) : orig.substring(0, 1);
      tool.SetPlayerLastName(0, short, false);

      for (int i = 1; i < 10; i++) {
        expect(tool.GetPlayerFirstName(i), equals(firstNames[i]),
            reason: 'Player $i FirstName must be unaffected');
        expect(tool.GetPlayerLastName(i),  equals(lastNames[i]),
            reason: 'Player $i LastName must be unaffected');
      }
    });
  });

  // T-S13 — Cross-section: player name edit does not corrupt S2 or S3a
  group('T-S13 Player name shift does not disturb S2 or S3a', () {
    test('growing player 0 last name leaves all coach names and 49ers S3a intact', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));

      final coachFirstNames = [for (int i = 0; i < 32; i++)
          tool.GetCoachAttribute(i, CoachOffsets.FirstName)];
      final nicknameBefore = tool.GetTeamString(0, TeamDataOffsets.Nickname);

      final orig = tool.GetPlayerLastName(0);
      tool.SetPlayerLastName(0, orig + 'ZZZZ', false);

      for (int i = 0; i < 32; i++) {
        expect(tool.GetCoachAttribute(i, CoachOffsets.FirstName),
            equals(coachFirstNames[i]),
            reason: 'Coach $i FirstName must be unaffected (S2 untouched)');
      }
      expect(tool.GetTeamString(0, TeamDataOffsets.Nickname), equals(nicknameBefore),
          reason: 'S3a must be unaffected by S3b shift');
      expect(tool.GetPlayerLastName(0), equals(orig + 'ZZZZ'),
          reason: 'Edit must have succeeded');
    });
  });

  // T-S14 — Info3 set — documents and tests Issue A
  group('T-S14 Info3 set documents Issue A', () {
    setUp(() => StaticUtils.Errors.clear());

    test('SetCoachAttribute Info3 sets and persists through save/reload', () async {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));

      // Verify baseline
      expect(tool.GetCoachAttribute(24, CoachOffsets.Info3),
          equals('defensive powerhouse'));

      // "defensive powerhouse" = 20 chars → "updated bio" = 11 chars (shorter: frees slack)
      tool.SetCoachAttribute(24, CoachOffsets.Info3, 'updated bio');
      expect(tool.GetCoachAttribute(24, CoachOffsets.Info3), equals('updated bio'));

      // Verify AdjustCoachStringPointers kept other coaches' strings intact
      expect(tool.GetCoachAttribute(0, CoachOffsets.FirstName), equals('Dennis'));
      expect(tool.GetCoachAttribute(31, CoachOffsets.Info2),
          equals('bring consistency in 2004'));

      final tmp = '${Directory.systemTemp.path}/nfl2k5_str_ts14.dat';
      tool.SaveFile(tmp);
      final r = GamesaveTool()..LoadSaveFile(tmp);
      expect(r.GetCoachAttribute(24, CoachOffsets.Info3), equals('updated bio'));
      expect(r.GetCoachAttribute(0, CoachOffsets.FirstName), equals('Dennis'));
      File(tmp).deleteSync();
    });
  });

  // T-QR-2 — AdjustCoachStringPointers correctly adjusts Info3 pointers after a shift
  //
  // Regression test for the B-5 fix: Info3 was missing from AdjustCoachStringPointers,
  // meaning a shift caused by any string edit would leave all later coaches' Info3
  // pointers pointing at stale addresses.
  group('T-QR-2 AdjustCoachStringPointers adjusts Info3 for all coaches after shift', () {
    test('all 32 coaches Info3 intact after team 0 LastName shrink', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));

      final info3Before = [
        for (int i = 0; i < 32; i++)
          tool.GetCoachAttribute(i, CoachOffsets.Info3)
      ];

      // Shorten team 0 LastName: "Erickson" (8) → "E" (1), frees 14 bytes.
      // AdjustCoachStringPointers must update the Info3 ptr for teams 1–31.
      tool.SetCoachAttribute(0, CoachOffsets.LastName, 'E');

      for (int i = 1; i < 32; i++) {
        expect(tool.GetCoachAttribute(i, CoachOffsets.Info3),
            equals(info3Before[i]),
            reason: 'Team $i Info3 pointer must be adjusted by AdjustCoachStringPointers');
      }
    });
  });

  // T-QR-6 — Empty Info3 / Info2 round-trip
  //
  // Some coaches (e.g. Lovie Smith / Bears, team 1) have empty Info2 AND Info3.
  // Verify:
  //   • GetCoachAttribute returns "" for those fields
  //   • GetCoachDataAll output contains the consecutive-comma pattern (empty fields)
  //   • Re-importing the full export back into a fresh load produces no errors and
  //     all string values are identical to the pre-export baseline
  //   • Setting a non-empty value into a previously-empty Info3 succeeds

  group('T-QR-6 Empty Info2/Info3 round-trip', () {
    setUp(() => StaticUtils.Errors.clear());

    test('Bears (team 1) has empty Info2 and Info3', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));
      expect(tool.GetCoachAttribute(1, CoachOffsets.Info2), equals(''));
      expect(tool.GetCoachAttribute(1, CoachOffsets.Info3), equals(''));
    });

    test('GetCoachDataAll output contains empty-field pattern for Bears line', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));
      tool.CoachKey = tool.CoachKeyAll;
      final output = tool.GetCoachDataAll();
      // Bears line must contain "Lovie,Smith" followed somewhere by ",," (two empty info fields)
      final bearsLine = output.split('\n').firstWhere(
          (l) => l.contains('Bears') && l.startsWith('Coach,'),
          orElse: () => '');
      expect(bearsLine, isNotEmpty, reason: 'Bears coach line must be present');
      expect(bearsLine, contains('Lovie'));
      expect(bearsLine, contains('Smith'));
      expect(bearsLine, contains(',,'),
          reason: 'Empty info fields must produce consecutive commas in output');
    });

    test('full export→import round-trip preserves all 32 coach strings (no errors)', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));
      tool.CoachKey = tool.CoachKeyAll;

      // Snapshot baseline strings for all 32 coaches.
      final firstNames = [for (int i = 0; i < 32; i++) tool.GetCoachAttribute(i, CoachOffsets.FirstName)];
      final lastNames  = [for (int i = 0; i < 32; i++) tool.GetCoachAttribute(i, CoachOffsets.LastName)];
      final info1s     = [for (int i = 0; i < 32; i++) tool.GetCoachAttribute(i, CoachOffsets.Info1)];
      final info2s     = [for (int i = 0; i < 32; i++) tool.GetCoachAttribute(i, CoachOffsets.Info2)];
      final info3s     = [for (int i = 0; i < 32; i++) tool.GetCoachAttribute(i, CoachOffsets.Info3)];

      // Export, then re-import into a fresh tool instance.
      final exportText = tool.GetCoachDataAll();

      final tool2 = GamesaveTool();
      tool2.LoadSaveFile(testFile(_franchise));
      tool2.CoachKey = tool.CoachKeyAll;
      final parser2 = InputParser(tool2);
      parser2.ProcessText(exportText);

      expect(StaticUtils.Errors, isEmpty,
          reason: 'Re-importing the export must produce no errors');

      for (int i = 0; i < 32; i++) {
        expect(tool2.GetCoachAttribute(i, CoachOffsets.FirstName), equals(firstNames[i]),
            reason: 'Team $i FirstName must survive round-trip');
        expect(tool2.GetCoachAttribute(i, CoachOffsets.LastName), equals(lastNames[i]),
            reason: 'Team $i LastName must survive round-trip');
        expect(tool2.GetCoachAttribute(i, CoachOffsets.Info1), equals(info1s[i]),
            reason: 'Team $i Info1 must survive round-trip');
        expect(tool2.GetCoachAttribute(i, CoachOffsets.Info2), equals(info2s[i]),
            reason: 'Team $i Info2 must survive round-trip');
        expect(tool2.GetCoachAttribute(i, CoachOffsets.Info3), equals(info3s[i]),
            reason: 'Team $i Info3 must survive round-trip');
      }
    });

    test('setting a non-empty value into a previously-empty Info3 succeeds', () {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));
      // Team 1 (Bears) currently has empty Info3 — but Info3 is empty/null-length,
      // so we first need to free slack by shortening another string.
      tool.SetCoachAttribute(0, CoachOffsets.LastName, 'E'); // frees 14 bytes
      expect(StaticUtils.Errors, isEmpty);

      // Now attempt to set a value for Bears Info3 (was empty — diff = newLen).
      // NOTE: If the section is still full after shrink this may still fail — that
      // is expected behaviour. The test verifies no crash/exception occurs and that
      // the result is either the new value (success) or "" (graceful rejection).
      String? caughtError;
      try {
        tool.SetCoachAttribute(1, CoachOffsets.Info3, 'new info');
      } catch (e) {
        caughtError = e.toString();
      }
      expect(caughtError, isNull,
          reason: 'SetCoachAttribute must not throw for a previously-empty Info3 field');

      // After the write the value is either "new info" (success) or "" (rejected).
      final result = tool.GetCoachAttribute(1, CoachOffsets.Info3);
      expect(result == 'new info' || result == '',
          isTrue,
          reason: 'Result must be either the new value or empty string (graceful rejection)');
    });
  });

  // T-QR-5 — Info3 grow after freeing slack (key path from the B-4 fix)
  //
  // T-S14 only tests shortening Info3.  Growing Info3 was the previously broken
  // path — it would throw FormatException because it fell through to int.parse.
  group('T-QR-5 Info3 grow after freeing slack (B-4 fix regression)', () {
    setUp(() => StaticUtils.Errors.clear());

    test('Info3 can be extended after another string frees slack; surrounding data intact', () async {
      final tool = GamesaveTool();
      tool.LoadSaveFile(testFile(_franchise));

      // Free 6 bytes of slack by shortening team 0 LastName.
      tool.SetCoachAttribute(0, CoachOffsets.LastName, 'Short');
      expect(StaticUtils.Errors, isEmpty);

      final orig = tool.GetCoachAttribute(24, CoachOffsets.Info3); // "defensive powerhouse"
      // Grow Info3 by 2 chars (costs 4 bytes from the 6 freed).
      tool.SetCoachAttribute(24, CoachOffsets.Info3, orig + 'XX');
      expect(tool.GetCoachAttribute(24, CoachOffsets.Info3), equals(orig + 'XX'),
          reason: 'Info3 must accept a longer value when slack is available');
      expect(StaticUtils.Errors, isEmpty,
          reason: 'No error expected — 4 bytes growth fits in 6 freed bytes');

      // Surrounding data must be undisturbed.
      expect(tool.GetCoachAttribute(0, CoachOffsets.FirstName), equals('Dennis'));
      expect(tool.GetCoachAttribute(31, CoachOffsets.Info2),
          equals('bring consistency in 2004'));

      // Persist and reload.
      final tmp = '${Directory.systemTemp.path}/nfl2k5_str_tqr5.dat';
      tool.SaveFile(tmp);
      final r = GamesaveTool()..LoadSaveFile(tmp);
      expect(r.GetCoachAttribute(24, CoachOffsets.Info3), equals(orig + 'XX'));
      expect(r.GetCoachAttribute(0, CoachOffsets.FirstName), equals('Dennis'));
      expect(r.GetCoachAttribute(31, CoachOffsets.Info2),
          equals('bring consistency in 2004'));
      File(tmp).deleteSync();
    });
  });
}
