// Load-time health check for a save file, aggregating three existing,
// otherwise-unconnected checks: player-names budget, coach-strings budget,
// and shared/aliased name pointers. Purely diagnostic -- no fix is applied.

import 'coach_strings.dart';
import 'gamesave_tool.dart';
import 'player_names.dart';

class SaveFileHealthIssues {
  final int playerNamesOverBy; // bytes over budget; 0 if not over
  final int coachStringsOverBy; // bytes over budget; 0 if not over
  final bool sharedNamePointers;
  final List<String> teamsWithInvalidPlaybooks;

  SaveFileHealthIssues({
    required this.playerNamesOverBy,
    required this.coachStringsOverBy,
    required this.sharedNamePointers,
    required this.teamsWithInvalidPlaybooks,
  });

  bool get hasAnyIssue =>
      playerNamesOverBy > 0 ||
      coachStringsOverBy > 0 ||
      sharedNamePointers ||
      teamsWithInvalidPlaybooks.isNotEmpty;
}

/// Checks [tool]'s currently-loaded, unedited data against the fixed-size
/// pools it must fit in, plus name-pointer integrity. Safe to call on any
/// freshly-loaded file -- reads only, no writes.
SaveFileHealthIssues checkSaveFileHealth(GamesaveTool tool) {
  final namesOverBy =
      PlayerNames.fromTool(tool).requiredBytes - PlayerNames.budget;
  final coachOverBy =
      CoachStrings.fromTool(tool).requiredBytes - CoachStrings.budget;
  final invalidPlaybookTeams = <String>[];
  for (int t = 0; t < 32; t++) {
    if (!GamesaveTool.ValidPlaybookNames.contains(tool.GetTeamPlaybookName(t))) {
      invalidPlaybookTeams.add(GamesaveTool.Teams[t]);
    }
  }
  return SaveFileHealthIssues(
    playerNamesOverBy: namesOverBy > 0 ? namesOverBy : 0,
    coachStringsOverBy: coachOverBy > 0 ? coachOverBy : 0,
    sharedNamePointers: tool.checkNamePointers(),
    teamsWithInvalidPlaybooks: invalidPlaybookTeams,
  );
}
