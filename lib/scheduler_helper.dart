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
 * Franchise file: Starts at 0x917EB, same format. Weeks 18–22 are playoffs (indices 17–21).
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

  /// When true, GetGame() appends day-of-week and time to each game string.
  static bool showDateTime = false;

  /// When true, GetSchedule() includes all playoff weeks regardless of whether
  /// they have any games scheduled. Default (false) hides empty playoff weeks.
  static bool showAllPlayoffGames = false;

  List<int>? mTeamGames;

  // for schedule files it's '2', for franchise files it's '0x917EB'.
  int mWeekOneStartLoc = _mFranchiseFileWeekOneStartLoc;
  static const int _mFranchiseFileWeekOneStartLoc = 0x917EB;
  static const int _mScheduleFileWeekOneStartLoc = 2;

  // Playoff week indices (0-based): week 17 = Wild Card (displayed as WEEK 18), etc.
  static const int kWildCardWeekIndex     = 17;
  static const int kDivisionalWeekIndex   = 18;
  static const int kChampionshipWeekIndex = 19;
  static const int kProBowlWeekIndex      = 20;
  static const int kSuperBowlWeekIndex    = 21;

  int mWeek = 0, mWeekGameCount = 0, mTotalGameCount = 0;

  // Supports optional day-of-week token and time: "away at home [sun|mon|...|sat] [H:MM]"
  final RegExp mGameRegex = RegExp(
    r'([0-9a-z]+)\s+at\s+([0-9a-z]+)'
    r'(?:\s+(sun|mon|tue|wed|thu|fri|sat))?'
    r'(?:\s+(\d{1,2}):(\d{2}))?',
  );

  // mGamesPerWeek[i] = number of real game slots in week i (0-based).
  // The franchise file always uses a fixed 136-byte stride per week (16 slots × 8 + separator × 8),
  // regardless of how many real games are played that week.
  final List<int> mGamesPerWeek = [
    16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, // weeks 1–17
    4, 4, 2, 1, 1, // Wild Card, Divisional, Championship, Pro Bowl, Super Bowl
  ];

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

    final RegExp weekNumRegex = RegExp(r'week\s+(\d+)', caseSensitive: false);

    // Determine what this schedule file contains.
    bool hasRegularSeasonWeeks = lines.any((l) {
      final wm = weekNumRegex.firstMatch(l.trim());
      return wm != null && (int.tryParse(wm.group(1)!) ?? 0) <= 17;
    });
    bool hasPlayoffWeeks = lines.any((l) {
      final wm = weekNumRegex.firstMatch(l.trim());
      return wm != null && (int.tryParse(wm.group(1)!) ?? 0) >= 18;
    });

    // PatchSchedule resets regular season weeks from the embedded template.
    // Skip it for playoff-only files so the existing season data is preserved.
    if (hasRegularSeasonWeeks || !hasPlayoffWeeks) {
      PatchSchedule();
    }

    // set up the year
    if (Tool.Year > 0) {
      String theYear = Tool.Year.toString();
      if (theYear.length > 1) {
        theYear = theYear.substring(theYear.length - 2, theYear.length);
        mYear = int.parse(theYear);
      }
    }

    // Auto-correction re-layouts game lines and inserts WEEK markers — it must
    // not run when the file contains playoff week markers (≥18) because it would
    // scramble them into the regular-season layout.
    if (AUTO_CORRECT_SCHEDULE && !hasPlayoffWeeks) {
      ReLayoutScheduleWeeks(lines);
      lines = Ensure17Weeks(lines);
    }

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].toString().trim().toLowerCase();
      if (line.startsWith('#') || line.length < 3) {
        // do nothing
      } else if (line.startsWith('week')) {
        if (mWeek >= mGamesPerWeek.length) {
          StaticUtils.AddError('Error! Week ${mWeek + 1} exceeds the maximum of ${mGamesPerWeek.length} weeks.');
          break;
        }
        // Parse the week number so we can jump directly to it (e.g., "WEEK 18"
        // in a playoff-only file should land on Wild Card, not week 1).
        final wm = weekNumRegex.firstMatch(line);
        int targetWeekIndex = wm != null ? (int.parse(wm.group(1)!) - 1) : -1;
        // Close the currently open week.
        CloseWeek();
        // If the file skips ahead (e.g., starts at WEEK 18), jump there directly.
        // PatchSchedule has already initialized any skipped weeks.
        if (targetWeekIndex > mWeek) {
          mWeek = targetWeekIndex;
        }
      } else {
        ScheduleGameFromLine(line);
      }
    }
    CloseWeek(); // close the last week

    if (hasRegularSeasonWeeks && mWeek < 17) {
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
      int maxSlots = (mWeek < mGamesPerWeek.length) ? mGamesPerWeek[mWeek] : 16;
      if (maxSlots == 16) {
        // Regular season: fill remaining slots with null/bye marker.
        int i = mWeekGameCount;
        while (i < 16) {
          ScheduleGameByIndex(0xff, 0xff, mWeek, i);
          i++;
        }
      }
      // Playoff weeks: unused slots are already zeros in the file; leave them.
    }
    mWeek++;
    mTotalGameCount += mWeekGameCount;
    mWeekGameCount = 0;
  }

  /// Attempts to schedule a game from a line string.
  /// Supports extended format: `away at home [dow] [H:MM]`
  /// where dow is one of: sun mon tue wed thu fri sat
  bool ScheduleGameFromLine(String line) {
    bool ret = false;
    RegExpMatch? m = mGameRegex.firstMatch(line);

    if (m != null) {
      String awayTeam = m.group(1)!;
      String homeTeam = m.group(2)!;
      String? dowToken  = m.group(3);
      String? hourStr   = m.group(4);
      String? minuteStr = m.group(5);
      int? targetWeekday = dowToken != null ? _dowTokenToWeekday(dowToken) : null;
      int? hour   = hourStr   != null ? int.tryParse(hourStr)   : null;
      int? minute = minuteStr != null ? int.tryParse(minuteStr) : null;

      int maxGames = (mWeek >= 0 && mWeek < mGamesPerWeek.length) ? mGamesPerWeek[mWeek] : 16;
      bool isTbd = awayTeam == 'tbd' && homeTeam == 'tbd';

      if (mWeekGameCount >= maxGames) {
        StaticUtils.AddError(
            'Error! Week ${mWeek + 1}: Too many games (max $maxGames).');
        ret = false;
      } else if (isTbd) {
        // "tbd at tbd": keep existing team bytes, only update date/time.
        if (targetWeekday != null || hour != null) {
          _applyGameTimeOverrides(mWeek, mWeekGameCount, targetWeekday, hour, minute);
        }
        mWeekGameCount++;
        ret = true;
      } else if (ScheduleGame(awayTeam, homeTeam, mWeek, mWeekGameCount)) {
        if (targetWeekday != null || hour != null) {
          _applyGameTimeOverrides(mWeek, mWeekGameCount, targetWeekday, hour, minute);
        }
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
          'Game $gameOfWeek for week $week is not valid. Valid games for week $week are 0-15.');
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
        // Playoff games keep year=0x00; do not overwrite.
        if (week < kWildCardWeekIndex) {
          Tool.SetByte(location + Game.YearTwoDigit.value, mYear);
        }

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

  /// Sets date and/or time fields for a specific game without touching other bytes.
  /// [week] is 0-based (0=week 1, 17=Wild Card, 21=Super Bowl).
  /// [gameOfWeek] is 0-based within the week. Pass null for any field to leave it unchanged.
  void SetGameDateTime(int week, int gameOfWeek, {int? month, int? day, int? hour, int? minute}) {
    int location = GameLocation(week, gameOfWeek);
    if (location == -1) {
      StaticUtils.AddError('Invalid week=$week gameOfWeek=$gameOfWeek');
      return;
    }
    if (month  != null) Tool.SetByte(location + Game.Month.value,        month);
    if (day    != null) Tool.SetByte(location + Game.Day.value,          day);
    // Noon (12 PM) is encoded as 0 in the file; user input "12" maps to 0.
    if (hour   != null) Tool.SetByte(location + Game.HourOfDay.value,    hour == 12 ? 0 : hour);
    if (minute != null) Tool.SetByte(location + Game.MinuteOfHour.value, minute);
  }

  /// Returns a string like "49ers at giants" for a valid week/game combo.
  /// When [showDateTime] is true, appends "  dow H:MM" (e.g. "  sun 4:15").
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

    if (awayIndex >= 0x20) {
      // Both home and away use out-of-range placeholder indices (e.g. Super Bowl uses
      // 0x20/0x21 permanently; other playoff rounds use 0x00 = 49ers as TBD placeholder).
      // Nothing to display until the engine fills in real teams.
      return ret;
    }
    // Note: index 0x00 = 49ers also serves as the "not yet scheduled" TBD placeholder for
    // playoff rounds that haven't resolved yet. "49ers at 49ers" in playoff output means
    // both slots are 0x00 — not actually the 49ers.
    ret = '${GetTeamFromIndex(awayIndex)} at ${GetTeamFromIndex(homeIndex)}';

    if (showDateTime) {
      try {
        int month   = data[location + Game.Month.value];
        int day     = data[location + Game.Day.value];
        int yearB   = data[location + Game.YearTwoDigit.value];
        // Playoff games store year=0x00; use mYear for day-of-week calculation.
        int year    = yearB == 0 ? (2000 + mYear) : (2000 + yearB);
        int hour    = data[location + Game.HourOfDay.value];
        int minute  = data[location + Game.MinuteOfHour.value];
        DateTime dt = DateTime(year, month, day);
        String dow  = _weekdayToToken(dt.weekday);
        String hr   = hour == 0 ? '12' : '$hour';
        ret += '  $dow $hr:${minute.toString().padLeft(2, '0')}';
      } catch (_) {
        // ignore invalid date bytes
      }
    }
    return ret;
  }

  /// Returns a week from the season. [week] is 0-based (0 = week 1).
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
    // Non-franchise files contain only 17 regular-season weeks.
    int maxWeek = FranchiseScheduleMode ? mGamesPerWeek.length : kWildCardWeekIndex;
    bool playoffHeaderWritten = false;
    for (int week = 0; week < maxWeek; week++) {
      bool isPlayoff = week >= kWildCardWeekIndex;
      if (isPlayoff && !showAllPlayoffGames) {
        bool hasGames = false;
        for (int i = 0; i < mGamesPerWeek[week] && !hasGames; i++) {
          String? game = GetGame(week, i);
          if (game != null && game.isNotEmpty) hasGames = true;
        }
        if (!hasGames) continue;
      }
      if (isPlayoff && !playoffHeaderWritten) {
        sb.write('--- PLAYOFFS ---\n\n');
        playoffHeaderWritten = true;
      }
      sb.write(GetWeek(week) ?? '');
    }
    return sb.toString();
  }

  /// Returns the file offset of the specified game record.
  /// [week] is 0-based; [gameOfWeek] is 0-based within the week.
  /// Returns -1 for out-of-range inputs.
  int GameLocation(int week, int gameOfWeek) {
    if (week < 0 || week >= mGamesPerWeek.length ||
        gameOfWeek < 0 || gameOfWeek >= mGamesPerWeek[week])
      return -1;

    // The franchise file always uses a 136-byte stride per week
    // (16 game slots × 8 bytes + 1 separator slot × 8 bytes).
    const int kWeekStride = 136;
    return WeekOneStartLoc + week * kWeekStride + gameOfWeek * 8;
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

  // -- Day-of-week helpers --

  /// Converts a three-letter DOW token to Dart's weekday (1=Mon … 7=Sun).
  static int _dowTokenToWeekday(String token) {
    const map = <String, int>{
      'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
    };
    return map[token.toLowerCase()] ?? 1;
  }

  /// Converts a Dart weekday (1=Mon … 7=Sun) to a three-letter DOW token.
  static String _weekdayToToken(int weekday) {
    const tokens = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    return tokens[(weekday - 1) % 7];
  }

  /// Adjusts the stored date/time for a just-scheduled game to match optional overrides.
  void _applyGameTimeOverrides(
      int week, int gameOfWeek, int? targetWeekday, int? hour, int? minute) {
    int location = GameLocation(week, gameOfWeek);
    if (location < 0) return;
    Uint8List data = Tool.GameSaveData!;

    if (targetWeekday != null) {
      int month  = data[location + Game.Month.value];
      int day    = data[location + Game.Day.value];
      int yearB  = data[location + Game.YearTwoDigit.value];
      int year   = yearB == 0 ? (2000 + mYear) : (2000 + yearB);
      try {
        DateTime current = DateTime(year, month, day);
        // Shift ±3 days at most to reach the target weekday.
        int delta = (targetWeekday - current.weekday) % 7;
        if (delta > 3) delta -= 7;
        // Use calendar arithmetic (year/month/day+delta) rather than
        // Duration arithmetic to avoid DST: on fall-back days adding
        // Duration(days:1) = 86400 s lands at 23:00 of the same calendar day.
        DateTime target = DateTime(current.year, current.month, current.day + delta);
        Tool.SetByte(location + Game.Month.value, target.month);
        Tool.SetByte(location + Game.Day.value,   target.day);
      } catch (_) {
        // ignore invalid date
      }
    }
    // Noon (12 PM) is encoded as 0 in the file; user input "12" maps to 0.
    if (hour   != null) Tool.SetByte(location + Game.HourOfDay.value,    hour == 12 ? 0 : hour);
    if (minute != null) Tool.SetByte(location + Game.MinuteOfHour.value, minute);
  }
}
