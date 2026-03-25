// Translated from Program.cs
// ignore_for_file: non_constant_identifier_names

import 'dart:io';
import 'gamesave_tool.dart';
import 'gamesave_tool_io.dart';
import 'save_session.dart';
import 'save_metadata.dart';
import 'input_parser.dart';
import 'enum_definitions.dart';
import 'static_utils.dart';
import 'logger.dart';

class Program {
  static String get Version => '1.0.0';

  /// The main entrypoint for the application.
  static void RunMain(List<String> args) {
    GamesaveTool? tool;
    SaveSession? session;
    String? saveFileName, outputFileName, dataToApplyTextFile;
    String key = '';
    String coachKey = '';
    String teamDataKey = '';

    bool showAppearance = false;
    bool showSpecialteams = false;
    bool showAbilities = false;
    bool showSchedule = false;
    bool readFromStdIn = false;
    bool autoUpdateDepthChart = false;
    bool autoUpdatePbp = false;
    bool autoUpdatePhoto = false;
    bool showFreeAgents = false;
    bool showDraftClass = false;
    bool showCoaches = false;
    bool showCoachesAll = false;
    bool showTeamData = false;
    bool showStadiumNames = false;
    bool showPlaybookNames = false;
    bool showJerseyNames = false;
    int  showJerseyNamesTeam = -1; // -1 = all 32 teams

    // Argument processing
    for (int i = 0; i < args.length; i++) {
      String arg = args[i].toLowerCase();
      switch (arg) {
        case '-app':  showAppearance = true; break;
        case '-st':   showSpecialteams = true; break;
        case '-ab':   showAbilities = true; break;
        case '-sch':  showSchedule = true; break;
        case '-stdin': readFromStdIn = true; break;
        case '-pb':   /* playbooks not yet implemented */ break;
        case '-audc': autoUpdateDepthChart = true; break;
        case '-aupbp': autoUpdatePbp = true; break;
        case '-auph': autoUpdatePhoto = true; break;
        case '-fa':   showFreeAgents = true; break;
        case '-dc':   showDraftClass = true; break;
        case '-coach': showCoaches = true; break;
        case '-coach_all': showCoachesAll = true; break;
        case '-teams': showTeamData = true; break;
        case '-show_stadium_names':  showStadiumNames = true; break;
        case '-show_playbook_names': showPlaybookNames = true; break;
        case '-show_jersey_names':
          showJerseyNames = true;
          break;
        case '-help':
        case '--help':
        case '/help':
        case '/?':
          _PrintUsage();
          return;
        default:
          if (args[i].startsWith('-out:'))
            outputFileName = args[i].substring(5);
          else if (args[i].endsWith('.txt'))
            dataToApplyTextFile = args[i];
          else if (args[i].toLowerCase().endsWith('.dat') || 
                   args[i].toLowerCase().endsWith('.zip') ||
                   args[i].toLowerCase().endsWith('.max') ||
                   args[i].toLowerCase().endsWith('.psu') ||
                   args[i].toLowerCase().endsWith('.ps2') ||
                   args[i].toLowerCase().endsWith('.bin') ||
                   args[i].toLowerCase().endsWith('.img'))
            saveFileName = args[i];
          else if (args[i].startsWith('-Key:'))
            key = args[i].substring(5);
          else if (args[i].startsWith('-CoachKey:'))
            coachKey = args[i].substring(10);
          else if (args[i].startsWith('-TeamDataKey:'))
            teamDataKey = args[i].substring(13);
          else if (args[i].toLowerCase().startsWith('-show_jersey_names:')) {
            showJerseyNames = true;
            final teamName = args[i].substring('-show_jersey_names:'.length);
            showJerseyNamesTeam = GamesaveTool.sTeamsDataOrder
                .indexWhere((t) => t.toLowerCase() == teamName.toLowerCase());
            if (showJerseyNamesTeam < 0)
              Logger.error('Unknown team name for -show_jersey_names: "$teamName"');
          } else
            Logger.error('Argument not applied: ${args[i]}');
          break;
      }
    }

    // Load save file
    if (saveFileName != null) {
      try {
        final bytes = File(saveFileName).readAsBytesSync();
        final lower = saveFileName.toLowerCase();

        if (lower.endsWith('.dat')) {
          session = SaveSession.fromRawDat(bytes);
          tool = session.engine;
        } else if (lower.endsWith('.zip')) {
          // Standard Xbox ZIP check (NFL2K5 save bundle)
          session = SaveSession.fromXboxZip(bytes);
          tool = session.engine;
        } else if (lower.endsWith('.max') || lower.endsWith('.psu')) {
          session = SaveSession.fromPs2Save(bytes);
          tool = session.engine;
        } else if (lower.endsWith('.ps2')) {
          session = SaveSession.fromPs2Card(bytes);
          tool = session.engine;
        } else if (lower.endsWith('.bin') || lower.endsWith('.img')) {
          // Could be Xbox MU or PS2 Card. Try Xbox first.
          try {
            session = SaveSession.fromXboxMU(bytes);
            tool = session.engine;
          } catch (_) {
            session = SaveSession.fromPs2Card(bytes);
            tool = session.engine;
          }
        }

        if (tool == null) {
          Logger.error("Failed to load file '$saveFileName'. Unsupported format or corrupted file.");
          return;
        }
      } catch (e) {
        Logger.error("Error loading file '$saveFileName': $e");
        return;
      }
    }

    // In C#, tool may be null here; Key/CoachKey processing doesn't require a loaded save file
    InputParser parser = InputParser(tool ?? GamesaveTool());
    if (key != '')
      parser.ProcessText('Key=$key');
    if (coachKey != '')
      parser.ProcessText('CoachKey=$coachKey');
    if (teamDataKey != '')
      parser.ProcessText('TeamDataKey=$teamDataKey');

    // Apply text data
    if ((dataToApplyTextFile != null || readFromStdIn) && outputFileName != null) {
      if (tool == null) {
        stderr.writeln('You must specify a valid save file name in order to apply data.');
        _PrintUsage();
        return;
      }
      if (readFromStdIn){
        String? line = '';
        int lineNumber = 0;
        stderr.writeln('Reading from standard in...');
        try {
          while ((line = stdin.readLineSync()) != null) {
            lineNumber++;
            parser.ProcessLine(line!);
          }
          parser.ApplySchedule();
        } catch (e, stack) {
          StaticUtils.AddError(
            "Error Processing line $lineNumber:'$line'.\n$e\n$stack");
        }
      }
      else{
        parser.ProcessText( File(dataToApplyTextFile!).readAsStringSync());
      }
    }

    if (outputFileName != null) {
      if (tool == null) {
        stderr.writeln('You must specify a valid save file name in order to save data.');
        _PrintUsage();
        return;
      }

      if (autoUpdateDepthChart)
        tool.AutoUpdateDepthChart();
      if (autoUpdatePbp)
        tool.AutoUpdatePBP();
      if (autoUpdatePhoto)
        tool.AutoUpdatePhoto();
      
      try {
        final lowerOut = outputFileName.toLowerCase();
        if (lowerOut.endsWith('.dat')) {
          tool.SaveFile(outputFileName);
        } else if (lowerOut.endsWith('.zip')) {
          if (session != null) {
            File(outputFileName).writeAsBytesSync(session.exportToXboxZip());
          } else {
             tool.SaveFile(outputFileName);
          }
        } else if (lowerOut.endsWith('.max')) {
          if (session != null) {
            File(outputFileName).writeAsBytesSync(session.exportToPs2Max());
          } else {
             stderr.writeln('Error: Only PS2 saves can be exported as .max. Use a PS2 source.');
          }
        } else if (lowerOut.endsWith('.psu')) {
          if (session != null) {
            File(outputFileName).writeAsBytesSync(session.exportToPs2Psu());
          } else {
             stderr.writeln('Error: Only PS2 saves can be exported as .psu. Use a PS2 source.');
          }
        } else if (lowerOut.endsWith('.ps2')) {
          if (session != null) {
            File(outputFileName).writeAsBytesSync(session.injectIntoPs2Card());
          } else {
             stderr.writeln('Error: Only PS2 saves can be injected into a .ps2 card. Use a PS2 source.');
          }
        } else if (lowerOut.endsWith('.bin') || lowerOut.endsWith('.img')) {
          if (session != null) {
            if (session.metadata.sourcePlatform == SavePlatform.xbox) {
              File(outputFileName).writeAsBytesSync(session.injectIntoXboxMU());
            } else {
              File(outputFileName).writeAsBytesSync(session.injectIntoPs2Card());
            }
          } else {
             stderr.writeln('Error: Only full save sessions can be injected into images.');
          }
        } else {
           tool.SaveFile(outputFileName);
        }
        Logger.log('# Data successfully written to file: $outputFileName.');
      } catch (e) {
        stderr.writeln('Error writing to file: $outputFileName. $e');
      }
    }

    // Print output
    if (tool != null) {
      StringBuffer builder = StringBuffer();
      if (showAbilities || showAppearance) {
        builder.write(tool.GetKey(showAbilities, showAppearance));
        builder.write(tool.GetLeaguePlayers(showAbilities, showAppearance, showSpecialteams));
        if (showFreeAgents)
          builder.write(tool.GetTeamPlayers('FreeAgents', showAbilities, showAppearance, false));
        if (showDraftClass)
          builder.write(tool.GetTeamPlayers('DraftClass', showAbilities, showAppearance, false));
      }
      if (showCoaches)
        builder.write(tool.GetCoachDataAll());
      if (showCoachesAll) {
        tool.CoachKey = tool.CoachKeyAll;
        builder.write(tool.GetCoachDataAll());
      }
      if (showTeamData)
        builder.write(tool.GetTeamDataAll());
      if (showStadiumNames)
        builder.write(tool.GetStadiumNamesList());
      if (showPlaybookNames)
        builder.write(tool.GetPlaybookNamesList());
      if (showJerseyNames) {
        if (showJerseyNamesTeam >= 0) {
          builder.write('\nJersey options for ${GamesaveTool.sTeamsDataOrder[showJerseyNamesTeam]}:\n');
          builder.write(tool.GetJerseyNamesList(showJerseyNamesTeam));
        } else {
          builder.write('\nJersey options (all teams):\n');
          for (int t = 0; t < 32; t++) {
            builder.write('${GamesaveTool.sTeamsDataOrder[t]}:\n');
            builder.write(tool.GetJerseyNamesList(t));
          }
        }
      }
      if (showSchedule && tool.saveType == SaveType.Franchise)
        builder.write(tool.GetSchedule());

      String? lookupPlayers = parser.GetLookupPlayers();
      if (lookupPlayers != null)
        builder.write(lookupPlayers);

      String output = builder.toString();
      Logger.log(output);
    } else {
      Logger.error('Error! you need to specify a valid save file.');
      _PrintUsage();
      return;
    }

    StaticUtils.ShowWarnings();
    StaticUtils.ShowErrors();
  }

  static void _PrintUsage() {
    Logger.log('''NFL2K5Tool Version $Version

This program can extract data from and import data into NFL2K5 Save game files.

Usage:
    nfl2k5tool_dart <save_file> [data_to_apply.txt] [options]

Supported Save Formats:
    Xbox: .dat, .zip (bundle), .bin/.img (Memory Unit)
    PS2:  .max, .psu, .ps2 (Memory Card), .zip (bundle)

Examples:
    [Print all player attributes]
    nfl2k5tool_dart MyRoster.zip -ab -app

    [Convert Xbox roster to PS2 Max format]
    nfl2k5tool_dart MyRoster.dat -out:MyRoster.max

    [Reads in 'MyRoster.zip', applies the data from input.txt, saves to MyRoster_mod.zip]
    nfl2k5tool_dart MyRoster.zip input.txt -out:MyRoster_mod.zip

    [Reads in 'MyRoster.zip', applies input.txt, prints all player abilities including free agents and draft class]
    nfl2k5tool_dart MyRoster.zip input.txt -dc -fa -ab -app


The default behavior when called with a supported save file and no options is to print player information from the given NFL2K5 save file.

When called with a NFL2K5 save file and a <data_to_apply.txt> file, the behavior is that it will modify the NFL2K5 save file with the data contained in the data file.

The following are the available options.

-app            Print appearance data.
-st             Print Special teams players
-ab             Print player abilities (speed, agility, ...).
-audc           Auto update the depth chart.
-aupbp          Auto update the play by play info for each player.
-auph           Auto update the photo for each player.
-sch            Print schedule.
-fa             Print Free Agents
-dc             Print draft class
-coach          Print coaches (uses current CoachKey)
-coach_all      Print all coach attributes (overrides CoachKey with full field set)
-teams          Print team metadata (nickname, city, stadium, logo, playbooks, jersey, etc.)
-show_stadium_names       Print all available stadium names (for use with [brackets])
-show_playbook_names      Print all available playbook names (for use with Playbook field)
-show_jersey_names        Print all jersey options for all 32 teams
-show_jersey_names:<team> Print jersey options for a single team (e.g. -show_jersey_names:49ers)
-stdin          Read data from standard in.
-Key:<key>      Specify key
-CoachKey:<key> Specify Coach Key
-TeamDataKey:<key> Specify Team Data Key
                  Available TeamData fields: Nickname, Abbrev, Stadium, City, AbbrAlt,
                  Logo, Playbook, DefaultJersey
                  Playbook values: PB_49ers, PB_Bears, PB_West_Coast, PB_General, etc.
-out:filename   Save modified Save file to <filename>.
-help           Show this help message.
''');
  }
}
