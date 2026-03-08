// Translated from Program.cs
// ignore_for_file: non_constant_identifier_names

import 'dart:io';
import 'gamesave_tool.dart';
import 'gamesave_tool_io.dart';
import 'input_parser.dart';
import 'enum_definitions.dart';
import 'static_utils.dart';
import 'logger.dart';

class Program {
  static String get Version => '1.0.0';

  /// The main entrypoint for the application.
  static void RunMain(List<String> args) {
    GamesaveTool? tool;
    String? saveFileName, outputFileName, dataToApplyTextFile;
    String key = '';
    String coachKey = '';

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
          else if (args[i].toLowerCase().endsWith('.dat') || args[i].toLowerCase().endsWith('.zip'))
            saveFileName = args[i];
          else if (args[i].startsWith('-Key:'))
            key = args[i].substring(5);
          else if (args[i].startsWith('-CoachKey:'))
            coachKey = args[i].substring(10);
          else
            Logger.error('Argument not applied: ${args[i]}');
          break;
      }
    }

    // Load save file
    if (saveFileName != null) {
      try {
        tool = GamesaveTool();
        if (!tool.LoadSaveFile(saveFileName)) {
          Logger.error("File '$saveFileName' does not exist. Make sure you have the correct path to the file specified.");
          return;
        }
      } catch (e) {
        Logger.error("Error loading file '$saveFileName'. Make sure it is an actual NFL2K5 roster or franchise file.");
        return;
      }
    }

    // In C#, tool may be null here; Key/CoachKey processing doesn't require a loaded save file
    InputParser parser = InputParser(tool ?? GamesaveTool());
    if (key != '')
      parser.ProcessText('Key=$key');
    if (coachKey != '')
      parser.ProcessText('CoachKey=$coachKey');

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
      if (autoUpdateDepthChart)
        tool.AutoUpdateDepthChart();
      if (autoUpdatePbp)
        tool.AutoUpdatePBP();
      if (autoUpdatePhoto)
        tool.AutoUpdatePhoto();
      try {
        tool.SaveFile(outputFileName);
      } catch (e) {
        if (e is Exception) {
          stderr.writeln('Error writing to file: $outputFileName. $e');
        } else {
          stderr.writeln('Error writing to file: $outputFileName. $e');
        }
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
        if (showCoaches)
          builder.write(tool.GetCoachDataAll());
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

    StaticUtils.ShowErrors();
  }

  static void _PrintUsage() {
    Logger.log('''NFL2K5Tool Version $Version

This program can extract data from and import data into a NFL2K5 Save game files.

Usage:
    nfl2k5tool_dart <filename.dat>|<filename.zip> <data_to_apply.txt> [options]

Examples:
    [Print all player attributes]
    nfl2k5tool_dart MyRoster.zip -ab -app

    [Print only specified player attributes]
    nfl2k5tool_dart MyRoster.zip -ab  -Key:Position,fname,lname,Photo,Skin

    [Reads in 'MyRoster.zip', applies the data from input.txt, saves to MyRoster_mod.zip]
    nfl2k5tool_dart MyRoster.zip input.txt -out:MyRoster_mod.zip

    [Reads in 'MyRoster.zip', applies input.txt, prints all player abilities including free agents and draft class]
    nfl2k5tool_dart MyRoster.zip input.txt -dc -fa -ab -app


The default behavior when called with a .dat or .zip filename and no options is to print player information from the given NFL2K5 save file.

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
-coach          Print coaches
-stdin          Read data from standard in.
-Key:<key>      Specify key
-CoachKey:<key> Specify Coach Key
-out:filename   Save modified Save file to <filename>.
-help           Show this help message.
''');
  }
}
