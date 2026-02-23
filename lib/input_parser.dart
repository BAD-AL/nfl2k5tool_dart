// Translated from InputParser.cs
// ignore_for_file: non_constant_identifier_names

import 'dart:io';
import 'enum_definitions.dart';
import 'static_utils.dart';
import 'gamesave_tool.dart';

enum ParsingStates { PlayerModification, PlayerLookupAndApply, PlayerLookup, Schedule }

/// Class used to help keep track of number of players being input.
class InputParserTeamTracker {
  int CBs = 0, DEs = 0, DTs = 0, FBs = 0, Gs = 0;
  int RBs = 0, OLBs = 0, ILBs = 0, Ps = 0, QBs = 0;
  int SSs = 0, Ts = 0, TEs = 0, WRs = 0, Cs = 0;
  int PlayerCount = 0;
  String Team = '';

  void Reset() {
    CBs = DEs = DTs = FBs = Gs = RBs = OLBs = ILBs = Ps = QBs = 0;
    SSs = Ts = TEs = WRs = Cs = PlayerCount = 0;
  }
}

class InputParser {
  final RegExp mTeamRegex = RegExp(r'Team\s*=\s*([0-9a-zA-Z]+)');
  final RegExp mWeekRegex = RegExp(r'Week\s([1-9]\d?)', caseSensitive: false, );
  final RegExp mGameRegex = RegExp(r'([0-9a-z]+)\s+at\s+([0-9a-zA-Z]+)');
  final RegExp mYearRegex = RegExp(r'YEAR\s*=\s*([0-9]+)', caseSensitive: false);

  ParsingStates mCurrentState = ParsingStates.PlayerModification;
  InputParserTeamTracker mTracker = InputParserTeamTracker();
  List<String>? mScheduleList;

  /// true to use existing names; false to replace the names.
  bool UseExistingNames = false;

  GamesaveTool Tool;

  InputParser(this.Tool);

  /// Gets the team corresponding to the text position
  static String GetTeam(int textPosition, String data) {
    String team = '49ers';
    RegExp r = RegExp(r'TEAM\s*=\s*([a-zA-Z49]+)', caseSensitive: false);
    RegExpMatch? theMatch;
    for (final m in r.allMatches(data)) {
      if (m.start > textPosition) break;
      theMatch = m;
    }
    if (theMatch != null) {
      team = theMatch.group(1)!;
    }
    return team;
  }

  static List<String>? GetCoaches(String data) {
    RegExp r = RegExp(r'^(Coach,.*)', caseSensitive: false, multiLine: true);
    List<String>? retVal;
    Iterable<RegExpMatch> mc = r.allMatches(data);
    if (mc.isNotEmpty) {
      retVal = [];
      for (final m in mc) {
        retVal.add(m.group(1)!);
      }
    }
    return retVal;
  }

  /// Returns the line that linePosition falls on in data
  static String? GetLine(int textPosition, String data) {
    String? ret;
    if (textPosition < data.length) {
      int i = 0;
      int lineStart = 0;
      int posLen = 0;
      for (i = textPosition; i > 0; i--) {
        if (data[i] == '\n') {
          lineStart = i + 1;
          break;
        }
      }
      i = lineStart;
      if (i < data.length) {
        String current = data[i];
        while (i < data.length - 1 && current != '\n') {
          posLen++;
          i++;
          current = data[i];
        }
        ret = data.substring(lineStart, lineStart + posLen);
      }
    }
    return ret;
  }

  /// Returns the n'th line after the textPosition in 'data'.
  static String? GetLineAfter(int textPosition, int linesAfter, String data) {
    int ne = 0;
    int i;
    for (i = textPosition; i < data.length; i++) {
      if (data[i] == '\n') ne++;
      if (ne == linesAfter) {
        i++;
        break;
      }
    }
    if (i < data.length)
      return GetLine(i, data);
    return null;
  }

  /// Process the text in the given file, applying it to the gamesave data.
  void ProcessFile(String fileName) {
    try {
      String contents = File(fileName).readAsStringSync();
      ProcessText(contents);
    } catch (e) {
      StaticUtils.AddError("Error processing file '$fileName'. $e");
    }
  }

  void ReadFromStdin() {
    String? line = '';
    int lineNumber = 0;
    stderr.writeln('Reading from standard in...');
    try {
      while ((line = stdin.readLineSync()) != null) {
        lineNumber++;
        ProcessLine(line!);
      }
      ApplySchedule();
    } catch (e, stack) {
      StaticUtils.AddError(
        "Error Processing line $lineNumber:'$line'.\n$e\n$stack");
    }
  }

  void ProcessText(String text) {
    sDelim = _CharCount(text, ';') > _CharCount(text, ',') ? ';' : ',';
    List<String> lines = text.split(RegExp(r'[\n\r]'));
    ProcessLines(lines);
  }

  void ProcessLines(List<String> lines) {
    Tool.GetKey(true, true);
    int i = 0;
    try {
      for (i = 0; i < lines.length; i++) {
        ProcessLine(lines[i]);
      }
      ApplySchedule();
    } catch (e, stack) {
      StringBuffer sb = StringBuffer();
      sb.write('Error! ');
      if (i < lines.length)
        sb.write('line #$i:\t\'${lines[i]}\'');
      sb.write(e.toString());
      sb.write('\n');
      sb.write(stack.toString());
      sb.write('\n\nOperation aborted at this point. Data not applied.');
      stderr.writeln(sb.toString());
    }
  }

  String? GetLookupPlayers() {
    if (mLookupedPlayers != null) {
      return mLookupedPlayers.toString();
    }
    return null;
  }

  RegExpMatch? mTeamMatch;
  StringBuffer? mLookupedPlayers;

  bool ProcessLine(String line) {
    bool retVal = true;
    line = line.trim();
    if (line.endsWith(','))
      line = line.substring(0, line.length - 1);

    if (line.startsWith('#') || line.isEmpty) {
      // comment or empty line - do nothing
    } else if (line.toLowerCase().startsWith('key=')) {
      Tool.SetKey(line.substring(4));
    } else if (line.toLowerCase().startsWith('coachkey=')) {
      Tool.CoachKey = line.substring(9);
    } else if (line.startsWith('SET')) {
      ApplySet(line);
    } else if (line.toLowerCase().contains('lookupandmodify')) {
      print('LookupAndModifyMode');
      mCurrentState = ParsingStates.PlayerLookupAndApply;
    } else if ((mTeamMatch = mTeamRegex.firstMatch(line)) != null) {
      mCurrentState = ParsingStates.PlayerModification;
      String team = mTeamMatch!.group(1).toString();
      bool ret = SetCurrentTeam(team);
      if (!ret) {
        StaticUtils.AddError("ERROR with line '$line'.");
        StaticUtils.AddError("Team input must be in the form 'TEAM = team '");
        return false;
      }
    } else if (mWeekRegex.firstMatch(line) != null) {
      mCurrentState = ParsingStates.Schedule;
      mScheduleList ??= [];
      mScheduleList!.add(line);
    } else if (mYearRegex.firstMatch(line) != null) {
      SetYear(line);
    } else if (line.startsWith('KR1,') || line.startsWith('KR2,') ||
               line.startsWith('PR,')  || line.startsWith('LS,')) {
      SetSpecialTeamPlayer(line);
    } else if (line == 'AutoUpdateDepthChart') {
      Tool.AutoUpdateDepthChart();
    } else if (line == 'AutoUpdatePBP') {
      Tool.AutoUpdatePBP();
    } else if (line == 'AutoUpdatePhoto') {
      Tool.AutoUpdatePhoto();
    } else if (line.toLowerCase().startsWith('coach,')) {
      SetCoachData(line);
    } else if (line.startsWith('LookupPlayer')) {
      mCurrentState = ParsingStates.PlayerLookup;
      mLookupedPlayers = StringBuffer();
    } else if (line.startsWith('ApplyFormula')) {
      _ApplyFormula(line);
    } else {
      switch (mCurrentState) {
        case ParsingStates.PlayerModification:
          retVal = InsertPlayer(line);
          break;
        case ParsingStates.PlayerLookup:
          mLookupedPlayers!.write(LookupPlayer(line));
          mLookupedPlayers!.write('\n');
          break;
        case ParsingStates.Schedule:
          mScheduleList!.add(line.toLowerCase());
          break;
        case ParsingStates.PlayerLookupAndApply:
          retVal = _LookupPlayerAndApply(line);
          break;
      }
    }
    return retVal;
  }

  /// Expects input like:
  ///   ApplyFormula('true','RightGlove','None', [QB])
  ///   ApplyFormula('Speed > 80','Stamina','95', [QB], Percent)
  void _ApplyFormula(String line) {
    int index = line.indexOf('(') + 1;
    int endPos = line.indexOf(']') + 1;
    if (index != 0 && endPos != 0) {
      FormulaMode fm = FormulaMode.Normal;
      String argString = line.substring(index).replaceAll(')', '');
      List<String> args = argString.split(',');
      String formula = args[0].replaceAll("'", '').trim().replaceAll(' ', '');
      // handle the trimming like C# Trim("' ".ToCharArray())
      formula = args[0].trim().replaceAll(RegExp(r"[' ]"), '');
      String attr = args[1].trim().replaceAll(RegExp(r"[' ]"), '');
      String val = args[2].trim().replaceAll(RegExp(r"[' ]"), '');
      List<String> positions = _GetFormulaPositions(line);

      if (line.toLowerCase().contains('add'))
        fm = FormulaMode.Percent;
      else if (line.toLowerCase().contains('increment'))
        fm = FormulaMode.Add;

      String? results = Tool.ApplyFormula(formula, attr, val, positions, fm, true);
      String message;
      if (results == null)
        message = 'Warning. No players selected by formula:\n\t"$line"';
      else if (results.startsWith('Exception!'))
        message = 'Error, Check formula\n$results';
      else
        message = '#Affected  Players\n$results';
      print(message);
    }
  }

  List<String> _GetFormulaPositions(String line) {
    List<String> retVal = [];
    int index1 = line.indexOf('[') + 1;
    int index2 = line.indexOf(']', index1 + 1) + 1;
    if (index1 > 0 && index2 > 0) {
      String ps = line.substring(index1, index2 - 1);
      List<String> positions = ps.split(',');
      for (String pos in positions) {
        retVal.add(pos.trim());
      }
    }
    return retVal;
  }

  bool _LookupPlayerAndApply(String line) {
    bool retVal = false;
    List<String> attributes = ParsePlayerLine(line)!;

    int firstNameIndex = -1, lastNameIndex = -1, positionIndex = -1;
    for (int i = 0; i < Tool.Order!.length; i++) {
      if (Tool.Order![i] == -1) firstNameIndex = i;
      else if (Tool.Order![i] == -2) lastNameIndex = i;
      else if (Tool.Order![i] == PlayerOffsets.Position.value) positionIndex = i;
      if (firstNameIndex > -1 && lastNameIndex > -1 && positionIndex > -1) break;
    }
    if (firstNameIndex > -1 && lastNameIndex > -1) {
      String? pos;
      if (positionIndex > -1) pos = attributes[positionIndex];
      String firstName = attributes[firstNameIndex];
      String lastName = attributes[lastNameIndex];

      List<int> playersToApplyTo = Tool.FindPlayer(pos, firstName, lastName);
      if (playersToApplyTo.isNotEmpty)
        retVal = SetPlayerData(playersToApplyTo[0], line, false);
    } else {
      StaticUtils.AddError("In 'LookupAndModify' mode, you must specify fname and lname in the 'Key' for proper lookup: $line");
    }
    return retVal;
  }

  /// Looks up a player and returns their data.
  String LookupPlayer(String line) {
    List<String> attributes = ParsePlayerLine(line)!;
    String retVal = '#NotFound: $line';

    int firstNameIndex = -1, lastNameIndex = -1, positionIndex = -1;
    for (int i = 0; i < Tool.Order!.length; i++) {
      if (Tool.Order![i] == -1) firstNameIndex = i;
      else if (Tool.Order![i] == -2) lastNameIndex = i;
      else if (Tool.Order![i] == PlayerOffsets.Position.value) positionIndex = i;
      if (firstNameIndex > -1 && lastNameIndex > -1 && positionIndex > -1) break;
    }
    String pos = attributes[positionIndex];
    String firstName = attributes[firstNameIndex];
    String lastName = attributes[lastNameIndex];

    StringBuffer builder = StringBuffer();
    List<int> playerIndexes = Tool.FindPlayer(pos, firstName, lastName);

    for (int i = 0; i < playerIndexes.length; i++) {
      builder.write(Tool.GetPlayerData(playerIndexes[i], true, true));
      builder.write('\n');
    }
    String built = builder.toString();
    if (built.isNotEmpty) {
      built = built.substring(0, built.length - 1); // remove last '\n'
      retVal = built;
    }
    return retVal;
  }

  void SetCoachData(String line) {
    List<String> keyParts = Tool.CoachKey.split(',');
    List<String> parts = ParseCoachLine(line);
    int teamIndex = Tool.GetTeamIndex(parts[1]);
    CoachOffsets current = CoachOffsets.Body;
    try {
      for (int i = 2; i < keyParts.length; i++) {
        if (i == parts.length) break;
        switch (keyParts[i].toLowerCase()) {
          case 'firstname':
          case 'fname':
            Tool.SetCoachAttribute(teamIndex, CoachOffsets.FirstName, parts[i]);
            break;
          case 'lastname':
          case 'lname':
            Tool.SetCoachAttribute(teamIndex, CoachOffsets.LastName, parts[i]);
            break;
          default:
            current = CoachOffsets.values.firstWhere(
                (e) => e.name.toLowerCase() == keyParts[i].toLowerCase());
            Tool.SetCoachAttribute(teamIndex, current, parts[i]);
        }
      }
    } catch (e) {
      StaticUtils.AddError(
          "Error setting data for line:\r\n$line\r\n\r\nPerhaps check '${current.name}' attribute.");
    }
  }

  // Expecting a line like "KR1,CB2"
  void SetSpecialTeamPlayer(String line) {
    List<String> parts = line.split(',');
    if (parts.length == 2) {
      try {
        SpecialTeamer guy = SpecialTeamer.values.firstWhere(
            (e) => e.name.toLowerCase() == parts[0].toLowerCase());
        String posStr = parts[1].substring(0, parts[1].length - 1);
        Positions pos = Positions.values.firstWhere(
            (e) => e.name.toLowerCase() == posStr.toLowerCase());
        int depth = 1;
        depth = int.tryParse(parts[1].substring(parts[1].length - 1)) ?? 1;
        Tool.SetSpecialTeamPosition(mTracker.Team, guy, pos, depth);
      } catch (e) {
        StaticUtils.AddError(
            'Team:${mTracker.Team} Error adding special team player $line');
      }
    } else if (parts.length == 3) {
      try {
        SpecialTeamer guy = SpecialTeamer.values.firstWhere(
            (e) => e.name.toLowerCase() == parts[0].toLowerCase());
        Tool.SetSpecialTeamPosition(mTracker.Team, guy, parts[1], parts[2]);
      } catch (e) {
        StaticUtils.AddError(
            'Team:${mTracker.Team} Error adding special team player $line');
      }
    }
  }

  bool InsertPlayer(String line) {
    int playerIndex = _GetPlayerIndex(line);
    bool useExisting = UseExistingNames || (playerIndex >= GamesaveTool.FirstDraftClassPlayer);
    return SetPlayerData(playerIndex, line, useExisting);
  }

  int _GetPlayerIndex(String line) {
    int retVal = -1;
    List<int> playerIndexes = Tool.GetPlayerIndexesForTeam(mTracker.Team);
    if (mTracker.PlayerCount < playerIndexes.length) {
      retVal = playerIndexes[mTracker.PlayerCount++];
    } else {
      StaticUtils.AddError(
          'Error, team player limit reached. ${mTracker.Team}; cannot add player: $line');
    }
    return retVal;
  }

  static String sDelim = ',';

  /// Parses a line of text into a list of strings.
  static List<String>? ParsePlayerLine(String line) {
    // default if not set
    List<String>? retVal;
    if (line.isNotEmpty) {
      retVal = line.split(sDelim);
      for (int i = 0; i < retVal.length; i++) {
        // Fix up commas inside quoted strings (single comma case)
        if (retVal[i].endsWith('"') && i > 0 && retVal[i - 1].startsWith('"')) {
          retVal[i - 1] = retVal[i - 1] + sDelim + retVal[i];
          retVal.removeAt(i);
        } else if (retVal[i].isEmpty) {
          retVal.removeAt(i);
          i--;
        }
      }
    }
    return retVal;
  }

  /// Parses a coach line of text into a list of strings.
  static List<String> ParseCoachLine(String line) {
    List<String> retVal = [];
    if (line.isNotEmpty) {
      int quoteCount = 0;
      List<int> chars = line.codeUnits.toList();
      int delimCode = sDelim.codeUnitAt(0);
      int quoteCode = '"'.codeUnitAt(0);
      int pipeCode = '|'.codeUnitAt(0);
      for (int i = 0; i < chars.length; i++) {
        if (chars[i] == quoteCode)
          quoteCount++;
        else if (quoteCount % 2 == 1 && chars[i] == delimCode)
          chars[i] = pipeCode;
      }
      retVal = String.fromCharCodes(chars).split(sDelim);
      for (int i = 0; i < retVal.length; i++) {
        if (retVal[i].contains('|'))
          retVal[i] = retVal[i].replaceAll('|', ',');
      }
    }
    return retVal;
  }

  static int _CharCount(String input, String thingToCount) {
    int retVal = 0;
    for (int i = 0; i < input.length; i++)
      if (input[i] == thingToCount) retVal++;
    return retVal;
  }

  /// Returns the index of the nth occurrence of the given character
  static int NthIndex(String input, String thingToCount, int index) {
    int count = 0;
    for (int i = 0; i < input.length; i++) {
      if (input[i] == thingToCount) {
        count++;
        if (count == index) return i;
      }
    }
    return -1;
  }

  /// Sets a player's attributes
  bool SetPlayerData(int player, String line, bool useExistingName) {
    return _SetPlayerStuff1(player, line, useExistingName);
  }

  bool _SetPlayerStuff1(int player, String line, bool useExistingName) {
    String attribute = '';
    String playerName = '';
    if (player > -1 && player < Tool.MaxPlayers) {
      int attr = -1;
      List<String> attributes = ParsePlayerLine(line)!;
      if (useExistingName && !_CheckPlayerNameExists(attributes, playerName)) {
        StaticUtils.AddError(
            'Could not find matching name in string database. player not added: $playerName');
        return false;
      }
      for (int i = 0; i < attributes.length; i++) {
        try {
          if (i >= Tool.Order!.length) break;
          attr = Tool.Order![i];
          attribute = attributes[i];
          if (attr == -1) {
            if (!Tool.SetPlayerFirstName(player, attribute, useExistingName))
              StaticUtils.AddError(
                  "Error setting FirstName >$attribute< for '$line' Can only use existing names for college players.");
          } else if (attr == -2) {
            if (!Tool.SetPlayerLastName(player, attribute, useExistingName))
              StaticUtils.AddError(
                  "Error setting LastName >$attribute< for '$line' Can only use existing names for college players.");
          } else if (attribute == '?' || attribute == '_') {
            // do nothing
          } else if (attr >= AppearanceAttributes.College.value) {
            if (attr != AppearanceAttributes.College.value)
              attribute = attribute.replaceAll(' ', ''); // strip spaces
            final aaAttr =
                AppearanceAttributes.values.firstWhere((e) => e.value == attr);
            Tool.SetPlayerAppearanceAttribute(player, aaAttr, attribute);
          } else {
            final poAttr =
                PlayerOffsets.values.firstWhere((e) => e.value == attr);
            Tool.SetAttribute(player, poAttr, attribute);
          }
        } catch (e) {
          String name = line.length > 15 ? line.substring(0, 15) + '...' : line;
          String desc = 'Unknown($attr)';
          try {
            if (attr > 99) {
              desc = AppearanceAttributes.values.firstWhere((e) => e.value == attr).name;
            } else {
              desc = PlayerOffsets.values.firstWhere((e) => e.value == attr).name;
            }
          } catch (_) {}
          StaticUtils.AddError(
              "Error setting attribute '$desc' to '$attribute' for line: $name");
        }
      }
    }
    return true;
  }

  List<String> MissingNames = [];

  bool _CheckPlayerNameExists(List<String> attributes, String playerName) {
    int firstNameIndex = Tool.Order!.indexOf(-1);
    int lastNameIndex = Tool.Order!.indexOf(-2);

    String firstName = attributes[firstNameIndex];
    String lastName = attributes[lastNameIndex];
    bool firstNameExists = Tool.CheckNameExists(firstName);
    bool lastNameExists = Tool.CheckNameExists(lastName);
    bool retVal = firstNameExists && lastNameExists;
    if (!retVal) {
      playerName =
          '$firstName $lastName firstNameExists=$firstNameExists lastNameExists=$lastNameExists';
      if (!firstNameExists)
        MissingNames.add(firstName);
      else
        MissingNames.add(lastName);
    } else {
      playerName = '';
    }
    return retVal;
  }

  bool SetCurrentTeam(String team) {
    if (Tool.GetTeamIndex(team) < 0) {
      StaticUtils.AddError("Team '$team' is Invalid.");
      return false;
    } else {
      mTracker.Team = team;
      mTracker.Reset();
      if (team == 'DraftClass')
        UseExistingNames = true;
      else
        UseExistingNames = false;
    }
    return true;
  }

  void SetYear(String line) {
    RegExpMatch? m = mYearRegex.firstMatch(line);
    if (m == null) {
      StaticUtils.AddError("'$line' is not valid.");
    } else {
      String year = m.group(1).toString();
      if (year.isEmpty) {
        StaticUtils.AddError("'$line' is not valid.");
      } else {
        Tool.SetYear(year);
      }
    }
  }

  void ApplySchedule() {
    if (mScheduleList != null && mScheduleList!.isNotEmpty) {
      Tool.ApplySchedule(mScheduleList!);
      mScheduleList = null;
    }
  }

  // #region SetBytes logic
  RegExp? simpleSetRegex;

  void ApplySet(String line) {
    simpleSetRegex ??= RegExp(
        r'SET\s*\(\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)\s*\)');

    if (simpleSetRegex!.firstMatch(line) != null) {
      ApplySimpleSet(line);
    } else {
      StaticUtils.AddError('ERROR with line "$line"');
    }
  }

  void ApplySimpleSet(String line) {
    simpleSetRegex ??= RegExp(
        r'SET\s*\(\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)\s*\)');

    RegExpMatch? m = simpleSetRegex!.firstMatch(line);
    if (m == null) {
      StaticUtils.AddError(
          "SET function not used properly. incorrect syntax>'$line'");
      return;
    }
    String loc = m.group(1)!.toLowerCase();
    String val = m.group(2)!.toLowerCase();
    loc = loc.substring(2); // strip '0x'
    val = val.substring(2);
    if (val.length % 2 != 0) val = '0' + val;

    try {
      int location = int.parse(loc, radix: 16);
      List<int> bytes = GetHexBytes(val)!;
      if (location + bytes.length > Tool.GameSaveData!.length) {
        StaticUtils.AddError(
            'ApplySet:> Error with line $line. Data falls off the end of rom.\n');
      } else if (location < 0) {
        StaticUtils.AddError(
            'ApplySet:> Error with line $line. location is negative.\n');
      } else {
        for (int i = 0; i < bytes.length; i++) {
          Tool.SetByte(location + i, bytes[i]);
        }
      }
    } catch (e) {
      StaticUtils.AddError('ApplySet:> Error with line $line.\n$e');
    }
  }

  List<int>? GetHexBytes(String? input) {
    if (input == null) return null;
    List<int> ret = List.filled(input.length ~/ 2, 0);
    int j = 0;
    for (int i = 0; i < input.length; i += 2) {
      String b = input.substring(i, i + 2);
      ret[j++] = int.parse(b, radix: 16);
    }
    return ret;
  }
  // #endregion
}
