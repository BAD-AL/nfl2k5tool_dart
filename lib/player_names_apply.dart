// Thin orchestration glue between InputParser's line-by-line text processing
// and PlayerNames' read-decide-commit model. Keeps PlayerNames free of any
// text-parsing knowledge and InputParser free of any budget/reduction
// knowledge.
import 'dart:typed_data';

import 'gamesave_tool.dart';
import 'input_parser.dart';
import 'logger.dart';
import 'player_names.dart';

/// Matches an uncommented 'Team = X' line anywhere in [text] — the only
/// thing that enters ParsingStates.PlayerModification, InputParser's one
/// state that performs real, budget-relevant name writes (see
/// InputParser.mTeamRegex). Every other state — PlayerLookupAndApply
/// ('LookupAndModify'), PlayerLookupAndVerify ('LookupAndVerify'), and
/// PlayerLookup (bare 'LookupPlayer') — either can't change a name's value
/// (LookupAndModify's FindPlayer lookup is exact-match, so any name it
/// "reapplies" is always byte-identical to what's already there) or never
/// calls NameSetter at all (the other two are read-only). So the presence
/// or absence of those specific markers doesn't actually matter to this
/// decision — only whether PlayerModification is ever entered does, and
/// that's exactly what this single check answers.
final RegExp _uncommentedTeamSectionRe =
    RegExp(r'^\s*(?!#).*Team\s*=\s*[0-9a-zA-Z]+', caseSensitive: false, multiLine: true);

/// Pass 1 (collect): builds a PlayerNames baseline from [tool]'s current
/// save data, then replays [text] through InputParser once so every pending
/// FirstName/LastName edit is captured in the model instead of written to
/// the gamesave. Every other attribute in [text] is also applied during this
/// pass — that's necessary busywork, not harmless: it writes to
/// [GameSaveData] before the caller knows whether a name commit will even
/// succeed, so a pre-write snapshot is taken first and stored on [names] for
/// [commitPlayerNamesAndApplyRest] to restore from if the commit fails.
///
/// Exception: text with no Team= section never enters PlayerModification —
/// InputParser's one state that performs real, budget-relevant name writes
/// (see _uncommentedTeamSectionRe's doc comment for why nothing else that
/// can appear in [text] needs separate handling here). The S3b budget check
/// has nothing to protect in that case and is skipped entirely; [text] is
/// instead run straight through the original, pre-PlayerNames InputParser
/// path (see [PlayerNames.bypassed]).
PlayerNames collectPlayerNamesFromText(GamesaveTool tool, String text) {
  final names = PlayerNames.fromTool(tool);
  names.preCollectSnapshot = Uint8List.fromList(tool.GameSaveData!);

  final bypass = !_uncommentedTeamSectionRe.hasMatch(text);
  if (bypass) {
    names.bypassed = true;
    InputParser(tool).ProcessText(text);
    return names;
  }

  Logger.log('Performing player name space check');
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
///
/// If [names] is [PlayerNames.bypassed], [collectPlayerNamesFromText] already
/// ran [text] through the original, unchecked InputParser path in full —
/// there's nothing left to commit or replay, so this returns immediately.
CommitResult commitPlayerNamesAndApplyRest(GamesaveTool tool, String text, PlayerNames names) {
  if (names.bypassed) {
    return CommitResult(
      success: true,
      bytesUsed: names.requiredBytes,
      bytesFree: PlayerNames.budget - names.requiredBytes,
    );
  }
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
