import 'dart:io';
import 'dart:typed_data';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/gamesave_tool_io.dart';
import 'package:test/test.dart';

String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

const String _roster = 'BaseRoster/SAVEGAME.DAT';
const String _franchise = 'Base2004Fran_Orig.zip';

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  group('T-CHP-1 Clears every player\'s pointer on a Roster file', () {
    test('all players\' +0x2C bytes are zero after clearing', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));

      tool.ClearHistoricPlayerStats();

      for (int player = 0; player < tool.MaxPlayers; player++) {
        final rec = tool.mPlayerStart + player * 0x54;
        expect(tool.GameSaveData![rec + 0x2c], equals(0),
            reason: 'player $player byte +0x2C');
        expect(tool.GameSaveData![rec + 0x2d], equals(0),
            reason: 'player $player byte +0x2D');
        expect(tool.GameSaveData![rec + 0x2e], equals(0),
            reason: 'player $player byte +0x2E');
        expect(tool.GameSaveData![rec + 0x2f], equals(0),
            reason: 'player $player byte +0x2F');
      }
    });
  });

  group('T-CHP-2 No-op safety guard on a Franchise file', () {
    test('GameSaveData is byte-for-byte unchanged on a Franchise save', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_franchise));
      final snapshot = Uint8List.fromList(tool.GameSaveData!);

      tool.ClearHistoricPlayerStats();

      expect(_bytesEqual(tool.GameSaveData!, snapshot), isTrue,
          reason: 'ClearHistoricPlayerStats must never touch a Franchise '
              'save -- it could destroy real, live season/career stats.');
    });
  });

  group('T-CHP-3 Only touches +0x2C..+0x2F per player, nothing else', () {
    test('every changed byte falls within some player\'s pointer span', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      final before = Uint8List.fromList(tool.GameSaveData!);

      tool.ClearHistoricPlayerStats();

      final after = tool.GameSaveData!;
      final validOffsets = <int>{};
      for (int player = 0; player < tool.MaxPlayers; player++) {
        final rec = tool.mPlayerStart + player * 0x54;
        validOffsets.addAll([rec + 0x2c, rec + 0x2d, rec + 0x2e, rec + 0x2f]);
      }

      for (int i = 0; i < before.length; i++) {
        if (before[i] != after[i]) {
          expect(validOffsets.contains(i), isTrue,
              reason: 'byte at 0x${i.toRadixString(16)} changed but is not '
                  'any player\'s +0x2C..+0x2F pointer span');
        }
      }
    });

    test('is idempotent -- a second call changes nothing further', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      tool.ClearHistoricPlayerStats();
      final afterFirst = Uint8List.fromList(tool.GameSaveData!);

      tool.ClearHistoricPlayerStats();

      expect(_bytesEqual(tool.GameSaveData!, afterFirst), isTrue);
    });
  });

  group('T-CHP-4 InputParser wiring', () {
    test('text without the tag leaves pointers untouched', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));
      final snapshot = Uint8List.fromList(tool.GameSaveData!);

      InputParser(tool).ProcessText('SomeOtherLine=1');

      expect(_bytesEqual(tool.GameSaveData!, snapshot), isTrue);
    });

    test('text with the tag clears pointers', () {
      final tool = GamesaveTool()..LoadSaveFile(testFile(_roster));

      InputParser(tool).ProcessText('ClearHistoricPlayerStats');

      final rec = tool.mPlayerStart;
      expect(tool.GameSaveData![rec + 0x2c], equals(0));
      expect(tool.GameSaveData![rec + 0x2d], equals(0));
      expect(tool.GameSaveData![rec + 0x2e], equals(0));
      expect(tool.GameSaveData![rec + 0x2f], equals(0));
    });
  });
}
