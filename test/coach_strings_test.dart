import 'dart:io';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/gamesave_tool_io.dart';
import 'package:test/test.dart';

String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

const String _franchise = 'Base2004Fran_Orig.zip';

/// Reads a coach string field's exact stored text, bypassing
/// GetCoachAttribute's CSV-safety quote-wrapping for comma-containing
/// strings (that wrapping is display-only — see CoachStrings._load's doc
/// comment) so tests can compare before/after values exactly regardless of
/// whether the real text happens to contain a comma.
String _rawCoachString(GamesaveTool tool, int coach, CoachOffsets attr) =>
    tool.GetName(tool.GetPointerDestination(tool.GetCoachPointer(coach)) + attr.value);

void main() {
  // T-CS-1 — Capacity
  group('T-CS-1 Capacity', () {
    test('budget is 2648 characters (5297 bytes)', () {
      expect(CoachStrings.budget, equals(5297));
    });

    test('stock franchise file fits within budget with zero edits', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final strings = CoachStrings.fromTool(tool);
      // The stock file is verified (see the earlier investigation this test
      // guards against regressing) to sit right at capacity — zero trailing
      // free bytes — but not over it. A completely untouched file must
      // never appear to already exceed its own budget.
      expect(strings.requiredBytes, lessThanOrEqualTo(CoachStrings.budget));
    });
  });

  // T-CS-2 — Order-independent batch commit on a full stock file
  group('T-CS-2 Order-independent batch commit', () {
    // The stock file has essentially zero real slack (verified: 5296 of
    // 5297 bytes already used), so a single field growing in isolation
    // genuinely doesn't fit — that's correct behavior, not a bug (see the
    // commit history of this test for the earlier, mistaken version that
    // expected otherwise). What CoachStrings actually fixes is different:
    // a batch that shrinks one field and grows another, netting out to fit,
    // must succeed regardless of which order the edits happen to be
    // processed in — today's real per-field mechanism (reproduced directly
    // against this same file earlier this session) can spuriously reject
    // the growth if it's processed before the shrink that would have freed
    // enough room, purely because it only ever inspects the pool's tail at
    // the moment of that one edit. Aggregate, all-at-once evaluation makes
    // the processing order irrelevant.
    test('shrinking one field and growing another nets out and succeeds, '
        'regardless of edit order', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final strings = CoachStrings.fromTool(tool);

      final coach0Before = _rawCoachString(tool, 0, CoachOffsets.Info1);
      const shrunk = 'Veteran.';
      // A fixed replacement, not an append to coach 1's real (unknown-length)
      // text — keeps the byte math independent of real save-file content
      // and safely under the per-field read cap.
      const grown = 'A fiery leader who commands respect.';
      expect(shrunk.length, lessThan(coach0Before.length),
          reason: 'Sanity check that this really is a shrink');
      expect(grown.length, lessThanOrEqualTo(CoachStrings.maxFieldChars),
          reason: 'Sanity check that this stays under the per-field read cap');

      // Apply the growing edit FIRST, before the shrink that frees room for
      // it — the exact ordering today's per-field mechanism is sensitive to.
      strings.overlayEdit(1, CoachOffsets.Info1, grown);
      strings.overlayEdit(0, CoachOffsets.Info1, shrunk);

      final result = strings.commit();

      expect(result.success, isTrue, reason: 'warnings: ${result.warnings}');
      expect(_rawCoachString(tool, 0, CoachOffsets.Info1), equals(shrunk));
      expect(_rawCoachString(tool, 1, CoachOffsets.Info1), equals(grown));
    });
  });
}
