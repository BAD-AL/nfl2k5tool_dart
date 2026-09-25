import 'dart:io';
import 'dart:typed_data';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/gamesave_tool_io.dart';
import 'package:test/test.dart';

String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

const String _franchise = 'Base2004Fran_Orig.zip';

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Full text for [tool]: players + coaches (with Info1/2/3 included, unlike
/// the default coach key) — the shape a real combined "Apply to Save"/
/// "Export Save" text actually has.
String _fullText(GamesaveTool tool) {
  tool.CoachKey = 'Coach,Team,FirstName,LastName,Info1,Info2,Info3';
  final key = tool.GetKey(true, true);
  return '$key\n${tool.GetLeaguePlayers(true, true, false)}${tool.GetCoachDataAll()}';
}

void main() {
  group('T-TA-1 Zero-edit combined export stays silent', () {
    test('stock franchise file: zero edits, both names and coach strings commit', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final text = _fullText(tool);

      final collected = collectEditsFromText(tool, text);
      final result = commitEditsAndApplyRest(tool, text, collected);

      expect(result.success, isTrue, reason: 'warnings: ${result.warnings}');
      expect(result.nameResult?.success, isTrue);
      expect(result.coachResult?.success, isTrue);
    });
  });

  group('T-TA-2 Combined edit in one pass', () {
    test('a player name edit and a coach Info edit in the same text both apply', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final text = _fullText(tool);

      final origFirst = tool.GetPlayerFirstName(0);
      final origLast = tool.GetPlayerLastName(0);
      final origInfo1 = tool.GetCoachAttribute(0, CoachOffsets.Info1);

      var edited = text.replaceFirst('$origFirst,$origLast', 'Marcus,$origLast');
      // Coach lines are written as Coach,Team,FirstName,LastName,Info1,Info2,Info3
      // per the CoachKey set in _fullText — replace coach 0's Info1 value
      // (whatever it currently is) with a short, known replacement.
      edited = edited.replaceFirst(origInfo1, 'A steady hand on the sideline.');

      final collected = collectEditsFromText(tool, edited);
      final result = commitEditsAndApplyRest(tool, edited, collected);

      expect(result.success, isTrue, reason: 'warnings: ${result.warnings}');
      expect(tool.GetPlayerFirstName(0), equals('Marcus'));
      expect(tool.GetPlayerLastName(0), equals(origLast));
      expect(tool.GetCoachAttribute(0, CoachOffsets.Info1),
          equals('A steady hand on the sideline.'));
    });
  });

  group('T-TA-3 Atomic rollback', () {
    test('a coach-strings failure rolls back an already-successful name commit too', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final snapshot = Uint8List.fromList(tool.GameSaveData!);
      final text = _fullText(tool);

      final origFirst = tool.GetPlayerFirstName(0);
      final origLast = tool.GetPlayerLastName(0);

      var edited = text.replaceFirst('$origFirst,$origLast', 'Marcus,$origLast');
      // Grow every coach's Info1 to something guaranteed to blow the pool
      // budget, forcing coachStrings.commit() to fail after names.commit()
      // already succeeded.
      const bigInfo1 = 'This coach biography has been deliberately made '
          'far too long to fit in the available budget for testing.';
      for (int i = 0; i < 32; i++) {
        final orig = tool.GetCoachAttribute(i, CoachOffsets.Info1);
        if (orig.isNotEmpty && edited.contains(orig)) {
          edited = edited.replaceFirst(orig, bigInfo1);
        }
      }

      final collected = collectEditsFromText(tool, edited);
      final result = commitEditsAndApplyRest(tool, edited, collected);

      expect(result.success, isFalse);
      expect(result.coachResult?.success, isFalse,
          reason: 'The oversized batch should fail at the coach-strings '
              'commit, after names.commit() already succeeded.');
      expect(_bytesEqual(tool.GameSaveData!, snapshot), isTrue,
          reason: 'A failed combined commit must leave GameSaveData '
              'completely untouched, including undoing the name change '
              'that already succeeded before the coach-strings commit ran.');
    });
  });
}
