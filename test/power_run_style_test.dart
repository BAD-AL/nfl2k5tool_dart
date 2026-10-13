// T-PRS-1 — PowerRunStyle round-trips through its enum *value*, not its
// ordinal index.
//
// PowerRunStyle has explicit, non-sequential values (Finesse=1, Balanced=50,
// Power=99) -- see lib/enum_definitions.dart. The read side (GetAttribute)
// already matched on `.value`; the enum-name write side (SetAttribute) used
// to match on `.index` (0/1/2), a translation slip from the C# original's
// `(byte)style` cast, which yields the underlying value, not the ordinal.
//
// Impact: the generated text carries this field by name (e.g. "Balanced"),
// so a plain extract -> apply-unchanged round trip exercised the broken
// write path for every player with an enum-named style and silently
// corrupted the byte -- 1696/2317 players changed on a no-op apply against
// Base2004Fran_Orig.zip before this fix (Balanced(50) -> 1, which is itself
// a valid value and reads back as "Finesse", not an obvious error).
import 'dart:io';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/gamesave_tool_io.dart';
import 'package:test/test.dart';

String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

const int _kPowerRunStyleOffset = 0x4d;

List<int> _snapshotPrsBytes(GamesaveTool tool) {
  final out = <int>[];
  for (int p = 0; p < tool.mMaxPlayers; p++) {
    final start = tool.GetPlayerDataStart(p);
    if (start < 0) continue;
    out.add(tool.GameSaveData![start + _kPowerRunStyleOffset]);
  }
  return out;
}

void main() {
  group('T-PRS-1 PowerRunStyle round-trips via its enum value', () {
    test('SetAttribute/GetAttribute round-trip for each named style', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
      const player = 0;

      for (final name in ['Finesse', 'Balanced', 'Power']) {
        tool.SetAttribute(player, PlayerOffsets.PowerRunStyle, name);
        final readBack = tool.GetAttribute(player, PlayerOffsets.PowerRunStyle);
        expect(readBack, equals(name),
            reason: 'writing "$name" must read back as "$name", not its ordinal index');
      }
    });

    test('byte value matches the enum\'s explicit value, not its ordinal', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
      const player = 0;
      final start = tool.GetPlayerDataStart(player);

      tool.SetAttribute(player, PlayerOffsets.PowerRunStyle, 'Balanced');
      expect(tool.GameSaveData![start + _kPowerRunStyleOffset], equals(PowerRunStyle.Balanced.value));
      expect(tool.GameSaveData![start + _kPowerRunStyleOffset], isNot(equals(PowerRunStyle.Balanced.index)));

      tool.SetAttribute(player, PlayerOffsets.PowerRunStyle, 'Power');
      expect(tool.GameSaveData![start + _kPowerRunStyleOffset], equals(PowerRunStyle.Power.value));
    });

    test('a no-op extract-then-apply round trip leaves every PowerRunStyle byte unchanged', () {
      // The realistic scenario that exposed the bug's real severity: the
      // generated text carries this field by name for every player, so a
      // plain re-apply of unmodified text exercises the write path for all
      // of them, not just a hand-picked one.
      final tool = GamesaveTool()..LoadSaveFile(testFile('Base2004Fran_Orig.zip'));
      final before = _snapshotPrsBytes(tool);

      final key = tool.GetKey(true, true);
      final text = '$key\n${tool.GetLeaguePlayers(true, true, false)}';
      InputParser(tool).ProcessText(text);

      final after = _snapshotPrsBytes(tool);
      expect(after, equals(before),
          reason: 'extracting and re-applying unmodified text must not alter any '
              'PowerRunStyle byte');
    });
  });
}
