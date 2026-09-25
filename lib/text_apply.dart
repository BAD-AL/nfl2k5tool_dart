// Combined orchestration for the two independent, budget-checked pools a
// single text-apply pass needs to collect before committing anything:
// PlayerNames (S3b player-name pool) and CoachStrings (coach-string pool).
//
// They can't each run their own InputParser pass the way player_names_apply.dart
// alone does: InputParser.ProcessText applies every other attribute in the
// text too (positions, stats, schedule, formulas, ...) — running it twice
// would double-apply all of that, not just names and coach strings. So both
// NameSetter and CoachStringSetter are wired onto one InputParser instance,
// processed in a single pass, here.
import 'dart:typed_data';

import 'coach_strings.dart';
import 'gamesave_tool.dart';
import 'input_parser.dart';
import 'logger.dart';
import 'player_names.dart';

/// Matches an uncommented 'Team = X' line anywhere in [text] — see
/// player_names_apply.dart's identical constant for the full reasoning.
/// Coach lines have no equivalent bypass condition: InputParser recognizes
/// 'Coach,...' lines unconditionally, independent of mCurrentState/
/// PlayerModification, so CoachStrings' check always engages when coach
/// data is present, regardless of what else is in the text.
final RegExp _uncommentedTeamSectionRe =
    RegExp(r'^\s*(?!#).*Team\s*=\s*[0-9a-zA-Z]+', caseSensitive: false, multiLine: true);

/// The two models built by [collectEditsFromText], carried through to
/// [commitEditsAndApplyRest].
class CollectedEdits {
  final PlayerNames names;
  final CoachStrings coachStrings;
  final Uint8List preCollectSnapshot;

  CollectedEdits(this.names, this.coachStrings, this.preCollectSnapshot);
}

/// The result of [commitEditsAndApplyRest] — both individual results, plus
/// [success] which is true only when both commits succeeded. Either result
/// is null when that model's commit was never attempted: [nameResult] when
/// player names were bypassed entirely (see [PlayerNames.bypassed]),
/// [coachResult] when [nameResult] already failed, since names.commit() is
/// always tried first and a failure there stops everything.
class EditCommitResult {
  final bool success;
  final CommitResult? nameResult;
  final CommitResult? coachResult;

  EditCommitResult({required this.success, this.nameResult, this.coachResult});

  /// Every warning from whichever model(s) actually reported one.
  List<String> get warnings => [
        ...?nameResult?.warnings,
        ...?coachResult?.warnings,
      ];
}

/// Pass 1 (collect): builds PlayerNames and CoachStrings baselines from
/// [tool]'s current save data, then replays [text] through InputParser once
/// so every pending name/coach-string edit is captured in the appropriate
/// model instead of written to the gamesave. Every other attribute in
/// [text] is also applied during this pass — that's necessary busywork, not
/// harmless: it writes to [GameSaveData] before the caller knows whether
/// either commit will even succeed, so a pre-write snapshot is taken first
/// and stored on the returned [CollectedEdits] for
/// [commitEditsAndApplyRest] to restore from if either commit fails.
///
/// See [PlayerNames.bypassed] for when player-name edits skip the S3b
/// budget check entirely (text with no Team= section) — CoachStrings has no
/// equivalent bypass and always engages.
CollectedEdits collectEditsFromText(GamesaveTool tool, String text) {
  final names = PlayerNames.fromTool(tool);
  final coachStrings = CoachStrings.fromTool(tool);
  final snapshot = Uint8List.fromList(tool.GameSaveData!);

  final bypassNames = !_uncommentedTeamSectionRe.hasMatch(text);
  names.bypassed = bypassNames;
  if (!bypassNames) {
    Logger.log('Performing player name space check');
  }

  final parser = InputParser(tool);
  parser.NameSetter = (player, isLastName, value, useExistingName) {
    if (!bypassNames && player < GamesaveTool.FirstDraftClassPlayer) {
      names.overlayEdit(player, isLastName, value);
    } else {
      _writeNameDirectly(tool, player, isLastName, value, useExistingName);
    }
  };
  parser.CoachStringSetter = (teamIndex, attr, value) {
    coachStrings.overlayEdit(teamIndex, attr, value);
  };
  parser.ProcessText(text);

  return CollectedEdits(names, coachStrings, snapshot);
}

/// See player_names_apply.dart's _writeDraftClassName — identical, just
/// renamed here since this call site also uses it for the "player names
/// bypassed entirely" case, not only draft-class rows.
void _writeNameDirectly(
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

/// Commits both [collected.names] and [collected.coachStrings] (after the
/// caller has applied whatever reduction plans it chose for either), then
/// replays [text] through InputParser a second time with name/coach-string
/// writes skipped (already committed) so every other attribute gets applied
/// as usual. If either commit fails, [tool]'s GameSaveData is restored to
/// its state from before [collectEditsFromText] ever ran and the second
/// pass is skipped — the caller can treat this as "nothing was saved," even
/// though the collect pass already wrote non-name/non-coach-string
/// attributes in the meantime.
EditCommitResult commitEditsAndApplyRest(
    GamesaveTool tool, String text, CollectedEdits collected) {
  final names = collected.names;
  final coachStrings = collected.coachStrings;

  void restore() => tool.GameSaveData!.setAll(0, collected.preCollectSnapshot);

  CommitResult? nameResult;
  if (!names.bypassed) {
    nameResult = names.commit();
    if (!nameResult.success) {
      restore();
      return EditCommitResult(success: false, nameResult: nameResult);
    }
  }

  final coachResult = coachStrings.commit();
  if (!coachResult.success) {
    restore();
    return EditCommitResult(success: false, nameResult: nameResult, coachResult: coachResult);
  }

  final parser = InputParser(tool);
  parser.NameSetter = (player, isLastName, value, useExistingName) {
    // Team/FreeAgent rows (when not bypassed): already written by
    // names.commit() above, no-op here.
    if (names.bypassed || player >= GamesaveTool.FirstDraftClassPlayer) {
      _writeNameDirectly(tool, player, isLastName, value, useExistingName);
    }
  };
  parser.CoachStringSetter = (teamIndex, attr, value) {
    // Already written by coachStrings.commit() above — every coach string
    // field, edited or not, was rewritten by that single repack, so there's
    // nothing left for this second pass to do.
  };
  parser.ProcessText(text);

  return EditCommitResult(success: true, nameResult: nameResult, coachResult: coachResult);
}
