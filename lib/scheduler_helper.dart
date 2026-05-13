// Translated from SchedulerHelper.cs
// ignore_for_file: non_constant_identifier_names

import 'dart:typed_data';
import 'enum_definitions.dart';
import 'static_utils.dart';
import 'nfl2k5_schedule.dart';
import 'gamesave_tool.dart';

/*
 * Flying fin Schedule file
 * 1 game = 8 bytes
 * Weeks separated by 0x0007000000000000, which also signifies an empty game.
 * struct game { home_team, away_team, month, day_of_month, two_digit_year, hour_of_day, minute_of_hour, null_byte }
 *
 * Franchise file: Starts at 0x917EB, same format
 */

/// Summary description for SchedulerHelper.
class SchedulerHelper {
  List<String> mTeams = [
    '49ers',    // 00
    'bears',
    'bengals',
    'bills',
    'broncos',
    'browns',   // 05
    'buccaneers',
    'cardinals',
    'chargers',
    'chiefs',
    'colts',    // 0A
    'cowboys',
    'dolphins',
    'eagles',
    'falcons',
    'giants',   // 0F
    'jaguars',
    'jets',
    'lions',
    'packers',
    'panthers', // 14
    'patriots',
    'raiders',
    'rams',
    'ravens',
    'redskins', // 19
    'saints',
    'seahawks',
    'steelers',
    'texans',
    'titans',   // 1E
    'vikings',
    'free_agents', // 20
  ];

  // schedule begins at the 2nd Thursday of September.
  static int FranchiseGameOneYearLocation = 0x917ef; // first game year.

  GamesaveTool Tool;

  int mYear = 0x04; // default 2004

  final List<int> mNullGame = [0x00, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];

  static bool AUTO_CORRECT_SCHEDULE = true;

  List<int>? mTeamGames;

  // for schedule files it's '2', for franchise files it's '0x917EB'.
  int mWeekOneStartLoc = _mFranchiseFileWeekOneStartLoc;
  static const int _mFranchiseFileWeekOneStartLoc = 0x917EB;
  static const int _mScheduleFileWeekOneStartLoc = 2;

  int mWeek = 0, mWeekGameCount = 0, mTotalGameCount = 0;
  final RegExp mGameRegex = RegExp(r'([0-9a-z]+)\s+at\s+([0-9a-z]+)');

  final List<int> mGamesPerWeek = [16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16];

  int get WeekOneStartLoc => mWeekOneStartLoc;

  /// Tells us if we are in 'FranchiseScheduleMode'.
  bool get FranchiseScheduleMode => mWeekOneStartLoc == _mFranchiseFileWeekOneStartLoc;
  set FranchiseScheduleMode(bool value) {
    if (value)
      mWeekOneStartLoc = _mFranchiseFileWeekOneStartLoc;
    else
      mWeekOneStartLoc = _mScheduleFileWeekOneStartLoc;
  }

  SchedulerHelper(this.Tool);

  /// Gets the default schedule for NFL2K5 from the embedded binary.
  Uint8List GetDefaultSchedule() {
    try {
      return Uint8List.fromList(kNfl2k5ScheduleData);
    } catch (e) {
      String msg = "Error! GetDefaultSchedule '$e'";
      StaticUtils.AddError(msg);
      assert(false, msg);
      return Uint8List(0);
    }
  }

  void PatchSchedule() {
    Uint8List defaultSchedule = GetDefaultSchedule();
    int start = WeekOneStartLoc - 2; // -2 because the file starts with 2 '0' bytes.
    for (int i = 0; i < defaultSchedule.length; i++)
      Tool.SetByte(start + i, defaultSchedule[i]);
  }

  /// Applies a schedule to the rom.
  void ApplySchedule(List<String> lines) {
    mWeek = -1;
    mWeekGameCount = 0;
    mTotalGameCount = 0;

    PatchSchedule();
    // set up the year
    if (Tool.Year > 0) {
      String theYear = Tool.Year.toString();
      if (theYear.length > 1) {
        theYear = theYear.substring(theYear.length - 2, theYear.length);
        mYear = int.parse(theYear);
      }
    }

    if (AUTO_CORRECT_SCHEDULE) {
      ReLayoutScheduleWeeks(lines);
      lines = Ensure17Weeks(lines);
    }

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].toString().trim().toLowerCase();
      if (line.startsWith('#') || line.length < 3) {
        // do nothing
      } else if (line.startsWith('week')) {
        if (mWeek > 17) {
          StaticUtils.AddError('Error! You can have only 17 weeks in a season.');
          break;
        }
        CloseWeek();
      } else {
        ScheduleGameFromLine(line);
      }
    }
    CloseWeek(); // close week 17

    if (mWeek < 17) {
      StaticUtils.AddError(
          "Warning! You didn't schedule all 17 weeks. The schedule could be messed up.");
    }
    if (mTeamGames != null) {
      for (int i = 0; i < mTeamGames!.length; i++) {
        if (mTeamGames![i] != 16) {
          StaticUtils.AddError(
              'Warning! The ${GetTeamFromIndex(i)} have ${mTeamGames![i]} games scheduled.');
        }
      }
    }
  }

  void CloseWeek() {
    if (mWeek > -1) {
      int i = mWeekGameCount;
      while (i < 16) {
        ScheduleGameByIndex(0xff, 0xff, mWeek, i);
        i++;
      }
    }
    mWeek++;
    mTotalGameCount += mWeekGameCount;
    mWeekGameCount = 0;
  }

  /// Attempts to schedule a game from a line string.
  bool ScheduleGameFromLine(String line) {
    bool ret = false;
    RegExpMatch? m = mGameRegex.firstMatch(line);

    if (m != null) {
      String awayTeam = m.group(1)!;
      String homeTeam = m.group(2)!;
      if (mWeekGameCount > 16) {
        StaticUtils.AddError(
            'Error! Week ${mWeek + 1}: You can have no more than 16 games in a week.');
        ret = false;
      } else if (ScheduleGame(awayTeam, homeTeam, mWeek, mWeekGameCount)) {
        mWeekGameCount++;
        ret = true;
      }
    }
    if (mTotalGameCount + mWeekGameCount > 256) {
      StaticUtils.AddError(
          'Warning! Week ${mWeek + 1}: There are more than 256 games scheduled.');
    }
    return ret;
  }

  /// Schedule a game by team names.
  /// [week] is 0-16 (0 = week 1).
  bool ScheduleGame(String awayTeam, String homeTeam, int week, int gameOfWeek) {
    int awayIndex = GetTeamIndex(awayTeam);
    int homeIndex = GetTeamIndex(homeTeam);

    if (awayIndex == -1 || homeIndex == -1) {
      StaticUtils.AddError(
          "Error! Week ${week + 1}: Game '$awayTeam at $homeTeam'");
      return false;
    }

    if (awayIndex == homeIndex && awayIndex < 0x20) {
      StaticUtils.AddError(
          'Warning! Week ${week + 1}: The $awayTeam are scheduled to play against themselves.');
    }

    if (week < 0 || week > 17) {
      StaticUtils.AddError(
          'Week $week is not valid. Weeks range 0-17 (0 = week 1).');
      return false;
    }
    if (GameLocation(week, gameOfWeek) < 0) {
      StaticUtils.AddError(
          'Game $gameOfWeek for week $week is not valid. Valid games for week $week are 0-16.');
      return false;
    }

    ScheduleGameByIndex(awayIndex, homeIndex, week, gameOfWeek);

    if (awayTeam == 'null' || homeTeam == 'null')
      return false;
    return true;
  }

  void ScheduleGameByIndex(int awayTeamIndex, int homeTeamIndex, int week, int gameOfWeek) {
    int location = GameLocation(week, gameOfWeek);
    if (location > 0) {
      if (awayTeamIndex != 0xff && homeTeamIndex != 0xff) {
        Tool.SetByte(location + Game.HomeTeam.value, homeTeamIndex);
        Tool.SetByte(location + Game.AwayTeam.value, awayTeamIndex);
        Tool.SetByte(location + Game.YearTwoDigit.value, mYear);

        try {
          DateTime time = GetGameTime(week, gameOfWeek);
          Tool.SetByte(location + Game.Month.value, time.month);
          Tool.SetByte(location + Game.Day.value, time.day);
        } catch (e) {
          // ignore date errors
        }
        if (awayTeamIndex < 0x20) {
          IncrementTeamGames(awayTeamIndex);
          IncrementTeamGames(homeTeamIndex);
        }
      } else {
        location -= 2;
        for (int i = 0; i < mNullGame.length; i++) {
          Tool.SetByte(location + i, mNullGame[i]);
        }
      }
    } else {
      StaticUtils.AddError('INVALID game. Week=$week Game of Week=$gameOfWeek');
    }
  }

  DateTime GetGameTime(int week, int gameOfWeek) {
    int location = GameLocation(week, gameOfWeek);
    Uint8List data = Tool.GameSaveData!;
    int year = 2000 + data[location + Game.YearTwoDigit.value];
    int month = data[location + Game.Month.value];
    int day = data[location + Game.Day.value];
    int hour = data[location + Game.HourOfDay.value];
    int minute = data[location + Game.MinuteOfHour.value];

    DateTime time = DateTime(year, month, day, hour, minute, 0);

    int weekday = time.weekday; // 1=Mon..7=Sun
    int newYear = 2000 + mYear;
    time = DateTime(newYear, time.month, time.day, time.hour, time.minute);
    // Advance until same weekday
    while (time.weekday != weekday)
      time = time.add(Duration(days: 1));
    return time;
  }

  /// Returns a string like "49ers at giants" for a valid week/game combo.
  String? GetGame(int week, int gameOfWeek) {
    int location = GameLocation(week, gameOfWeek);
    if (location == -1) return null;

    Uint8List data = Tool.GameSaveData!;
    // If the game is a bye
    if (location > 2 && data[location - 1] == 0x07)
      return '';

    int awayIndex = data[location + 1];
    int homeIndex = data[location];
    String ret = '';

    if (awayIndex < 0x20) {
      ret = '${GetTeamFromIndex(awayIndex)} at ${GetTeamFromIndex(homeIndex)}';
    }
    return ret;
  }

  /// Returns a week from the season. [week] is 0-16 (0 = week 1).
  String? GetWeek(int week) {
    if (week < 0 || week > mGamesPerWeek.length - 1) return null;
    StringBuffer sb = StringBuffer();
    sb.write('WEEK\n');

    int numGames = 0;
    for (int i = 0; i < mGamesPerWeek[week]; i++) {
      String? game = GetGame(week, i);
      if (game != null && game.isNotEmpty) {
        sb.write('$game\n');
        numGames++;
      }
    }
    sb.write('\n');
    return sb.toString().replaceFirst(
        'WEEK', 'WEEK ${week + 1}  [$numGames games]');
  }

  String GetSchedule() {
    StringBuffer sb = StringBuffer();
    sb.write('YEAR=${Tool.Year}\n\n');
    for (int week = 0; week < mGamesPerWeek.length; week++)
      sb.write(GetWeek(week) ?? '');
    return sb.toString();
  }

  int GameLocation(int week, int gameOfWeek) {
    if (week < 0 || week > mGamesPerWeek.length - 1 ||
        gameOfWeek > mGamesPerWeek[week] || gameOfWeek < 0)
      return -1;

    int offset = 0;
    for (int i = 0; i < week; i++)
      offset += (mGamesPerWeek[i] * 8) + 8;
    offset += gameOfWeek * 8;
    return WeekOneStartLoc + offset;
  }

  List<String> GetErrorMessages() {
    return StaticUtils.Errors;
  }

  void IncrementTeamGames(int teamIndex) {
    mTeamGames ??= List.filled(0x20, 0);
    if (teamIndex < mTeamGames!.length)
      mTeamGames![teamIndex]++;
  }

  List<String> Ensure17Weeks(List<String> lines) {
    int wks = CountWeeks(lines);
    for (int i = lines.length - 2; i > 0; i -= 2) {
      String line1 = lines[i];
      String line2 = lines[i + 1];
      if (wks > 16) {
        break;
      } else if (line1.contains('at') && line2.contains('at')) {
        lines.insert(i + 1, 'WEEK ');
        i--;
        wks++;
      }
    }
    return lines;
  }

  /// Lay out the schedule first game to last game, dividing the games up by games per week.
  void ReLayoutScheduleWeeks(List<String> lines) {
    // first, remove all the 'WEEK' lines (non-game lines)
    for (int i = lines.length - 1; i > -1; i--)
      if (mGameRegex.firstMatch(lines[i]) == null)
        lines.removeAt(i);
    int startAt = lines.length;
    List<int> gamesPerWeek = [16, 16, 14, 14, 14, 14, 14, 14, 14, 14, 16, 16, 16, 16, 16, 16, 16];
    for (int j = gamesPerWeek.length - 1; j > -1; j--) {
      startAt -= gamesPerWeek[j];
      if (startAt < 0) startAt = 0;
      lines.insert(startAt, 'WEEK 1');
    }
  }

  int CountWeeks(List<String> lines) {
    int count = 0;
    for (String line in lines) {
      if (line.toLowerCase().contains('week')) count++;
    }
    return count;
  }

  int GetTeamIndex(String teamName) {
    if (teamName.toLowerCase() == 'null') return 255;
    for (int i = 0; i < mTeams.length; i++) {
      if (mTeams[i] == teamName) return i;
    }
    return -1;
  }

  /// Returns the team specified by the index passed. (0 = 49ers).
  String? GetTeamFromIndex(int index) {
    if (index == 255) return 'null';
    if (index < 0 || index > mTeams.length - 1) return null;
    return mTeams[index];
  }
}
