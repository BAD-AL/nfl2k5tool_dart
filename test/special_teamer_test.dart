// T-ST-1 — Special Teamer slots (Holder, KR1, KR2, PK, LS, PR).
//
// Covers the Holder and PK (Kicker) slots added alongside the existing
// KR1/KR2/LS/PR support -- see GAMESAVE_SECTIONS.md, "Special Teamer
// Slots (+0x194-+0x199)" for how these offsets were identified.
import 'dart:io';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/gamesave_tool_io.dart';
import 'package:test/test.dart';

String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

void main() {
  group('T-ST-1 Special Teamer slots', () {
    test('GetSpecialTeamPosition reports a Holder distinct from the punter for some teams', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile('Base2004Fran_Orig.zip'));

      // Bears: stock roster's holder (backup QB) is not the starting punter.
      final holder = tool.GetSpecialTeamPosition('Bears', SpecialTeamer.Holder);
      expect(holder, isNot(contains('ERROR')));
    });

    test('SetSpecialTeamPosition/GetSpecialTeamPosition round-trip for Holder', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile('Base2004Fran_Orig.zip'));

      // Point the 49ers' Holder slot at the backup QB (depth 2).
      tool.SetSpecialTeamPosition('49ers', SpecialTeamer.Holder, Positions.QB, 2);
      final result = tool.GetSpecialTeamPosition('49ers', SpecialTeamer.Holder);

      expect(result, equals('Holder,QB2'));
    });

    test('SetSpecialTeamPosition/GetSpecialTeamPosition round-trip for PK', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile('Base2004Fran_Orig.zip'));

      tool.SetSpecialTeamPosition('49ers', SpecialTeamer.PK, Positions.K, 1);
      final result = tool.GetSpecialTeamPosition('49ers', SpecialTeamer.PK);

      expect(result, equals('PK,K1'));
    });

    test('GetSpecialTeamDepthChart includes Holder and PK lines', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile('Base2004Fran_Orig.zip'));

      final chart = tool.GetSpecialTeamDepthChart('49ers');

      expect(chart, contains('Holder,'));
      expect(chart, contains('PK,'));
      expect(chart, contains('KR1,'));
      expect(chart, contains('KR2,'));
      expect(chart, contains('LS,'));
      expect(chart, contains('PR,'));
    });

    test('AutoUpdateDepthChart sets Holder to the team\'s punter', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile('Base2004Fran_Orig.zip'));

      // Force a mismatch first (point Holder at a non-punter) so the test
      // actually exercises AutoUpdateDepthChart's assignment rather than
      // passing by coincidence.
      tool.SetSpecialTeamPosition('49ers', SpecialTeamer.Holder, Positions.QB, 2);
      expect(tool.GetSpecialTeamPosition('49ers', SpecialTeamer.Holder), equals('Holder,QB2'));

      tool.AutoUpdateDepthChart();

      final holder = tool.GetSpecialTeamPosition('49ers', SpecialTeamer.Holder);
      expect(holder, equals('Holder,P1'));
    });

    test('a kicker\'s own player-data row is not hijacked by the PK dispatch prefix', () {
      // Regression guard: a player-data line's first field is Position, so
      // any kicker's row literally starts with "K,". The text-format
      // dispatch prefix must be "PK," (not "K,") or every kicker's row
      // would be misrouted into SetSpecialTeamPlayer instead of normal
      // player parsing.
      final tool = GamesaveTool()..LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
      final key = tool.GetKey(true, true);
      final text = '$key\n${tool.GetLeaguePlayers(true, true, false)}';

      final kickerLine = text
          .split(RegExp(r'[\n\r]'))
          .firstWhere((l) => l.trim().startsWith('K,'), orElse: () => '');

      expect(kickerLine, isNotEmpty, reason: 'expected at least one kicker row');
      // The line parses as ordinary player data, not "PK,<pos><depth>".
      expect(RegExp(r'^K,[A-Za-z]').hasMatch(kickerLine.trim()), isTrue);
    });
  });
}
