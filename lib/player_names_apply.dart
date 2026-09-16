// Thin orchestration glue between InputParser's line-by-line text processing
// and PlayerNames' read-decide-commit model. Keeps PlayerNames free of any
// text-parsing knowledge and InputParser free of any budget/reduction
// knowledge.
import 'dart:typed_data';

import 'gamesave_tool.dart';
import 'input_parser.dart';
import 'player_names.dart';

/// Pass 1 (collect): builds a PlayerNames baseline from [tool]'s current
/// save data, then replays [text] through InputParser once so every pending
/// FirstName/LastName edit is captured in the model instead of written to
/// the gamesave. Every other attribute in [text] is also applied during this
/// pass — that's necessary busywork, not harmless: it writes to
/// [GameSaveData] before the caller knows whether a name commit will even
/// succeed, so a pre-write snapshot is taken first and stored on [names] for
/// [commitPlayerNamesAndApplyRest] to restore from if the commit fails.
PlayerNames collectPlayerNamesFromText(GamesaveTool tool, String text) {
  final names = PlayerNames.fromTool(tool);
  names.preCollectSnapshot = Uint8List.fromList(tool.GameSaveData!);
  final parser = InputParser(tool)
    ..NameSetter = (player, isLastName, value, useExistingName) {
      if (player < GamesaveTool.FirstDraftClassPlayer) {
        names.overlayEdit(player, isLastName, value);
      } else {
        _writeDraftClassName(tool, player, isLastName, value, useExistingName);
      }
    };
  parser.ProcessText(text);
  return names;
}

/// Draft-class rows are entirely outside PlayerNames' domain (see
/// PlayerNames._load) — their names never live in S3b, so they're written
/// directly via the same path InputParser used before this feature existed,
/// preserving the useExistingName constraint InsertPlayer already enforces
/// for them.
void _writeDraftClassName(
  GamesaveTool tool,
  int player,
  bool isLastName,
  String value,
  bool useExistingName,
) {
  if (isLastName) {
    tool.SetPlayerLastName(player, value, useExistingName);
  } else {
    tool.SetPlayerFirstName(player, value, useExistingName);
  }
}

/// Commits [names] (after the caller has applied whatever reduction plans it
/// chose) as the single real write to the player-name pool, then replays
/// [text] through InputParser a second time with name writes skipped (already
/// committed) so every other attribute gets applied as usual. If the commit
/// fails (still over budget, or an unmanaged-data overlap), [tool]'s
/// GameSaveData is restored to its state from before [collectPlayerNamesFromText]
/// ever ran and the second pass is skipped — the caller can treat this as
/// "nothing was saved," even though the collect pass already wrote non-name
/// attributes in the meantime.
CommitResult commitPlayerNamesAndApplyRest(GamesaveTool tool, String text, PlayerNames names) {
  final result = names.commit();
  if (!result.success) {
    final snapshot = names.preCollectSnapshot;
    if (snapshot != null) {
      tool.GameSaveData!.setAll(0, snapshot);
    }
    return result;
  }
  final parser = InputParser(tool)
    ..NameSetter = (player, isLastName, value, useExistingName) {
      // Team/FreeAgent rows: already written by commit() above, no-op here.
      if (player >= GamesaveTool.FirstDraftClassPlayer) {
        _writeDraftClassName(tool, player, isLastName, value, useExistingName);
      }
    };
  parser.ProcessText(text);
  return result;
}
