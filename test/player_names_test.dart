import 'dart:io';
import 'dart:typed_data';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/gamesave_tool_io.dart';
import 'package:test/test.dart';

String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

const String _franchise = 'Base2004Fran_Orig.zip';
const String _roster = 'BaseRoster/SAVEGAME.DAT';
const String _maddenConversion = 'Madden-conversion-2026.txt';

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Parses [text]'s player rows into team -> ordered [firstName, lastName]
/// pairs, exactly as the source file intends them, for cross-checking
/// against what actually got committed. NOT a general InputParser
/// replacement — just enough to verify names end up correct, independent of
/// the code under test. [fnameCol]/[lnameCol] must match the file's own
/// Key= column order (this repo's default puts Position first; some
/// externally-generated files, like Madden-conversion-2026.txt, put
/// fname/lname first instead).
Map<String, List<List<String>>> _parseExpectedNamesByTeam(
  String text, {
  required int fnameCol,
  required int lnameCol,
}) {
  final expectedByTeam = <String, List<List<String>>>{};
  String? currentTeam;
  for (var line in text.split(RegExp(r'[\n\r]'))) {
    line = line.trim();
    if (line.isEmpty ||
        line.startsWith('#') ||
        line.startsWith('ApplyFormula') ||
        line.toLowerCase().startsWith('key=')) {
      continue;
    }
    final teamMatch = RegExp(r'^Team\s*=\s*([0-9a-zA-Z]+)').firstMatch(line);
    if (teamMatch != null) {
      currentTeam = teamMatch.group(1);
      expectedByTeam.putIfAbsent(currentTeam!, () => []);
      continue;
    }
    if (currentTeam == null) continue;
    final parts = line.split(',');
    if (parts.length <= fnameCol || parts.length <= lnameCol) continue;
    expectedByTeam[currentTeam]!.add([parts[fnameCol], parts[lnameCol]]);
  }
  return expectedByTeam;
}

void main() {
  // T-PN-1 — Capacity
  group('T-PN-1 Capacity', () {
    test('budget is 54303 bytes', () {
      expect(PlayerNames.budget, equals(54303));
    });

    test('franchise baseline requiredBytes/requiredBytesAfterDedup (regression guard)', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final names = PlayerNames.fromTool(tool);
      // PlayerNames' *editable* domain is Team + FreeAgent players only —
      // draft class (up to 380 players in franchise) is never edited through
      // it. In this file, every draft-class name pointer also resolves
      // outside S3b entirely (into the separate, read-only college-name
      // section), except for a single always-empty, structurally-unused
      // slot one past the real player count — _load()'s system-resident
      // pass models that one read-only (4 bytes: two empty strings) purely
      // so commit()'s repack can't orphan its pointer, but it never holds
      // real content. A completely untouched stock file must therefore
      // already fit with zero reduction — this is the exact regression this
      // guard exists to catch (see T-PN-14 for the full pipeline version).
      expect(names.requiredBytes, equals(52614));
      expect(names.requiredBytes, lessThan(PlayerNames.budget));
      expect(names.requiredBytesAfterDedup, equals(29350));
      expect(names.requiredBytesAfterDedup, lessThan(names.requiredBytes),
          reason: 'Dedup ceiling must always be <= the naive total');
    });

    test('roster baseline requiredBytes fits budget without any reduction', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      final names = PlayerNames.fromTool(tool);
      expect(names.requiredBytes, equals(52788));
      expect(names.requiredBytes, lessThan(PlayerNames.budget));
    });

    test('roster carries extra system-resident bytes franchise does not', () {
      // Unlike Franchise, where the draft-class index range resolves
      // outside S3b (into the college-name section) with one harmless empty
      // exception (see the test above), Roster's equivalent range holds a
      // handful of fixed, permanent entries (e.g. broadcast-booth names)
      // whose pointers resolve *inside* S3b for this save type — real
      // content _load()'s system-resident pass must model read-only so
      // commit()'s repack preserves rather than destroys it. That makes the
      // two save types' baselines genuinely different, not bugs to reconcile.
      final franchiseNames =
          PlayerNames.fromTool(GamesaveTool()..LoadSaveFile(testFile(_franchise)));
      final rosterNames =
          PlayerNames.fromTool(GamesaveTool()..LoadSaveFile(testFile(_roster)));
      expect(rosterNames.requiredBytes - franchiseNames.requiredBytes, equals(174));
    });
  });

  // T-PN-2 — Overlay edits
  group('T-PN-2 Overlay edits', () {
    test('edit applies to the right player/field only', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      final names = PlayerNames.fromTool(tool);
      final before = names.requiredBytes;

      names.overlayEdit(0, false, 'Zebulon');
      names.overlayEdit(5, true, 'Q');

      expect(tool.GetPlayerFirstName(0), equals('Duane'),
          reason: 'Overlay must not touch GameSaveData until commit()');
      expect(names.requiredBytes, isNot(equals(before)));
    });
  });

  // T-PN-3 — Dedup planning
  group('T-PN-3 Dedup planning', () {
    late GamesaveTool tool;
    late PlayerNames names;

    setUp(() {
      tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      names = PlayerNames.fromTool(tool);
    });

    test('known duplicate groups produce expected best-case savings', () {
      final plan = names.planDedup();
      expect(plan.groups, isNotEmpty);
      expect(plan.totalSavings, equals(23264));
      final williams = plan.groups.firstWhere((g) => g.text == 'Williams' && g.isLastName);
      expect(williams.savingsBytes, equals(648));
      expect(williams.redirected.length, equals(36));
    });

    test('canonical owner is always the highest-priority group member', () {
      final plan = names.planDedup();
      for (final g in plan.groups) {
        for (final r in g.redirected) {
          // Never redirect to a free-agent canonical when a protected
          // (active roster) member exists in the same group.
          if (!g.canonical.isFreeAgent) continue;
          expect(r.isFreeAgent, isTrue,
              reason: 'If canonical is a free agent, no protected member can exist in the group');
        }
      }
    });

    test('same-field-only: a first name never matches a last name', () {
      final plan = names.planDedup();
      for (final g in plan.groups) {
        expect(g.canonical.isLastName, equals(g.isLastName));
        for (final r in g.redirected) {
          expect(r.isLastName, equals(g.isLastName));
        }
      }
    });

    test('targetBytes stops once the deficit is closed (minimal plan)', () {
      final target = 10000;
      final plan = names.planDedup(targetBytes: target);
      expect(plan.totalSavings, greaterThanOrEqualTo(target));
      final full = names.planDedup();
      expect(plan.groups.length, lessThan(full.groups.length),
          reason: 'A minimal plan should touch fewer groups than the full best case');
    });
  });

  // T-PN-4 — Dedup commit correctness
  group('T-PN-4 Dedup commit correctness', () {
    test('redirected players read correctly, share address, others unaffected, round trip', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final names = PlayerNames.fromTool(tool);
      final plan = names.planDedup();
      names.applyDedup(plan);

      final origPlayer0First = tool.GetPlayerFirstName(0);
      final origPlayer0Last = tool.GetPlayerLastName(0);

      final result = names.commit();

      expect(result.success, isTrue);
      expect(result.bytesUsed, equals(29350));
      expect(result.bytesUsed, lessThan(PlayerNames.budget));

      // Spot-check a known duplicate group (see T-PN-3).
      expect(tool.GetPlayerLastName(142), equals('Williams'));
      expect(tool.GetPlayerLastName(675), equals('Williams'));

      // Untouched player unaffected.
      expect(tool.GetPlayerFirstName(0), equals(origPlayer0First));
      expect(tool.GetPlayerLastName(0), equals(origPlayer0Last));

      // Deliberately-shared pointers are now detected (expected after dedup).
      expect(tool.checkNamePointers(), isTrue);

      // Save -> reload round trip.
      final tmp = '${Directory.systemTemp.path}/nfl2k5_pn_t4.dat';
      tool.SaveFile(tmp);
      final reloaded = GamesaveTool()..LoadSaveFile(tmp);
      expect(reloaded.GetPlayerLastName(142), equals('Williams'));
      expect(reloaded.GetPlayerLastName(675), equals('Williams'));
      expect(reloaded.GetPlayerFirstName(0), equals(origPlayer0First));
      expect(reloaded.GetPlayerLastName(0), equals(origPlayer0Last));
      File(tmp).deleteSync();
    });
  });

  // T-PN-5 — Truncation planning
  group('T-PN-5 Truncation planning', () {
    late PlayerNames names;

    setUp(() {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      names = PlayerNames.fromTool(tool);
    });

    test('names of 4 chars or fewer are never selected', () {
      final plan = names.planTruncation();
      for (final e in plan.entries) {
        expect(e.originalText.length, greaterThan(4));
      }
    });

    test('only free agents (never draft class or active roster) are candidates', () {
      // Draft-class players aren't modeled by PlayerNames at all (see
      // PlayerNames._load), so this is really just checking free-agent-only.
      final plan = names.planTruncation();
      expect(plan.entries, isNotEmpty);
      for (final e in plan.entries) {
        expect(e.ref.isFreeAgent, isTrue);
        expect(e.ref.playerIndex, lessThan(GamesaveTool.FirstDraftClassPlayer));
      }
    });

    test('longest names first, fewest players touched for a given target', () {
      final plan = names.planTruncation();
      for (int i = 1; i < plan.entries.length; i++) {
        expect(plan.entries[i - 1].originalText.length,
            greaterThanOrEqualTo(plan.entries[i].originalText.length));
      }

      final target = 100;
      final minimal = names.planTruncation(targetBytes: target);
      expect(minimal.totalSavings, greaterThanOrEqualTo(target));
      expect(minimal.entries.length, lessThan(plan.entries.length));
    });
  });

  // T-PN-6 — Truncation commit correctness
  group('T-PN-6 Truncation commit correctness', () {
    test('exact "X." format, last name untouched, round trip, others byte-identical', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      final names = PlayerNames.fromTool(tool);
      final plan = names.planTruncation();
      final first = plan.entries.first;
      final player = first.ref.playerIndex;
      final lastNameBefore = tool.GetPlayerLastName(player);
      final untouchedFirst = tool.GetPlayerFirstName(0);

      names.applyTruncation(plan);
      final result = names.commit();

      expect(result.success, isTrue);
      final newFirst = tool.GetPlayerFirstName(player);
      expect(newFirst.length, equals(2));
      expect(newFirst[1], equals('.'));
      expect(newFirst[0], equals(first.originalText[0]));
      expect(tool.GetPlayerLastName(player), equals(lastNameBefore),
          reason: 'Truncation must never touch last names');
      expect(tool.GetPlayerFirstName(0), equals(untouchedFirst));

      final tmp = '${Directory.systemTemp.path}/nfl2k5_pn_t6.dat';
      tool.SaveFile(tmp);
      final reloaded = GamesaveTool()..LoadSaveFile(tmp);
      expect(reloaded.GetPlayerFirstName(player), equals(newFirst));
      expect(reloaded.GetPlayerLastName(player), equals(lastNameBefore));
      File(tmp).deleteSync();
    });
  });

  // T-PN-7 — checkNamePointers gating
  group('T-PN-7 checkNamePointers gating', () {
    test('runs and is clean on a non-dedup commit', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      final names = PlayerNames.fromTool(tool);
      final result = names.commit();
      expect(result.success, isTrue);
      expect(result.warnings, isEmpty,
          reason: 'No shared pointers were created, so no warning is expected');
      expect(tool.checkNamePointers(), isFalse,
          reason: 'Ground truth: no shared pointers should exist after a non-dedup commit');
    });

    test('is skipped on a dedup commit (no false failure from intentional sharing)', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final names = PlayerNames.fromTool(tool);
      names.applyDedup(names.planDedup());
      final result = names.commit();
      expect(result.success, isTrue);
      expect(result.warnings, isEmpty,
          reason: 'Dedup deliberately creates shared pointers; must not be reported as a warning');
    });
  });

  // T-PN-8 — Pointer-category regression guard
  group('T-PN-8 Pointer-category regression guard', () {
    test('every player/coach/college pointer into the pool resolves correctly after dedup', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final names = PlayerNames.fromTool(tool);
      names.applyDedup(names.planDedup());
      final result = names.commit();
      expect(result.success, isTrue);

      // Every player's first/last name must read back exactly as committed.
      for (int p = 0; p <= tool.mMaxPlayers; p++) {
        expect(() => tool.GetPlayerFirstName(p), returnsNormally);
        expect(() => tool.GetPlayerLastName(p), returnsNormally);
        expect(tool.GetPlayerFirstName(p), isNot(contains('INVALID')));
        expect(tool.GetPlayerLastName(p), isNot(contains('INVALID')));
      }

      // Coach names must be entirely unaffected (they live in S2, not S3b).
      for (int team = 0; team < 32; team++) {
        expect(() => tool.GetCoachAttribute(team, CoachOffsets.FirstName), returnsNormally);
        expect(() => tool.GetCoachAttribute(team, CoachOffsets.LastName), returnsNormally);
      }

      // College lookups must still resolve (spot-check a handful of players).
      for (int p = 0; p < 50; p++) {
        expect(() => tool.GetCollege(p), returnsNormally);
      }
    });
  });

  // T-PN-9 — Budget enforcement / no-op on failure
  group('T-PN-9 Budget enforcement', () {
    test('still-over-budget after best-case dedup+truncation fails cleanly, no bytes touched', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      final snapshot = Uint8List.fromList(tool.GameSaveData!);
      final names = PlayerNames.fromTool(tool);

      for (int p = 0; p < GamesaveTool.FirstDraftClassPlayer; p++) {
        names.overlayEdit(p, false, '${'X' * 50}$p');
        names.overlayEdit(p, true, '${'Y' * 50}$p');
      }
      names.applyDedup(names.planDedup());
      names.applyTruncation(names.planTruncation());

      final result = names.commit();
      expect(result.success, isFalse);
      expect(result.warnings, isNotEmpty);
      expect(_bytesEqual(tool.GameSaveData!, snapshot), isTrue,
          reason: 'A failed commit must leave GameSaveData completely untouched');
    });
  });

  // T-PN-10 — InputParser integration
  group('T-PN-10 InputParser integration', () {
    test('no-op round trip via collect/commit leaves names and other attributes unchanged', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      final key = tool.GetKey(true, true);
      final text = '$key\n${tool.GetLeaguePlayers(true, true, false)}';

      final origFirst = tool.GetPlayerFirstName(0);
      final origLast = tool.GetPlayerLastName(0);
      final origSpeed = tool.GetPlayerField(0, 'Speed');

      final names = collectPlayerNamesFromText(tool, text);
      final result = commitPlayerNamesAndApplyRest(tool, text, names);

      expect(result.success, isTrue);
      expect(tool.GetPlayerFirstName(0), equals(origFirst));
      expect(tool.GetPlayerLastName(0), equals(origLast));
      expect(tool.GetPlayerField(0, 'Speed'), equals(origSpeed));
    });

    test('a name edit in the text propagates; other attributes still apply', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      final key = tool.GetKey(true, true);
      final origFirst = tool.GetPlayerFirstName(0);
      final origLast = tool.GetPlayerLastName(0);
      final origSpeed = tool.GetPlayerField(0, 'Speed');
      final text = '$key\n${tool.GetLeaguePlayers(true, true, false)}';
      final edited = text.replaceFirst('$origFirst,$origLast', 'Zeb,Zorbo');

      final names = collectPlayerNamesFromText(tool, edited);
      final result = commitPlayerNamesAndApplyRest(tool, edited, names);

      expect(result.success, isTrue);
      expect(tool.GetPlayerFirstName(0), equals('Zeb'));
      expect(tool.GetPlayerLastName(0), equals('Zorbo'));
      expect(tool.GetPlayerField(0, 'Speed'), equals(origSpeed),
          reason: 'Non-name attributes must still apply through the second pass');
    });

    test('NameSetter defaults to null: existing (pre-feature) InputParser callers unaffected', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      final key = tool.GetKey(true, true);
      final origFirst = tool.GetPlayerFirstName(0);
      final origLast = tool.GetPlayerLastName(0);
      final text = '$key\n${tool.GetLeaguePlayers(true, true, false)}';
      final edited = text.replaceFirst('$origFirst,$origLast', 'Zeb,Zorbo');

      // Exactly today's usage: a single ProcessText call, no NameSetter.
      final parser = InputParser(tool);
      expect(parser.NameSetter, isNull);
      parser.ProcessText(edited);

      expect(tool.GetPlayerFirstName(0), equals('Zeb'));
      expect(tool.GetPlayerLastName(0), equals('Zorbo'));
    });
  });

  // T-PN-11 — Real large-scale text corpus (not synthetic edits)
  group('T-PN-11 Full-league text dump stress test', () {
    test('real 475KB/2053-line full-league export: collect, dedup, commit, reload', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final text = File(testFile('Base2004Fran_Orig.output.ab.app.sch.txt')).readAsStringSync();
      expect(text.length, greaterThan(400000),
          reason: 'Sanity check that this really is the large real corpus, not a stub');

      final origFirst0 = tool.GetPlayerFirstName(0);
      final origLast0 = tool.GetPlayerLastName(0);

      final names = collectPlayerNamesFromText(tool, text);
      // Same real-world figure as the binary-only capacity test (T-PN-1) —
      // this text is a serialization of the same underlying save.
      expect(names.requiredBytes, equals(52614));

      names.applyDedup(names.planDedup());
      final result = commitPlayerNamesAndApplyRest(tool, text, names);

      expect(result.success, isTrue);
      expect(result.bytesUsed, equals(29350));
      expect(tool.GetPlayerFirstName(0), equals(origFirst0));
      expect(tool.GetPlayerLastName(0), equals(origLast0));
      expect(tool.checkNamePointers(), isTrue,
          reason: 'Dedup deliberately created shared pointers');

      // Spot-check players scattered across active roster through draft class.
      for (final p in [0, 500, 1500, 2300]) {
        expect(() => tool.GetPlayerFirstName(p), returnsNormally);
        expect(() => tool.GetPlayerLastName(p), returnsNormally);
        expect(tool.GetPlayerFirstName(p), isNot(contains('INVALID')));
      }

      final tmp = '${Directory.systemTemp.path}/nfl2k5_pn_t11.dat';
      tool.SaveFile(tmp);
      final reloaded = GamesaveTool()..LoadSaveFile(tmp);
      expect(reloaded.GetPlayerFirstName(0), equals(origFirst0));
      expect(reloaded.GetPlayerLastName(0), equals(origLast0));
      File(tmp).deleteSync();
    });
  });

  // T-PN-12 — External, non-gamesave-derived text (genuinely overflows on its own)
  group('T-PN-12 Externally-generated conversion file (Madden-conversion-2026.txt)', () {
    test('real overflow from a third-party tool: dedup alone closes the gap', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final text = File(testFile(_maddenConversion)).readAsStringSync();
      expect(text.length, greaterThan(500000));

      // This file uses a custom Key= line (fname/lname before Position,
      // unlike our own default column order) — exercises SetKey, not just
      // the auto-generated GetKey path every other test relies on.
      expect(text, startsWith('Key=fname,lname,Position,'));

      // Baseline free-agent names, captured before any processing, so we can
      // later confirm every slot got genuinely overwritten (not silently
      // left stale because some line failed to insert).
      final faIndexes = tool.GetPlayerIndexesForTeam('FreeAgents');
      final baselineFA = {
        for (final p in faIndexes) p: '${tool.GetPlayerFirstName(p)}|${tool.GetPlayerLastName(p)}'
      };

      StaticUtils.Errors.clear();
      final names = collectPlayerNamesFromText(tool, text);

      // This file lists more free agents than the fixed-size free-agent slot
      // array holds — a pre-existing, orthogonal player-count limit (nothing
      // to do with the name-pool budget) that InputParser already reports.
      // Pinning the count as a regression guard: if this changes, something
      // about free-agent slot handling or this fixture changed.
      expect(StaticUtils.Errors.length, equals(427));
      expect(StaticUtils.Errors.first, contains('team player limit reached'));

      // The 427 rejected players' names must never reach the model at all —
      // InputParser's own player-index guard (returns -1 once a team's slots
      // are exhausted) short-circuits before our NameSetter hook is ever
      // called for those lines. Verify concretely: every free-agent slot
      // that DID exist got overwritten by one of the (successfully-inserted)
      // free agents earlier in the file, none were left stale.
      final rejectedNames = <String>{};
      for (final err in StaticUtils.Errors) {
        final m = RegExp(r'cannot add player: ([^,]+),([^,]+),').firstMatch(err);
        if (m != null) rejectedNames.add('${m.group(1)}|${m.group(2)}');
      }
      expect(rejectedNames.length, equals(427),
          reason: 'Every rejection should name a distinct player line');

      // Genuinely over budget with zero reduction — unlike our own exported
      // fixtures, this wasn't authored with any pointer-sharing baked in.
      expect(names.requiredBytes, equals(55004));
      expect(names.requiredBytes, greaterThan(PlayerNames.budget));

      final dedup = names.planDedup();
      expect(dedup.totalSavings, equals(19094));
      names.applyDedup(dedup);

      StaticUtils.Errors.clear();
      final result = commitPlayerNamesAndApplyRest(tool, text, names);

      expect(result.success, isTrue);
      expect(result.bytesUsed, equals(35910));
      expect(result.bytesUsed, lessThan(PlayerNames.budget));
      expect(tool.checkNamePointers(), isTrue,
          reason: 'Dedup deliberately created shared pointers');

      // None of the 427 rejected players' names ended up occupying a
      // free-agent slot, and every slot that exists was genuinely
      // overwritten (proving the earlier, successfully-inserted free agents
      // filled every slot before the limit was hit — nothing was silently
      // left stale).
      int slotsStillBaseline = 0;
      for (final p in faIndexes) {
        final combined = '${tool.GetPlayerFirstName(p)}|${tool.GetPlayerLastName(p)}';
        expect(rejectedNames.contains(combined), isFalse,
            reason: 'Free-agent slot $p ended up with a name that was rejected during parsing');
        if (combined == baselineFA[p]) slotsStillBaseline++;
      }
      expect(slotsStillBaseline, equals(0),
          reason: 'All ${faIndexes.length} free-agent slots should have been overwritten by the '
              'earlier (successfully-inserted) free agents in the file, before the limit was hit');

      // Full extraction-and-compare: every successfully-inserted player's
      // committed name must equal exactly what the source file said for
      // that line — not just "didn't crash" or "round-trips with itself."
      // This file's Key= puts fname,lname first (column 0/1), unlike our
      // own exports (Position,fname,lname — column 1/2).
      final expectedByTeam = _parseExpectedNamesByTeam(text, fnameCol: 0, lnameCol: 1);
      int compared = 0, skippedExcess = 0;
      for (final team in expectedByTeam.keys) {
        final indexes = tool.GetPlayerIndexesForTeam(team);
        final expected = expectedByTeam[team]!;
        for (int i = 0; i < expected.length; i++) {
          if (i >= indexes.length) {
            skippedExcess++; // rejected line, already verified separately above
            continue;
          }
          final playerIndex = indexes[i];
          expect(tool.GetPlayerFirstName(playerIndex), equals(expected[i][0]),
              reason: 'team=$team index=$playerIndex (first name)');
          expect(tool.GetPlayerLastName(playerIndex), equals(expected[i][1]),
              reason: 'team=$team index=$playerIndex (last name)');
          compared++;
        }
      }
      expect(compared, equals(1937));
      expect(skippedExcess, equals(427));

      // No character silently corrupted in transit: every extracted name
      // above was already proven byte-exact against the source text, and
      // the source itself contains nothing outside safe single-byte range
      // (this format only ever writes one byte per character — see commit()).
      for (final teamNames in expectedByTeam.values) {
        for (final pair in teamNames) {
          for (final name in pair) {
            for (final code in name.codeUnits) {
              expect(code, lessThanOrEqualTo(0xFF),
                  reason: 'Source name "$name" has a character this format cannot represent');
            }
          }
        }
      }

      // Round trip — every successfully-inserted player, not just a sample.
      final tmp = '${Directory.systemTemp.path}/nfl2k5_pn_t12.dat';
      tool.SaveFile(tmp);
      final reloaded = GamesaveTool()..LoadSaveFile(tmp);
      for (final team in expectedByTeam.keys) {
        final indexes = tool.GetPlayerIndexesForTeam(team);
        for (int i = 0; i < expectedByTeam[team]!.length && i < indexes.length; i++) {
          final p = indexes[i];
          expect(reloaded.GetPlayerFirstName(p), equals(tool.GetPlayerFirstName(p)));
          expect(reloaded.GetPlayerLastName(p), equals(tool.GetPlayerLastName(p)));
        }
      }
      File(tmp).deleteSync();
    });

    test('truncation alone is sufficient for this file', () {
      // Before the draft-class-exclusion fix, this file's deficit was 11,119
      // bytes and truncation's 1,480-byte best case fell far short of it —
      // this test used to prove the "insufficient, fails safely" path with
      // real data. Excluding draft class (which never needed S3b space to
      // begin with) shrinks the deficit to 701 bytes, which truncation alone
      // now covers. That's not a weaker test — it's a direct, visible
      // consequence of the fix, worth asserting explicitly so a future
      // regression back to the old (wrong) numbers is caught here too. The
      // "insufficient, fails safely" case is still fully covered by T-PN-9
      // with deliberately-synthetic worst-case data.
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final text = File(testFile(_maddenConversion)).readAsStringSync();

      StaticUtils.Errors.clear();
      final names = collectPlayerNamesFromText(tool, text);
      final deficit = names.requiredBytes - PlayerNames.budget;
      expect(deficit, equals(701));

      final trunc = names.planTruncation();
      expect(trunc.entries.length, equals(187));
      expect(trunc.totalSavings, equals(1480));
      expect(trunc.totalSavings, greaterThanOrEqualTo(deficit),
          reason: 'Truncation alone now closes this file\'s (corrected) gap');
      names.applyTruncation(trunc);

      StaticUtils.Errors.clear();
      final result = commitPlayerNamesAndApplyRest(tool, text, names);

      expect(result.success, isTrue);
      expect(result.bytesUsed, lessThanOrEqualTo(PlayerNames.budget));
    });
  });

  // T-PN-14 — The headline regression guard: a genuine no-op export of the
  // stock franchise file must never need a dialog. This is exactly the bug
  // the user caught live (recording a demo GIF of "open the stock franchise
  // file, make one simple edit, export" and getting an unexpected overflow
  // dialog on a file that should just work) — draft-class players were being
  // modeled and charged against the S3b budget even though none of their
  // 762 name slots live in S3b at all (verified: every one of them resolves
  // into the separate, read-only college-name section in the real file).
  group('T-PN-14 Zero-edit franchise export stays silent', () {
    test('stock franchise file, zero edits, zero reduction: succeeds with room to spare', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final key = tool.GetKey(true, true);
      final text = '$key\n${tool.GetLeaguePlayers(true, true, false)}';

      final origFirst0 = tool.GetPlayerFirstName(0);
      final origLast0 = tool.GetPlayerLastName(0);

      final names = collectPlayerNamesFromText(tool, text);
      expect(names.requiredBytes, lessThanOrEqualTo(PlayerNames.budget),
          reason: 'A genuine no-op export must never need a reduction dialog');

      final result = commitPlayerNamesAndApplyRest(tool, text, names);
      expect(result.success, isTrue);
      expect(result.warnings, isEmpty);
      expect(tool.GetPlayerFirstName(0), equals(origFirst0));
      expect(tool.GetPlayerLastName(0), equals(origLast0));
    });
  });

  // T-PN-15 — The literal scenario from the demo GIF that caught this bug:
  // open the stock franchise file, make one simple edit, export.
  group('T-PN-15 Simple default-franchise edit stays silent', () {
    test('one first-name edit on the stock franchise file exports with no reduction needed', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final key = tool.GetKey(true, true);
      final origFirst = tool.GetPlayerFirstName(0);
      final origLast = tool.GetPlayerLastName(0);
      final text = '$key\n${tool.GetLeaguePlayers(true, true, false)}';
      final edited = text.replaceFirst('$origFirst,$origLast', 'Marcus,$origLast');

      final names = collectPlayerNamesFromText(tool, edited);
      expect(names.requiredBytes, lessThanOrEqualTo(PlayerNames.budget),
          reason: 'One simple name edit on the stock file must not trigger overflow');

      final result = commitPlayerNamesAndApplyRest(tool, edited, names);
      expect(result.success, isTrue);
      expect(result.warnings, isEmpty);
      expect(tool.GetPlayerFirstName(0), equals('Marcus'));
      expect(tool.GetPlayerLastName(0), equals(origLast));
    });
  });

  // T-PN-16 — Draft-class edits bypass PlayerNames entirely and go through
  // the original SetPlayerFirstName/LastName(..., useExistingName) path.
  group('T-PN-16 Draft-class edits are handled outside PlayerNames', () {
    test('editing a draft-class name to reuse an existing string still applies correctly', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final draftPlayer = GamesaveTool.FirstDraftClassPlayer;
      final existingFirst = tool.GetPlayerFirstName(0);
      final existingLast = tool.GetPlayerLastName(0);
      final origDraftFirst = tool.GetPlayerFirstName(draftPlayer);
      final origDraftLast = tool.GetPlayerLastName(draftPlayer);

      final key = tool.GetKey(true, true);
      final draftText = tool.GetDraftClass(true, true);
      final text = '$key\n${tool.GetLeaguePlayers(true, true, false)}\n$draftText';
      final edited = text.replaceFirst(
          '$origDraftFirst,$origDraftLast', '$existingFirst,$existingLast');

      final beforeBytes = PlayerNames.fromTool(tool).requiredBytes;
      final names = collectPlayerNamesFromText(tool, edited);
      expect(names.requiredBytes, equals(beforeBytes),
          reason: 'Draft-class edits must never affect the S3b budget');

      final result = commitPlayerNamesAndApplyRest(tool, edited, names);
      expect(result.success, isTrue);
      expect(tool.GetPlayerFirstName(draftPlayer), equals(existingFirst));
      expect(tool.GetPlayerLastName(draftPlayer), equals(existingLast));
    });
  });

  // T-PN-17 — System-resident draft-class-range entries (data physically
  // inside S3b despite being outside PlayerNames' editable domain) must
  // survive a repack unchanged, in both directions this session found real
  // bugs in: entries that were always there (Roster's fixed broadcast-booth
  // names), and an entry that happens to already point into S3b before any
  // edit (a rare but real pre-existing-save-state case).
  group('T-PN-17 System-resident draft-class-range entries survive repack', () {
    test('Roster broadcast-booth names round-trip through a non-dedup commit', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      final booth = <int, (String, String)>{};
      for (int p = GamesaveTool.FirstDraftClassPlayer; p <= tool.mMaxPlayers; p++) {
        booth[p] = (tool.GetPlayerFirstName(p), tool.GetPlayerLastName(p));
      }
      expect(booth.values.any((n) => n.$1.isNotEmpty || n.$2.isNotEmpty), isTrue,
          reason: 'Sanity check that this fixture really has system-resident content to protect');

      final names = PlayerNames.fromTool(tool);
      final result = names.commit();
      expect(result.success, isTrue);
      expect(tool.checkNamePointers(), isFalse,
          reason: 'A non-dedup commit must never leave two fields aliasing the same address — '
              'this caught a real bug where an un-retargeted empty pointer coincidentally '
              'resolved into newly-repacked content after the pool moved');

      for (final entry in booth.entries) {
        expect(tool.GetPlayerFirstName(entry.key), equals(entry.value.$1));
        expect(tool.GetPlayerLastName(entry.key), equals(entry.value.$2));
      }

      final tmp = '${Directory.systemTemp.path}/nfl2k5_pn_t17.dat';
      tool.SaveFile(tmp);
      final reloaded = GamesaveTool()..LoadSaveFile(tmp);
      for (final entry in booth.entries) {
        expect(reloaded.GetPlayerFirstName(entry.key), equals(entry.value.$1));
        expect(reloaded.GetPlayerLastName(entry.key), equals(entry.value.$2));
      }
      File(tmp).deleteSync();
    });

    test('a draft-class pointer that already resolves into S3b before any edit is preserved, '
        'not corrupted, by an unrelated commit', () {
      // Simulates a rare but real pre-existing save-state: some draft-class
      // player's name pointer already resolves into S3b (e.g. a leftover
      // from a prior useExistingName edit) *before* this session's edit ever
      // starts, and this session's text never mentions that player at all.
      // Before this fix, PlayerNames didn't model it, so commit()'s repack
      // either corrupted it (read back as garbage) or, after an interim fix,
      // refused to commit at all. Now it's modeled read-only and correctly
      // preserved through the repack.
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final draftPlayer = GamesaveTool.FirstDraftClassPlayer + 5;
      const kPlayerDataLength = 0x54;
      final p0First = tool.GetPlayerFirstName(0);
      final p0PtrLoc = 0 * kPlayerDataLength + tool.FirstPlayerFnamePointerLoc;
      final p0Dest = tool.GetPointerDestination(p0PtrLoc);
      final draftPtrLoc = draftPlayer * kPlayerDataLength + tool.FirstPlayerFnamePointerLoc;
      final value = p0Dest - draftPtrLoc + 1;
      tool.SetByte(draftPtrLoc, value & 0xff);
      tool.SetByte(draftPtrLoc + 1, (value >> 8) & 0xff);
      tool.SetByte(draftPtrLoc + 2, (value >> 16) & 0xff);
      tool.SetByte(draftPtrLoc + 3, (value >> 24) & 0xff);
      expect(tool.GetPlayerFirstName(draftPlayer), equals(p0First),
          reason: 'Sanity check that the manual poke really did alias player 0\'s first name');

      final key = tool.GetKey(true, true);
      final origP0Last = tool.GetPlayerLastName(0);
      final text = '$key\n${tool.GetLeaguePlayers(true, true, false)}';
      final edited = text.replaceFirst('$p0First,$origP0Last', 'Marcus,$origP0Last');

      final names = collectPlayerNamesFromText(tool, edited);
      final result = commitPlayerNamesAndApplyRest(tool, edited, names);

      expect(result.success, isTrue);
      expect(tool.GetPlayerFirstName(draftPlayer), equals(p0First),
          reason: 'The pre-existing alias must survive an unrelated commit unchanged');
    });
  });
}
