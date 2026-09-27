import 'dart:io';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/gamesave_tool_io.dart';
import 'package:test/test.dart';

String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

const String _franchise = 'Base2004Fran_Orig.zip';

void main() {
  group('T-PBV-1 SetTeamString rejects an invalid playbook name', () {
    test('a made-up playbook name is rejected with the new wording', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      StaticUtils.Errors.clear();

      tool.SetTeamString(0, TeamDataOffsets.Playbook, 'PB_WAS_Comm');

      expect(StaticUtils.Errors, isNotEmpty);
      expect(StaticUtils.Errors.last, contains('not a valid playbook'));
      expect(StaticUtils.Errors.last, isNot(contains('unknown playbook')));
    });

    test('a real playbook name still applies correctly (no regression)', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      StaticUtils.Errors.clear();

      tool.SetTeamString(0, TeamDataOffsets.Playbook, 'PB_Bears');

      expect(StaticUtils.Errors, isEmpty);
      expect(tool.GetTeamString(0, TeamDataOffsets.Playbook), equals('PB_Bears'));
    });
  });
}
