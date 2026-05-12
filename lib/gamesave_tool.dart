// Translated from GamesaveTool.cs
// ignore_for_file: non_constant_identifier_names

import 'dart:math';
import 'dart:typed_data';
import 'enum_definitions.dart';
import 'static_utils.dart';
import 'data_map.dart';
import 'depth_chart.dart';
import 'scheduler_helper.dart';
import 'logger.dart';
import 'jersey_data.dart';

/// The class that reads and modifies the xbox game save file.
class GamesaveTool {
  final Map<String, int> mCoachMap = {};
  final Map<int, String> mReverseCoachMap = {};

  int mPlayerStart = 0xB288;
  int mModifiableNameSectionEnd = 0x8906f;
  int mCollegePlayerNameSectionStart = 0x8bab0;
  int mCollegePlayerNameSectionEnd = 0x8f2ef;
  int mStringTableStart = 0x75c40;
  int mStringTableEnd = 0x94d10;
  int m49ersPlayerPointersStart = 0x44a8;
  int m49ersNumPlayersAddress = 0x45c4;
  int mFreeAgentCountLocation = 0x358;
  int mFreeAgentPlayersPointer = 0x35c;
  int mCoachPointerOffset = 0x14c;
  int mCoachStringSectionLength = 0x14b1;
  int mMaxPlayers = 2317;

  static const int FirstDraftClassPlayer = 1937;
  static const int _mDraftClassSize = 380;
  static const int _cPlayerDataLength = 0x54;
  static const int _cTeamDiff = 0x1f4;
  static const int _cTeamDataPtrOffset       = 0x104; // team_block → S3a nickname ptr
  static const int _cTeamStadiumByteOffset   = 0x118; // team_block → stadium index byte
  static const int _cTeamLogoByteOffset      = 0x154; // team_block → logo/PBP index byte
                                                       // (S3a[2] string kept in sync)
  static const int _cTeamDefaultJerseyOffset = 0x192; // team_block → default jersey index
  int _cPlaybookTableBase = 0x2C90;                     // absolute; stride 8 per team
                                                        // bytes 0-3=offense ptr, 4-7=defense ptr
                                                        // (relative string pointers to name/abbrev)
                                                        // franchise=0x2C90, roster=0x29B0

  // Stadium lookup maps — populated by _buildStadiumLookup() at load time.
  final Map<int, int>    _stadiumShortNameAddresses = {}; // index → S1a address
  final Map<String, int> _stadiumNameToIndex        = {}; // short name → index

  // Playbook lookup — populated by _buildPlaybookLookup() at load time.
  // Keyed by offense name (e.g. "West Coast"); value is (offAddr, defAddr) pair.
  final Map<String, int> _playbookOffAddr = {}; // offense name → offense string address
  final Map<String, int> _playbookDefAddr = {}; // offense name → defense string address
  static const String NFL2K5Folder = '53450030';

  SaveType mSaveType = SaveType.Franchise;
  SaveType get saveType => mSaveType;
  void _SetSaveType(SaveType value) {
    mSaveType = value;
    Logger.log('#Loading SaveType:${value.name}');
  }

  String mZipFile = '';

  Uint8List? GameSaveData;
  int Year = 0;

  void loadSaveData(Uint8List data) {
    GameSaveData = data;
    setupForSaveType();
    checkNamePointers();
  }

  /// Detects save type from header magic bytes and calls the appropriate
  /// initializer. Can be called directly when GameSaveData is assigned
  /// externally (e.g. in AutoFixSkinFromPhoto).
  void setupForSaveType() {
    mColleges.clear();
    if (GameSaveData![0] == 0x52 && GameSaveData![1] == 0x4F &&
        GameSaveData![2] == 0x53 && GameSaveData![3] == 0x54) {
      InitializeForRoster();
    } else {
      InitializeForFranchise();
    }
    _buildStadiumLookup();
    _buildPlaybookLookup();
  }

  GamesaveTool() {
    mCoachMap['Dennis Green'] = 0x00;
    mCoachMap['Jim Mora Jr.'] = 0x01;
    mCoachMap['Brian Billick'] = 0x02;
    mCoachMap['Mike Mularkey'] = 0x03;
    mCoachMap['John Fox'] = 0x04;
    mCoachMap['Lovie Smith'] = 0x05;
    mCoachMap['Marvin Lewis'] = 0x06;
    mCoachMap['Mike Shanahan'] = 0x08;
    mCoachMap['Dallas Coach'] = 0x07;
    mCoachMap['Steve Mariucci'] = 0x09;
    mCoachMap['Mike Sherman'] = 0x0A;
    mCoachMap['Tony Dungy'] = 0x0B;
    mCoachMap['Jack Del Rio'] = 0x0C;
    mCoachMap['Dick Vermeil'] = 0x0D;
    mCoachMap['Dave Wannstedt'] = 0x0E;
    mCoachMap['Mike Tice'] = 0x0F;
    mCoachMap['Bill Belichick'] = 0x10;
    mCoachMap['Jim Haslett'] = 0x11;
    mCoachMap['Tom Coughlin'] = 0x12;
    mCoachMap['Herman Edwards'] = 0x13;
    mCoachMap['Norv Turner'] = 0x14;
    mCoachMap['Andy Reid'] = 0x15;
    mCoachMap['Bill Cowher'] = 0x16;
    mCoachMap['Mike Martz'] = 0x17;
    mCoachMap['Marty Schottenheimer'] = 0x18;
    mCoachMap['Dennis Erickson'] = 0x19;
    mCoachMap['Mike Holmgren'] = 0x1A;
    mCoachMap['Jon Gruden'] = 0x1B;
    mCoachMap['Jeff Fisher'] = 0x1C;
    mCoachMap['Joe Gibbs'] = 0x1D;
    mCoachMap['Butch Davis'] = 0x1E;
    mCoachMap['Dom Capers'] = 0x25;
    mCoachMap['Generic1'] = 0x32;
    mCoachMap['Generic2'] = 0x33;

    mReverseCoachMap[0x00] = 'Dennis Green';
    mReverseCoachMap[0x01] = 'Jim Mora Jr.';
    mReverseCoachMap[0x02] = 'Brian Billick';
    mReverseCoachMap[0x03] = 'Mike Mularkey';
    mReverseCoachMap[0x04] = 'John Fox';
    mReverseCoachMap[0x05] = 'Lovie Smith';
    mReverseCoachMap[0x06] = 'Marvin Lewis';
    mReverseCoachMap[0x08] = 'Mike Shanahan';
    mReverseCoachMap[0x07] = 'Dallas Coach';
    mReverseCoachMap[0x09] = 'Steve Mariucci';
    mReverseCoachMap[0x0A] = 'Mike Sherman';
    mReverseCoachMap[0x0B] = 'Tony Dungy';
    mReverseCoachMap[0x0C] = 'Jack Del Rio';
    mReverseCoachMap[0x0D] = 'Dick Vermeil';
    mReverseCoachMap[0x0E] = 'Dave Wannstedt';
    mReverseCoachMap[0x0F] = 'Mike Tice';
    mReverseCoachMap[0x10] = 'Bill Belichick';
    mReverseCoachMap[0x11] = 'Jim Haslett';
    mReverseCoachMap[0x12] = 'Tom Coughlin';
    mReverseCoachMap[0x13] = 'Herman Edwards';
    mReverseCoachMap[0x14] = 'Norv Turner';
    mReverseCoachMap[0x15] = 'Andy Reid';
    mReverseCoachMap[0x16] = 'Bill Cowher';
    mReverseCoachMap[0x17] = 'Mike Martz';
    mReverseCoachMap[0x18] = 'Marty Schottenheimer';
    mReverseCoachMap[0x19] = 'Dennis Erickson';
    mReverseCoachMap[0x1A] = 'Mike Holmgren';
    mReverseCoachMap[0x1B] = 'Jon Gruden';
    mReverseCoachMap[0x1C] = 'Jeff Fisher';
    mReverseCoachMap[0x1D] = 'Joe Gibbs';
    mReverseCoachMap[0x1E] = 'Butch Davis';
    mReverseCoachMap[0x25] = 'Dom Capers';
    mReverseCoachMap[0x32] = 'Generic1';
    mReverseCoachMap[0x33] = 'Generic2';
  }

  void InitializeForFranchise() {
    _SetSaveType(SaveType.Franchise);
    mPlayerStart = 0xB288;
    mModifiableNameSectionEnd = 0x8906f;
    mCollegePlayerNameSectionStart = 0x8bab0;
    mCollegePlayerNameSectionEnd = 0x8f2ef;
    mStringTableStart = 0x75c40;
    mStringTableEnd = 0x94d10;
    mFreeAgentPlayersPointer = 0x35c;
    mFreeAgentCountLocation = 0x358;
    m49ersPlayerPointersStart = 0x44a8;
    m49ersNumPlayersAddress = 0x45c4;
    mMaxPlayers = 2317;
    _cPlaybookTableBase = 0x2C90;
    SchedulerHelper.FranchiseGameOneYearLocation = 0x917ef;
    Year = 2000 + GameSaveData![SchedulerHelper.FranchiseGameOneYearLocation];
    AutoPlayerStartLocation();
  }

  void InitializeForRoster() {
    _SetSaveType(SaveType.Roster);
    mPlayerStart = 0xAFA8;
    mModifiableNameSectionEnd = 0x88d8f;
    mCollegePlayerNameSectionStart = 0x8b7d0;
    mCollegePlayerNameSectionEnd = 0x8f00f;
    mStringTableStart = 0x75960;
    mStringTableEnd = 0x88d80;
    mFreeAgentPlayersPointer = 0x7c;
    mFreeAgentCountLocation = 0x78;
    m49ersPlayerPointersStart = 0x41c8;
    m49ersNumPlayersAddress = 0x42e4;
    mMaxPlayers = 1943;
    _cPlaybookTableBase = 0x29B0;
    Year = 0;
    AutoPlayerStartLocation();
  }

  int GetCoachPointer(int teamIndex) {
    return m49ersPlayerPointersStart + mCoachPointerOffset + teamIndex * _cTeamDiff;
  }

  Uint8List GetCoachBytes(int teamIndex) {
    if (teamIndex < 32) {
      int coachPointer = GetCoachPointer(teamIndex);
      int coach_ptr = GetPointerDestination(coachPointer);
      int end = coach_ptr + CoachOffsets.EmptyPass.value + 1;
      return Uint8List.fromList(GameSaveData!.sublist(coach_ptr, end));
    }
    return Uint8List(0);
  }

  String get CoachKeyAll => mCoachKeyAll;

  static const String mCoachKeyAll =
      'Coach,Team,FirstName,LastName,Info1,Info2,Info3,Body,Photo,Wins,Losses,Ties,SeasonsWithTeam,totalSeasons,WinningSeasons,SuperBowls,SuperBowlWins,SuperBowlLosses,PlayoffWins,' +
          'PlayoffLosses,Overall,OvrallOffense,RushFor,PassFor,OverallDefense,PassRush,PassCoverage,QB,RB,TE,WR,OL,DL,LB,SpecialTeams,Professionalism,Preparation,' +
          'Conditioning,Motivation,Leadership,Discipline,Respect,PlaycallingRun,ShotgunRun,IFormRun,SplitbackRun,EmptyRun,ShotgunPass,SplitbackPass,IFormPass,LoneBackPass,EmptyPass';

  static const String DefaultCoachKey = 'Coach,Team,FirstName,LastName,Body,Photo';
  String mCoachKey = DefaultCoachKey;

  String get CoachKey => mCoachKey;
  set CoachKey(String value) {
    String lastAttr = '';
    try {
      List<String> parts = value.split(',');
      for (String part in parts) {
        if (part.isNotEmpty &&
            part.toLowerCase() != 'team' &&
            part.toLowerCase() != 'coach') {
          lastAttr = part;
          CoachOffsets.values.firstWhere(
              (e) => e.name.toLowerCase() == part.toLowerCase());
        }
      }
      mCoachKey = value;
    } catch (e) {
      StaticUtils.AddError("Error setting CoachKey part='$lastAttr' in '$value'");
    }
  }

  void SetCoachAttribute(int teamIndex, CoachOffsets attr, String value) {
    if (teamIndex < 32) {
      int coachPointer = GetCoachPointer(teamIndex);
      int coach_loc = GetPointerDestination(coachPointer);
      int loc = coach_loc + attr.value;
      int val, v1, v2;
      String strVal;

      switch (attr) {
        case CoachOffsets.FirstName:
        case CoachOffsets.LastName:
        case CoachOffsets.Info1:
        case CoachOffsets.Info2:
        case CoachOffsets.Info3:
          SetCoachString(value.replaceAll('"', ''), loc);
          break;
        case CoachOffsets.Photo:
          val = int.parse(value);
          v1 = val & 0xff;
          v2 = val >> 8;
          SetByte(loc, v1);
          SetByte(loc + 1, v2);
          break;
        case CoachOffsets.Body:
          strVal = value.replaceAll('[', '').replaceAll(']', '');
          if (mCoachMap.containsKey(strVal))
            SetByte(loc, mCoachMap[strVal]!);
          else
            StaticUtils.AddError(
                "Error Setting Body '$value' value for ${sTeamsDataOrder[teamIndex]} Coach");
          break;
        default:
          v1 = int.parse(value);
          SetByte(loc, v1);
          break;
      }
    }
  }

  String GetCoachAttribute(int teamIndex, CoachOffsets attr) {
    String retVal = '!!!!Invalid!!!!';
    if (teamIndex < 32) {
      int coachPointer = GetCoachPointer(teamIndex);
      int coach_ptr = GetPointerDestination(coachPointer);
      int loc = coach_ptr + attr.value;
      switch (attr) {
        case CoachOffsets.FirstName:
        case CoachOffsets.LastName:
        case CoachOffsets.Info1:
        case CoachOffsets.Info2:
        case CoachOffsets.Info3:
          int str_ptr = coach_ptr + attr.value;
          retVal = GetName(str_ptr);
          break;
        case CoachOffsets.Body:
          int body_ptr = coach_ptr + CoachOffsets.Body.value;
          int bodyNumber = GameSaveData![body_ptr];
          retVal = mReverseCoachMap[bodyNumber] ?? '!!!!Invalid!!!!';
          break;
        case CoachOffsets.Photo:
          int val = GameSaveData![loc + 1] << 8;
          val += GameSaveData![loc];
          retVal = '$val';
          switch (retVal.length) {
            case 3: retVal = '0$retVal'; break;
            case 2: retVal = '00$retVal'; break;
            case 1: retVal = '000$retVal'; break;
          }
          break;
        default:
          retVal = '${GameSaveData![loc]}';
          break;
      }
    }
    if (retVal.contains(',')) {
      retVal = '"$retVal"';
    }
    return retVal;
  }

  String GetCoachData(int teamIndex) {
    String retVal = '!!!!!!!!INVALID!!!!!!!!!!!!';
    if (teamIndex < 32) {
      StringBuffer builder = StringBuffer('Coach,');
      builder.write(sTeamsDataOrder[teamIndex]);
      builder.write(',');
      String key = CoachKey.toLowerCase().replaceAll('fname', 'FirstName').replaceAll('lname', 'LastName');
      List<String> parts = key.split(',');
      for (String part in parts) {
        if (part.isEmpty || part == 'coach' || part == 'team') continue;
        try {
          CoachOffsets attr = CoachOffsets.values
              .firstWhere((e) => e.name.toLowerCase() == part.toLowerCase());
          if ('body'.toLowerCase() == part.toLowerCase()) {
            builder.write('[');
            builder.write(GetCoachAttribute(teamIndex, attr));
            builder.write('],');
          } else {
            builder.write(GetCoachAttribute(teamIndex, attr));
            builder.write(',');
          }
        } catch (e) {
          // skip unknown parts
        }
      }
      String built = builder.toString();
      if (built.endsWith(','))
        built = built.substring(0, built.length - 1);
      retVal = built;
    }
    return retVal;
  }

  String GetCoachDataAll() {
    StringBuffer builder = StringBuffer();
    builder.write('\n\nCoachKEY=');
    builder.write(CoachKey);
    builder.write('\n');
    for (int i = 0; i < 32; i++) {
      builder.write(GetCoachData(i));
      builder.write('\r\n');
    }
    return builder.toString();
  }

  // ─── Team data (S3a) and stadium (S1a) ─────────────────────────────────────

  static const String DefaultTeamKey = 'TeamData,Team,Nickname,Abbrev,Stadium,City,AbbrAlt,Logo,Playbook,DefaultJersey';
  String mTeamKeyAll =
      'TeamData,Team,Nickname,Abbrev,Stadium,City,AbbrAlt,Logo,Playbook,DefaultJersey';
  String get TeamKeyAll => mTeamKeyAll;
  String mTeamKey = DefaultTeamKey;
  String get TeamKey => mTeamKey;

  set TeamKey(String value) {
    String lastAttr = '';
    try {
      for (String part in value.split(',')) {
        if (part.isNotEmpty &&
            part.toLowerCase() != 'team' &&
            part.toLowerCase() != 'teamdata') {
          lastAttr = part;
          TeamDataOffsets.values.firstWhere(
              (e) => e.name.toLowerCase() == part.toLowerCase());
        }
      }
      mTeamKey = value;
    } catch (e) {
      StaticUtils.AddError(
          "Error setting TeamKey part='$lastAttr' in '$value'");
    }
  }

  /// Scan S1a once at load time to build the stadium index ↔ address maps.
  void _buildStadiumLookup() {
    _stadiumShortNameAddresses.clear();
    _stadiumNameToIndex.clear();

    // S1a ends where S2 begins — the address of coach 0's FirstName string.
    int s2Start = GetPointerDestination(
        GetPointerDestination(GetCoachPointer(0)));

    // S1a layout per entry: short_name → city → sNN_code → long_name
    // We need two-back from the code to get the short name.
    int i = mStringTableStart;
    String prevStr      = '';
    int    prevAddr     = 0;
    String prevPrevStr  = '';
    int    prevPrevAddr = 0;

    while (i < s2Start - 1) {
      // Skip null padding between strings.
      while (i < s2Start - 1 && GameSaveData![i] == 0) {
        i += 2;
      }
      if (i >= s2Start - 1) break;

      int strStart = i;
      StringBuffer sb = StringBuffer();
      while (i < s2Start && GameSaveData![i] != 0) {
        sb.writeCharCode(GameSaveData![i]);
        i += 2;
      }
      String s = sb.toString();
      if (s.isEmpty) { i += 2; continue; }

      // Step over the null terminator.
      i += 2;

      // If this string looks like a stadium code "sNN", two strings back is
      // the short name (prevStr is city, prevPrevStr is short name).
      if (s.length == 3 && s[0] == 's') {
        final int? idx = int.tryParse(s.substring(1));
        if (idx != null && prevPrevStr.isNotEmpty) {
          _stadiumShortNameAddresses[idx] = prevPrevAddr;
          _stadiumNameToIndex[prevPrevStr] = idx;
        }
      }

      prevPrevStr  = prevStr;
      prevPrevAddr = prevAddr;
      prevStr      = s;
      prevAddr     = strStart;
    }
  }

  /// Scan all 32 teams' playbook pointers to build name/abbrev ↔ address maps.
  /// Silently skips entries whose pointer resolves outside the file (roster files
  /// have no playbook table at _cPlaybookTableBase).
  void _buildPlaybookLookup() {
    _playbookOffAddr.clear();
    _playbookDefAddr.clear();
    final int len = GameSaveData!.length;

    // Find the start of the playbook string block via team 0's offense pointer.
    final int firstPtrLoc = _cPlaybookTableBase;
    if (firstPtrLoc + 4 > len) return;
    int addr = GetPointerDestination(firstPtrLoc);
    if (addr < 0 || addr >= len) return;

    // Walk (offense-name, defense-abbrev) pairs consecutively in the string table.
    // All legitimate defense abbreviations are all-uppercase and ≤ 4 chars
    // (e.g. "SF", "WCO", "UA").  The first string that fails that test ends the block.
    while (addr < len) {
      int offAddr = addr;
      String offName = GetString(offAddr);
      if (offName.isEmpty) break;
      int defAddr = offAddr + offName.length * 2 + 2;
      if (defAddr + 2 > len) break;
      String defAbbrev = GetString(defAddr);
      if (defAbbrev.isEmpty || defAbbrev.length > 4 ||
          defAbbrev != defAbbrev.toUpperCase()) break;
      _playbookOffAddr[offName] = offAddr;
      _playbookDefAddr[offName] = defAddr;
      addr = defAddr + defAbbrev.length * 2 + 2;
    }
  }

  /// Convert a playbook name string to its PB_ token, e.g. "West Coast" → "PB_West_Coast".
  static String _playbookNameToToken(String name) =>
      'PB_${name.replaceAll(' ', '_')}';

  /// Convert a PB_ token back to the name string, e.g. "PB_West_Coast" → "West Coast".
  static String _playbookTokenToName(String token) =>
      token.startsWith('PB_') ? token.substring(3).replaceAll('_', ' ') : token;

  /// Write a 4-byte signed relative pointer at [ptrLoc] that points to [targetAddr].
  void _writePointerToAddr(int ptrLoc, int targetAddr) {
    int pointer = targetAddr - ptrLoc + 1;
    SetByte(ptrLoc,     pointer & 0xff);
    SetByte(ptrLoc + 1, (pointer >> 8)  & 0xff);
    SetByte(ptrLoc + 2, (pointer >> 16) & 0xff);
    SetByte(ptrLoc + 3, (pointer >> 24) & 0xff);
  }

  /// Returns the index into S3a (0–4) for the given [attr].
  /// Throws [ArgumentError] for offsets with no S3a field.
  int _teamDataOffsetToS3aIndex(TeamDataOffsets attr) {
    switch (attr) {
      case TeamDataOffsets.Nickname: return 0;
      case TeamDataOffsets.Abbrev:   return 1;
      case TeamDataOffsets.City:     return 3;
      case TeamDataOffsets.AbbrAlt:  return 4;
      default:
        throw ArgumentError('$attr has no S3a field index');
    }
  }

  /// Returns the address in S3a of the string at [s3aFieldIndex] for [teamIndex].
  int _getS3aStringAddress(int teamIndex, int s3aFieldIndex) {
    int teamBlock    = m49ersPlayerPointersStart + teamIndex * _cTeamDiff;
    int nicknameAddr = GetPointerDestination(teamBlock + _cTeamDataPtrOffset);
    int addr = nicknameAddr;
    for (int f = 0; f < s3aFieldIndex; f++) {
      String s = GetString(addr);
      addr += s.length * 2 + 2; // stride over string + null terminator
    }
    return addr;
  }

  String GetStadiumNameByIndex(int stadiumIndex) {
    int? addr = _stadiumShortNameAddresses[stadiumIndex];
    if (addr == null) return '!!!!Invalid!!!!';
    return GetString(addr);
  }

  String GetStadiumName(int teamIndex) {
    if (teamIndex < 0 || teamIndex >= 32) return '!!!!Invalid!!!!';
    int teamBlock = m49ersPlayerPointersStart + teamIndex * _cTeamDiff;
    int idx = GameSaveData![teamBlock + _cTeamStadiumByteOffset];
    return GetStadiumNameByIndex(idx);
  }

  String GetTeamString(int teamIndex, TeamDataOffsets attr) {
    if (teamIndex < 0 || teamIndex >= 32) return '!!!!Invalid!!!!';
    if (attr == TeamDataOffsets.Stadium) return GetStadiumName(teamIndex);
    int teamBlock = m49ersPlayerPointersStart + teamIndex * _cTeamDiff;
    switch (attr) {
      case TeamDataOffsets.Logo:
        return GameSaveData![teamBlock + _cTeamLogoByteOffset].toString();
      case TeamDataOffsets.DefaultJersey:
        return GameSaveData![teamBlock + _cTeamDefaultJerseyOffset].toString();
      case TeamDataOffsets.Playbook:
        return _playbookNameToToken(
            GetString(GetPointerDestination(_cPlaybookTableBase + teamIndex * 8)));
      default:
        return GetString(
            _getS3aStringAddress(teamIndex, _teamDataOffsetToS3aIndex(attr)));
    }
  }

  void SetStadiumIndex(int teamIndex, int stadiumIndex) {
    if (teamIndex < 0 || teamIndex >= 32) return;
    if (!_stadiumShortNameAddresses.containsKey(stadiumIndex)) {
      StaticUtils.AddError(
          'SetStadiumIndex: unknown stadium index $stadiumIndex');
      return;
    }
    int teamBlock = m49ersPlayerPointersStart + teamIndex * _cTeamDiff;
    SetByte(teamBlock + _cTeamStadiumByteOffset, stadiumIndex);
    // For standard NFL teams, stadium index equals logo/PBP index — keep in sync.
    SetLogoIndex(teamIndex, stadiumIndex);
  }

  void SetLogoIndex(int teamIndex, int logoIndex) {
    if (teamIndex < 0 || teamIndex >= 32) return;
    int teamBlock = m49ersPlayerPointersStart + teamIndex * _cTeamDiff;
    SetByte(teamBlock + _cTeamLogoByteOffset, logoIndex);
    // Keep S3a[2] logo string in sync (always 2 chars — same-length safe).
    int numAddr = _getS3aStringAddress(teamIndex, 2);
    String padded = logoIndex.toString().padLeft(2, '0');
    for (int i = 0; i < 2; i++) {
      SetByte(numAddr + i * 2,     padded.codeUnitAt(i));
      SetByte(numAddr + i * 2 + 1, 0);
    }
  }

  void SetTeamString(int teamIndex, TeamDataOffsets attr, String value) {
    if (teamIndex < 0 || teamIndex >= 32) return;

    if (attr == TeamDataOffsets.Stadium) {
      int? idx = _stadiumNameToIndex[value];
      if (idx == null) {
        StaticUtils.AddError(
            "SetTeamString: unknown stadium '$value' for "
            "${sTeamsDataOrder[teamIndex]}");
        return;
      }
      SetStadiumIndex(teamIndex, idx);
      return;
    }

    // Numeric byte fields
    int? intVal = int.tryParse(value.trim());
    int teamBlock = m49ersPlayerPointersStart + teamIndex * _cTeamDiff;
    switch (attr) {
      case TeamDataOffsets.Logo:
        if (intVal == null) {
          StaticUtils.AddError('SetTeamString: Logo must be an integer, got "$value"');
          return;
        }
        SetLogoIndex(teamIndex, intVal);
        return;
      case TeamDataOffsets.DefaultJersey:
        if (intVal == null) {
          StaticUtils.AddError('SetTeamString: DefaultJersey must be an integer, got "$value"');
          return;
        }
        final jerseyList = kTeamJerseyNames[sTeamsDataOrder[teamIndex]];
        if (jerseyList != null && (intVal < 0 || intVal >= jerseyList.length)) {
          StaticUtils.AddWarning(
              'SetTeamString: DefaultJersey index $intVal out of range for '
              '${sTeamsDataOrder[teamIndex]} (valid: 0–${jerseyList.length - 1})');
        }
        SetByte(teamBlock + _cTeamDefaultJerseyOffset, intVal);
        return;
      case TeamDataOffsets.Playbook: {
        final name = _playbookTokenToName(value);
        final offAddr = _playbookOffAddr[name];
        final defAddr = _playbookDefAddr[name];
        if (offAddr == null || defAddr == null) {
          StaticUtils.AddError(
              'SetTeamString: unknown playbook "$value" for ${sTeamsDataOrder[teamIndex]}. '
              'Known: ${_playbookOffAddr.keys.map(_playbookNameToToken).join(', ')}');
          return;
        }
        _writePointerToAddr(_cPlaybookTableBase + teamIndex * 8,     offAddr);
        _writePointerToAddr(_cPlaybookTableBase + teamIndex * 8 + 4, defAddr);
        return;
      }
      default:
        break;
    }

    int addr    = _getS3aStringAddress(teamIndex, _teamDataOffsetToS3aIndex(attr));
    String curr = GetString(addr);
    if (value.length > curr.length) {
      StaticUtils.AddError(
          'SetTeamString: value too long for ${sTeamsDataOrder[teamIndex]} '
          '${attr.name}: "$curr"(${curr.length}) → "$value"(${value.length}). '
          'Maximum length is ${curr.length}.');
      return;
    }
    // Shorter values are right-padded with spaces to preserve the string length
    // in S3a.  (The text-file parser trims trailing whitespace from lines, so
    // callers cannot pass trailing spaces explicitly.)
    if (value.length < curr.length) {
      value = value.padRight(curr.length);
    }
    for (int i = 0; i < value.length; i++) {
      SetByte(addr + i * 2,     value.codeUnitAt(i));
      SetByte(addr + i * 2 + 1, 0);
    }
  }

  String GetTeamData(int teamIndex) {
    if (teamIndex < 0 || teamIndex >= 32) return '';
    StringBuffer sb = StringBuffer();
    String key = TeamKey;
    for (String part in key.split(',')) {
      String lp = part.toLowerCase();
      if (lp == 'teamdata' || lp == 'team') {
        if (lp == 'teamdata') {
          sb.write('TeamData,');
        } else {
          sb.write('${sTeamsDataOrder[teamIndex]},');
        }
        continue;
      }
      try {
        TeamDataOffsets attr = TeamDataOffsets.values
            .firstWhere((e) => e.name.toLowerCase() == lp);
        String val = GetTeamString(teamIndex, attr);
        if (attr == TeamDataOffsets.Stadium) {
          sb.write('[$val],');
        } else {
          sb.write('$val,');
        }
      } catch (_) {
        // unknown key part — skip
      }
    }
    String result = sb.toString();
    if (result.endsWith(',')) result = result.substring(0, result.length - 1);
    return result;
  }

  String GetTeamDataAll() {
    StringBuffer sb = StringBuffer();
    sb.write('\n\nTeamDataKey=');
    sb.write(TeamKey);
    sb.write('\n');
    for (int i = 0; i < 32; i++) {
      sb.write(GetTeamData(i));
      sb.write('\r\n');
    }
    return sb.toString();
  }

  /// Returns the jersey name for [teamIndex] at [jerseyIndex], or null if
  /// [teamIndex] or [jerseyIndex] is out of range.
  String? GetJerseyName(int teamIndex, int jerseyIndex) {
    if (teamIndex < 0 || teamIndex >= 32) return null;
    final list = kTeamJerseyNames[sTeamsDataOrder[teamIndex]];
    if (list == null || jerseyIndex < 0 || jerseyIndex >= list.length) return null;
    return list[jerseyIndex];
  }

  /// Returns all jersey names for [teamIndex], one per line with index prefix.
  /// Format: "  N: Jersey Name"
  String GetJerseyNamesList(int teamIndex) {
    if (teamIndex < 0 || teamIndex >= 32) return '';
    final list = kTeamJerseyNames[sTeamsDataOrder[teamIndex]] ?? [];
    final sb = StringBuffer();
    for (int i = 0; i < list.length; i++) {
      sb.write('  $i: ${list[i]}\n');
    }
    return sb.toString();
  }

  /// Returns all known stadium names sorted by index, one per line.
  /// Format: "  NN: Stadium Name"  (useful for knowing valid [bracket] values)
  String GetStadiumNamesList() {
    final sb = StringBuffer();
    sb.write('\nStadium names:\n');
    final indices = _stadiumShortNameAddresses.keys.toList()..sort();
    for (final idx in indices) {
      final name = GetStadiumNameByIndex(idx);
      sb.write('  ${idx.toString().padLeft(2)}: [$name]\n');
    }
    return sb.toString();
  }

  /// Returns all known playbook names, one per line, as PB_ tokens.
  String GetPlaybookNamesList() {
    final sb = StringBuffer();
    sb.write('\nPlaybook names:\n');
    for (final name in _playbookOffAddr.keys) {
      sb.write('  ${_playbookNameToToken(name)}\n');
    }
    return sb.toString();
  }

  // ─── End team data ──────────────────────────────────────────────────────────

  void AutoPlayerStartLocation() {
    int firstPlayerLoc = GameSaveData!.length;
    for (int t = 0; t < 33; t++) {
      String team = sTeamsDataOrder[t];
      int teamIndex = GetTeamIndex(team);
      int teamPlayerPointersStart = teamIndex * _cTeamDiff + m49ersPlayerPointersStart;
      if (team.toLowerCase() == 'freeagents')
        teamPlayerPointersStart = GetPointerDestination(mFreeAgentPlayersPointer);

      int numPlayers = GetNumPlayers(team);
      int pointerLoc = -1;

      for (int i = 0; i < numPlayers; i++) {
        pointerLoc = teamPlayerPointersStart + (i * 4);
        int ptr = GameSaveData![pointerLoc + 3] << 24;
        ptr += GameSaveData![pointerLoc + 2] << 16;
        ptr += GameSaveData![pointerLoc + 1] << 8;
        ptr += GameSaveData![pointerLoc];
        if (ptr >= 0x80000000) ptr -= 0x100000000;
        int playerLoc = ptr + pointerLoc - 1;
        if (playerLoc < firstPlayerLoc && ValidPlayer(playerLoc))
          firstPlayerLoc = playerLoc;
      }
    }
    // Only update if a candidate was actually found; if firstPlayerLoc stayed
    // at GameSaveData!.length it means no valid player was found and we must
    // leave mPlayerStart at the hard-coded default for this save type.
    if (firstPlayerLoc < GameSaveData!.length && firstPlayerLoc != mPlayerStart)
      mPlayerStart = firstPlayerLoc;
  }

  final RegExp mInValidPlayerTest = RegExp(r',[0-9]{2,3},');

  bool ValidPlayer(int playerLoc) {
    bool retVal = false;
    int prevFirstPlayer = mPlayerStart;
    mPlayerStart = playerLoc;
    try {
      StringBuffer builder = StringBuffer();
      GetPlayerAppearanceAttribute(0, AppearanceAttributes.College, builder);
      String built = builder.toString();
      if (built.endsWith(',')) built = built.substring(0, built.length - 1);
      String college = built.replaceAll('"', '');

      List<AppearanceAttributes> attrs = [
        AppearanceAttributes.Hand, AppearanceAttributes.BodyType, AppearanceAttributes.Skin, AppearanceAttributes.Face,
        AppearanceAttributes.Dreads, AppearanceAttributes.Helmet, AppearanceAttributes.FaceMask, AppearanceAttributes.Visor,
        AppearanceAttributes.EyeBlack, AppearanceAttributes.MouthPiece, AppearanceAttributes.LeftGlove, AppearanceAttributes.RightGlove,
        AppearanceAttributes.LeftWrist, AppearanceAttributes.RightWrist, AppearanceAttributes.LeftElbow, AppearanceAttributes.RightElbow,
        AppearanceAttributes.Sleeves, AppearanceAttributes.LeftShoe, AppearanceAttributes.RightShoe, AppearanceAttributes.NeckRoll,
        AppearanceAttributes.Turtleneck
      ];

      if (Colleges.containsKey(college)) {
        for (AppearanceAttributes attr in attrs) {
          GetPlayerAppearanceAttribute(0, attr, builder);
        }
        String test = builder.toString();
        if (mInValidPlayerTest.firstMatch(test) == null)
          retVal = true;
      }
    } catch (e) {
      // ignore
    } finally {
      mPlayerStart = prevFirstPlayer;
    }
    return retVal;
  }

  int get FirstPlayerFnamePointerLoc => mPlayerStart + 0x10;

  /// Returns [true] if any two player name pointers (fname or lname) resolve
  /// to the same address within the modifiable name section.
  ///
  /// Community-edited roster files built with Flying Finn's editor re-use a
  /// single string entry for multiple players to conserve space.  When [SetName]
  /// overwrites such a shared entry, every player that references it gets
  /// silently renamed.  Callers should treat a [true] result as a warning that
  /// in-place name edits may have unintended side-effects.
  ///
  /// Returns [false] when every player pointer destination is unique — the
  /// standard layout produced by the base game and this tool.
  bool checkNamePointers() {
    final Set<int> seen = {};
    bool hasShared = false;
    for (int player = 0; player <= mMaxPlayers; player++) {
      final int fnamePtrLoc = player * _cPlayerDataLength + FirstPlayerFnamePointerLoc;
      final int lnamePtrLoc = fnamePtrLoc + 4;
      for (final int ptrLoc in [fnamePtrLoc, lnamePtrLoc]) {
        final int dest = GetPointerDestination(ptrLoc);
        if (dest < mStringTableStart || dest >= mModifiableNameSectionEnd) continue;
        if (!seen.add(dest)) hasShared = true;
      }
    }
    Logger.log(hasShared
        ? '#checkNamePointers: shared name pointers detected – '
            'SetName may overwrite names used by multiple players'
        : '#checkNamePointers: all player name pointers are unique');
    return hasShared;
  }

  static List<String> sTeamsDataOrder = [
    '49ers', 'Bears', 'Bengals', 'Bills', 'Broncos', 'Browns', 'Buccaneers', 'Cardinals',
    'Chargers', 'Chiefs', 'Colts', 'Cowboys', 'Dolphins', 'Eagles', 'Falcons', 'Giants', 'Jaguars',
    'Jets', 'Lions', 'Packers', 'Panthers', 'Patriots', 'Raiders', 'Rams', 'Ravens', 'Redskins',
    'Saints', 'Seahawks', 'Steelers', 'Texans', 'Titans', 'Vikings',
    'FreeAgents', 'DraftClass'
  ];

  static List<String> get Teams {
    return sTeamsDataOrder.sublist(0, 32);
  }

  int get MaxPlayers => mMaxPlayers;

  String GetLeaguePlayers(bool attributes, bool appearance, bool specialTeamers) {
    StringBuffer builder = StringBuffer();
    for (int i = 0; i < 32; i++) {
      builder.write(GetTeamPlayers(sTeamsDataOrder[i], attributes, appearance, specialTeamers));
    }
    return builder.toString();
  }

  String GetDraftClass(bool attributes, bool appearance) {
    int limit = FirstDraftClassPlayer + _mDraftClassSize;
    if (mSaveType == SaveType.Roster)
      limit = FirstDraftClassPlayer + 7;

    StringBuffer builder = StringBuffer();
    builder.write('\nTeam = ');
    builder.write('DraftClass');
    builder.write('    Players:');
    builder.write(_mDraftClassSize);
    builder.write('\n');

    for (int i = FirstDraftClassPlayer; i < limit; i++) {
      builder.write(GetPlayerData(i, attributes, appearance));
      builder.write('\n');
    }
    return builder.toString();
  }

  Uint8List GetTeamBytes(String team) {
    int teamIndex = GetTeamIndex(team);
    int teamPlayerPointersStart = teamIndex * _cTeamDiff + m49ersPlayerPointersStart;
    return Uint8List.fromList(GameSaveData!.sublist(teamPlayerPointersStart, teamPlayerPointersStart + _cTeamDiff));
  }

  String GetTeamPlayers(String team, bool attributes, bool appearance, bool specialTeams) {
    if (team.toLowerCase() == 'draftclass')
      return GetDraftClass(attributes, appearance);

    List<int> playerIndexes = GetPlayerIndexesForTeam(team);
    StringBuffer builder = StringBuffer();
    builder.write('\nTeam = ');
    builder.write(team);
    builder.write('    Players:');
    builder.write(playerIndexes.length);
    builder.write('\n');

    for (int i = 0; i < playerIndexes.length; i++) {
      builder.write(GetPlayerData(playerIndexes[i], attributes, appearance));
      builder.write('\n');
    }
    if (specialTeams) {
      builder.write(GetSpecialTeamDepthChart(team));
      builder.write('\n');
    }
    return builder.toString();
  }

  List<int> GetPlayerIndexesForTeam(String team) {
    List<int> retVal = [];
    int teamIndex = GetTeamIndex(team);
    int teamPlayerPointersStart = teamIndex * _cTeamDiff + m49ersPlayerPointersStart;
    if (team.toLowerCase() == 'freeagents')
      teamPlayerPointersStart = GetPointerDestination(mFreeAgentPlayersPointer);
    else if (team.toLowerCase() == 'draftclass') {
      int lastDraftClassPlayer = FirstDraftClassPlayer + _mDraftClassSize + 1;
      for (int i = FirstDraftClassPlayer; i < lastDraftClassPlayer; i++)
        retVal.add(i);
      return retVal;
    }

    int numPlayers = GetNumPlayers(team);
    int playerIndex = -1;

    try {
      for (int i = 0; i < numPlayers; i++) {
        playerIndex = GetPlayerIndexByPointer(teamPlayerPointersStart + (i * 4));
        retVal.add(playerIndex);
      }
    } catch (e) {
      StaticUtils.AddError('Error getting players for:$team Invalid pointer found. player index=$playerIndex');
    }
    return retVal;
  }

  int GetPlayerIndexByPointer(int pointerLoc) {
    int ptr = GameSaveData![pointerLoc + 3] << 24;
    ptr += GameSaveData![pointerLoc + 2] << 16;
    ptr += GameSaveData![pointerLoc + 1] << 8;
    ptr += GameSaveData![pointerLoc];
    if (ptr >= 0x80000000) ptr -= 0x100000000;
    int playerLoc = ptr + pointerLoc - 1;
    int retVal = (playerLoc - mPlayerStart) ~/ _cPlayerDataLength;
    if (retVal > mMaxPlayers)
      throw Exception('Error! Invalid player index:$retVal');
    return retVal;
  }

  String GetNumberOfPlayersOnAllTeams() {
    StringBuffer builder = StringBuffer();
    for (String team in sTeamsDataOrder) {
      builder.write(team);
      builder.write(' Count = ');
      builder.write(GetNumPlayers(team));
      builder.write('\n');
    }
    return builder.toString();
  }

  int GetNumPlayers(String team) {
    int retVal = 0;
    int index = GetTeamIndex(team);
    int loc = m49ersNumPlayersAddress + index * _cTeamDiff;
    if (team.toLowerCase() == 'freeagents') {
      loc = mFreeAgentCountLocation;
      retVal = GameSaveData![loc + 1] << 8;
    }
    retVal += GameSaveData![loc];
    return retVal;
  }

  int GetTeamIndex(String team) {
    for (int i = 0; i < sTeamsDataOrder.length; i++)
      if (sTeamsDataOrder[i].toLowerCase() == team.toLowerCase())
        return i;
    return -1;
  }

  String GetPlayerTeam(int player) {
    List<int> players;
    for (int i = 0; i < sTeamsDataOrder.length - 1; i++) {
      players = GetPlayerIndexesForTeam(sTeamsDataOrder[i]);
      for (int j = 0; j < players.length; j++) {
        if (players[j] == player)
          return sTeamsDataOrder[i];
      }
    }
    return 'DraftClass';
  }

  void AutoUpdatePBP() {
    Logger.log('#AutoUpdatePBP');
    String key, firstName, lastName, number, val;
    for (int player = 0; player < MaxPlayers; player++) {
      firstName = GetPlayerFirstName(player);
      lastName = GetPlayerLastName(player);
      number = GetAttribute(player, PlayerOffsets.JerseyNumber);
      if (number.length < 2)
        number = '#0$number';
      else
        number = '#$number';

      key = '$lastName, $firstName';
      if (DataMap.PBPMap.containsKey(key))
        val = DataMap.PBPMap[key]!;
      else if (DataMap.PBPMap.containsKey(lastName))
        val = DataMap.PBPMap[lastName]!;
      else
        val = DataMap.PBPMap[number] ?? '';
      SetAttribute(player, PlayerOffsets.PBP, val);
    }
  }

  void AutoUpdatePhoto() {
    Logger.log('#AutoUpdatePhoto');
    String key, firstName, lastName, number, val;
    for (int player = 0; player < MaxPlayers; player++) {
      firstName = GetPlayerFirstName(player);
      lastName = GetPlayerLastName(player);
      number = GetAttribute(player, PlayerOffsets.JerseyNumber);
      if (number.length < 2)
        number = '#0$number';
      else
        number = '#$number';

      key = '$lastName, $firstName';
      if (DataMap.PhotoMap.containsKey(key))
        val = DataMap.PhotoMap[key]!;
      else
        val = DataMap.PhotoMap['NoPhoto'] ?? '0000';
      SetAttribute(player, PlayerOffsets.Photo, val);
    }
  }

  void AutoUpdateYearsProFromYear(int currentYear, List<String> teams) {
    String dob = '';
    List<String> parts;
    int birthYear = 0;
    int yearsPro = 0;
    List<int>? playerPointers;

    for (int t = 0; t < teams.length; t++) {
      if (teams[t].toLowerCase() == 'draftclass') continue;
      playerPointers = GetPlayerIndexesForTeam(teams[t]);
      for (int i = 0; i < playerPointers.length; i++) {
        dob = GetAttribute(playerPointers[i], PlayerOffsets.DOB);
        parts = dob.split('/');
        if (parts.length > 2) {
          birthYear = int.tryParse(parts[2]) ?? 0;
          if (birthYear != 0) {
            yearsPro = currentYear - (birthYear + 22);
            if (yearsPro < 0) yearsPro = 0;
            SetAttribute(playerPointers[i], PlayerOffsets.YearsPro, yearsPro.toString());
          }
        }
      }
    }
    if (teams.contains('DraftClass')) {
      int end = FirstDraftClassPlayer + _mDraftClassSize + 1;
      int targetYear = currentYear - 21;
      for (int i = FirstDraftClassPlayer; i < end; i++) {
        dob = GetAttribute(i, PlayerOffsets.DOB);
        parts = dob.split('/');
        dob = '${parts[0]}/${parts[1]}/$targetYear';
        SetAttribute(i, PlayerOffsets.DOB, dob);
        SetAttribute(i, PlayerOffsets.YearsPro, '0');
      }
    }
  }

  String GetDepthCharts() {
    StringBuffer sb = StringBuffer();
    for (int i = 0; i < 32; i++) {
      sb.write('#');
      sb.write(sTeamsDataOrder[i]);
      sb.write(' DepthChart:\n');
      sb.write(GetDepthChartForTeam(sTeamsDataOrder[i]));
      sb.write('\n#Special Teams\n');
      sb.write(GetSpecialTeamDepthChart(sTeamsDataOrder[i]));
      sb.write('\n\n');
    }
    return sb.toString();
  }

  String GetDepthChartForTeam(String team) {
    if (team.toLowerCase() == 'freeagents' || team.toLowerCase() == 'draftclass')
      return '';
    List<int> playerIndexes = GetPlayerIndexesForTeam(team);
    DepthChart depthChart = DepthChart();
    for (int i = 0; i < playerIndexes.length; i++) {
      depthChart.AddPlayer(
        GetPlayerFirstName(playerIndexes[i]),
        GetPlayerLastName(playerIndexes[i]),
        GetPlayerPosition(playerIndexes[i]),
        GetHumanReadablePositionDepth(playerIndexes[i])
      );
    }
    return depthChart.toString();
  }

  int GetHumanReadablePositionDepth(int player) {
    int retVal = 0;
    int playerLocation = GetPlayerDataStart(player);
    int depthVal = GameSaveData![playerLocation + PlayerOffsets.Depth.value];

    Positions pos = GetPlayerPositionEnum(player);
    switch (pos) {
      case Positions.QB:
      case Positions.TE:
      case Positions.C:
      case Positions.FB:
      case Positions.FS:
      case Positions.K:
      case Positions.P:
      case Positions.RB:
      case Positions.SS:
        retVal = mSinglePosDepthArray.indexOf(depthVal);
        break;
      default:
        retVal = mMultiDepthArray.indexOf(depthVal);
        break;
    }
    retVal++;
    return retVal;
  }

  int GetPlayerPositionDepth(int player) {
    int playerLocation = GetPlayerDataStart(player);
    return GameSaveData![playerLocation + PlayerOffsets.Depth.value];
  }

  void SetPlayerPositionDepth(int player, int depth) {
    int playerLocation = GetPlayerDataStart(player);
    SetByte(playerLocation + PlayerOffsets.Depth.value, depth);
  }

  void AutoUpdateDepthChart() {
    Logger.log('#AutoUpdateDepthChart');
    for (int i = 0; i < 32; i++) {
      AutoUpdateDepthChartForTeam(sTeamsDataOrder[i]);
    }
    AutoUpdateSpecialteamsDepth();
  }

  List<int> mMultiDepthArray = [0x60, 0x10, 0x84, 0x34, 0xA8, 0xCC, 0x58, 0xFC];
  List<int> mSinglePosDepthArray = [0x0, 0x4, 0x8, 0x0C, 0xF];

  void AutoUpdateDepthChartForTeam(String team) {
    List<int> positions = List.filled(17, 0);
    if (team.toLowerCase() == 'freeagents' || team.toLowerCase() == 'draftclass')
      return;
    int depth = 0;
    Positions pos;
    List<int> playerIndexes = GetPlayerIndexesForTeam(team);
    for (int i = 0; i < playerIndexes.length; i++) {
      pos = GetPlayerPositionEnum(playerIndexes[i]);
      switch (pos) {
        case Positions.QB:
        case Positions.TE:
        case Positions.C:
        case Positions.FB:
        case Positions.FS:
        case Positions.K:
        case Positions.P:
        case Positions.RB:
        case Positions.SS:
          depth = positions[pos.value];
          if (depth > mSinglePosDepthArray.length - 1)
            SetPlayerPositionDepth(playerIndexes[i], mSinglePosDepthArray[mSinglePosDepthArray.length - 1]);
          else
            SetPlayerPositionDepth(playerIndexes[i], mSinglePosDepthArray[depth]);
          break;
        default:
          depth = positions[pos.value];
          if (depth > mMultiDepthArray.length - 1)
            SetPlayerPositionDepth(playerIndexes[i], mMultiDepthArray[mMultiDepthArray.length - 1]);
          else
            SetPlayerPositionDepth(playerIndexes[i], mMultiDepthArray[depth]);
          break;
      }
      positions[pos.value]++;
    }
  }

  void AutoUpdateSpecialteamsDepth() {
    for (int i = 0; i < 32; i++) {
      AutoUpdateSpecialTeams(sTeamsDataOrder[i]);
    }
  }

  void AutoUpdateSpecialTeams(String team) {
    int teamIndex = GetTeamIndex(team);
    int teamPlayerPointersStart = teamIndex * _cTeamDiff + m49ersPlayerPointersStart;
    List<int> playerIndexes = GetPlayerIndexesForTeam(team);

    int fast1 = playerIndexes.length - 1;
    int fast2 = playerIndexes.length - 2;
    int center = 0;
    int speedTest1 = 0;
    int speedTest2 = 0;
    String playerPosition = '';

    for (int i = playerIndexes.length - 1; i > 0; i--) {
      playerPosition = GetPlayerPosition(playerIndexes[i]) + ',';
      if (',WR,RB,'.contains(playerPosition)) {
        int.tryParse(GetAttribute(playerIndexes[i], PlayerOffsets.Speed)) ?? 0;
        speedTest1 = int.tryParse(GetAttribute(playerIndexes[i], PlayerOffsets.Speed)) ?? 0;
        speedTest2 = int.tryParse(GetAttribute(playerIndexes[fast1], PlayerOffsets.Speed)) ?? 0;
        if (!IsStarter(GetPlayerPositionDepth(playerIndexes[i]))) {
          if (speedTest1 > speedTest2) {
            fast2 = fast1;
            fast1 = i;
          } else if (!',WR,RB,'.contains(GetPlayerPosition(playerIndexes[fast2]) + ','))
            fast2 = i;
        }
      } else if (playerPosition == 'C,' && center == 0) {
        center = i;
      }
    }
    SetByte(teamPlayerPointersStart + SpecialTeamer.KR1.value, fast1);
    SetByte(teamPlayerPointersStart + SpecialTeamer.KR2.value, fast2);
    SetByte(teamPlayerPointersStart + SpecialTeamer.PR.value, fast1);
    SetByte(teamPlayerPointersStart + SpecialTeamer.LS.value, center);
  }

  bool IsStarter(int depth) {
    return depth == 0 || depth == 0x60 || depth == 0x10;
  }

  String GetSpecialTeamDepthChart(String team) {
    StringBuffer builder = StringBuffer();
    builder.write(GetSpecialTeamPosition(team, SpecialTeamer.KR1));
    builder.write('\r\n');
    builder.write(GetSpecialTeamPosition(team, SpecialTeamer.KR2));
    builder.write('\r\n');
    builder.write(GetSpecialTeamPosition(team, SpecialTeamer.PR));
    builder.write('\r\n');
    builder.write(GetSpecialTeamPosition(team, SpecialTeamer.LS));
    builder.write('\r\n');
    return builder.toString();
  }

  String GetSpecialTeamPosition(String team, SpecialTeamer guy) {
    int teamIndex = GetTeamIndex(team);
    int teamPlayerPointersStart = teamIndex * _cTeamDiff + m49ersPlayerPointersStart;
    List<int> playerIndexes = GetPlayerIndexesForTeam(team);
    int playerIndex = GameSaveData![teamPlayerPointersStart + guy.value];

    String pos = 'ERROR';
    int depth = 0;
    if (playerIndex < playerIndexes.length) {
      pos = GetPlayerPosition(playerIndexes[playerIndex]);
      for (int i = 0; i <= playerIndex; i++) {
        if (pos == GetPlayerPosition(playerIndexes[i]))
          depth++;
      }
    }
    return '${guy.name},$pos$depth';
  }

  void SetSpecialTeamPosition(String team, SpecialTeamer stPosition, dynamic posOrFirstName, [dynamic depthOrLastName]) {
    if (posOrFirstName is Positions) {
      // SetSpecialTeamPosition(team, stPosition, pos, depth)
      Positions pos = posOrFirstName;
      int depth = depthOrLastName as int;
      int index = -1;
      int teamIndex = GetTeamIndex(team);
      int teamPlayerPointersStart = teamIndex * _cTeamDiff + m49ersPlayerPointersStart;
      List<int> playerIndexes = GetPlayerIndexesForTeam(team);
      int testDepth = 0;
      String position = pos.name;
      for (int i = 0; i < playerIndexes.length; i++) {
        if (GetPlayerPosition(playerIndexes[i]) == position) {
          testDepth++;
          if (testDepth == depth) {
            index = i;
            break;
          }
        }
      }
      if (index > -1) {
        SetByte(teamPlayerPointersStart + stPosition.value, index);
      } else {
        throw StateError('Depth $depth at position ${pos.name} does not exist');
      }
    } else {
      // SetSpecialTeamPosition(team, stPosition, firstName, lastName)
      String firstName = posOrFirstName as String;
      String lastName = depthOrLastName as String;
      String theName = '$firstName $lastName';
      int index = -1;
      int teamIndex = GetTeamIndex(team);
      int teamPlayerPointersStart = teamIndex * _cTeamDiff + m49ersPlayerPointersStart;
      List<int> playerIndexes = GetPlayerIndexesForTeam(team);
      for (int i = 0; i < playerIndexes.length; i++) {
        if (theName == GetPlayerName(playerIndexes[i], ' ')) {
          index = i;
          break;
        }
      }
      if (index > -1) {
        SetByte(teamPlayerPointersStart + stPosition.value, index);
      } else {
        throw StateError("Error setting special teamer! '$theName' is not on the team!");
      }
    }
  }

  void SetYear(String year) {
    try {
      Year = int.parse(year);
      if (GameSaveData != null && Year > 2000 &&
          GameSaveData!.length > SchedulerHelper.FranchiseGameOneYearLocation) {
        GameSaveData![SchedulerHelper.FranchiseGameOneYearLocation] = Year - 2000;
      }
    } catch (e) {
      StaticUtils.AddError('Error Setting year to:$year');
    }
  }

  void ApplySchedule(List<String> scheduleList) {
    SchedulerHelper helper = SchedulerHelper(this);
    helper.FranchiseScheduleMode = true;
    helper.ApplySchedule(scheduleList);
  }

  String GetSchedule() {
    SchedulerHelper helper = SchedulerHelper(this);
    helper.FranchiseScheduleMode = true;
    helper.mYear = Year > 2000 ? Year - 2000 : 4;
    return helper.GetSchedule();
  }

  /// Sets date and/or time for a specific franchise game.
  /// [week] is 1-based (week 1 = first regular season week, week 18 = Wild Card).
  /// [gameOfWeek] is 1-based.
  void SetGameDateTime(int week, int gameOfWeek,
      {int? month, int? day, int? hour, int? minute}) {
    SchedulerHelper helper = SchedulerHelper(this);
    helper.FranchiseScheduleMode = true;
    helper.mYear = Year > 2000 ? Year - 2000 : 4;
    // Convert from 1-based to 0-based.
    helper.SetGameDateTime(week - 1, gameOfWeek - 1,
        month: month, day: day, hour: hour, minute: minute);
  }

  void SetByte(int loc, int b) {
    GameSaveData![loc] = b;
  }

  List<int>? mOrder;
  List<int>? get Order => mOrder;

  String? mCustomKey;

  String GetKey(bool attributes, bool appearance) {
    String retVal = '';
    if (mCustomKey != null && mCustomKey!.isNotEmpty)
      retVal = mCustomKey!;
    else
      retVal = GetDefaultKey(attributes, appearance);

    if (retVal.isNotEmpty && retVal[0] != '#')
      retVal = '#$retVal';
    return retVal;
  }

  String GetDefaultKey(bool attributes, bool appearance) {
    StringBuffer builder = StringBuffer();
    StringBuffer dummy = StringBuffer();
    int prevLength = 0;
    builder.write('#Position,fname,lname,JerseyNumber,');
    int size = 4;
    if (attributes) size += mAttributeOrder.length;
    if (appearance) size += mAppearanceOrder.length;
    mOrder = List.filled(size, 0);
    mOrder![0] = PlayerOffsets.Position.value;
    mOrder![1] = -1;
    mOrder![2] = -2;
    mOrder![3] = PlayerOffsets.JerseyNumber.value;
    int i = 4;
    if (attributes) {
      for (PlayerOffsets attr in mAttributeOrder) {
        builder.write(attr.name);
        builder.write(',');
        mOrder![i++] = attr.value;
      }
    }
    if (appearance) {
      for (AppearanceAttributes app in mAppearanceOrder) {
        prevLength = dummy.length;
        GetPlayerAppearanceAttribute(0, app, dummy);
        mOrder![i++] = app.value;
        if (dummy.length > prevLength) {
          builder.write(app.name);
          builder.write(',');
        }
      }
    }
    return builder.toString();
  }

  void SetKey(String line) {
    if (line.isNotEmpty && line.toLowerCase().startsWith('key='))
      line = line.substring(4);
    line = line.trimRight();
    if (line.endsWith(',')) line = line.substring(0, line.length - 1);
    mCustomKey = line;
    if (mCustomKey != null && mCustomKey!.isNotEmpty) {
      List<String> parts = mCustomKey!.split(',');
      mOrder = List.filled(parts.length, 0);
      for (int i = 0; i < parts.length; i++) {
        int? tmp = GetAttributeValue(parts[i]);
        if (tmp == null) {
          throw Exception('Error Setting Key');
        }
        mOrder![i] = tmp;
      }
    }
  }

  int? GetAttributeValue(String a) {
    if (a == 'fname') return -1;
    if (a == 'lname') return -2;
    try {
      AppearanceAttributes aa = AppearanceAttributes.values.firstWhere((e) => e.name == a);
      return aa.value;
    } catch (_) {}
    try {
      PlayerOffsets po = PlayerOffsets.values.firstWhere((e) => e.name == a);
      return po.value;
    } catch (_) {
      StaticUtils.AddError("Attribute '$a' is invalid");
    }
    return null;
  }

  List<AppearanceAttributes> mAppearanceOrder = [
    AppearanceAttributes.College, AppearanceAttributes.DOB, AppearanceAttributes.PBP,
    AppearanceAttributes.Photo, AppearanceAttributes.YearsPro, AppearanceAttributes.Hand,
    AppearanceAttributes.Weight, AppearanceAttributes.Height, AppearanceAttributes.BodyType,
    AppearanceAttributes.Skin, AppearanceAttributes.Face, AppearanceAttributes.Dreads,
    AppearanceAttributes.Helmet, AppearanceAttributes.FaceMask, AppearanceAttributes.Visor,
    AppearanceAttributes.EyeBlack, AppearanceAttributes.MouthPiece, AppearanceAttributes.LeftGlove,
    AppearanceAttributes.RightGlove, AppearanceAttributes.LeftWrist, AppearanceAttributes.RightWrist,
    AppearanceAttributes.LeftElbow, AppearanceAttributes.RightElbow, AppearanceAttributes.Sleeves,
    AppearanceAttributes.LeftShoe, AppearanceAttributes.RightShoe, AppearanceAttributes.NeckRoll,
    AppearanceAttributes.Turtleneck
  ];

  List<PlayerOffsets> mAttributeOrder = [
    PlayerOffsets.Speed, PlayerOffsets.Agility, PlayerOffsets.Strength, PlayerOffsets.Jumping, PlayerOffsets.Coverage,
    PlayerOffsets.PassRush, PlayerOffsets.RunCoverage, PlayerOffsets.PassBlocking, PlayerOffsets.RunBlocking, PlayerOffsets.Catch,
    PlayerOffsets.RunRoute, PlayerOffsets.BreakTackle, PlayerOffsets.HoldOntoBall, PlayerOffsets.PowerRunStyle, PlayerOffsets.PassAccuracy,
    PlayerOffsets.PassArmStrength, PlayerOffsets.PassReadCoverage, PlayerOffsets.Tackle, PlayerOffsets.KickPower, PlayerOffsets.KickAccuracy,
    PlayerOffsets.Stamina, PlayerOffsets.Durability, PlayerOffsets.Leadership, PlayerOffsets.Scramble, PlayerOffsets.Composure,
    PlayerOffsets.Consistency, PlayerOffsets.Aggressiveness
  ];

  String GetPlayerData(int player, bool attributes, bool appearance) {
    StringBuffer builder = StringBuffer();
    if (mOrder == null || mOrder!.isEmpty)
      GetKey(attributes, appearance);
    for (int i = 0; i < mOrder!.length; i++) {
      int attr = mOrder![i];
      if (attr == -1)
        builder.write(GetPlayerFirstName(player));
      else if (attr == -2)
        builder.write(GetPlayerLastName(player));
      else if (attr >= AppearanceAttributes.College.value)
        GetPlayerAppearanceAttribute(player, AppearanceAttributes.values.firstWhere((e) => e.value == attr), builder);
      else
        builder.write(GetAttribute(player, PlayerOffsets.values.firstWhere((e) => e.value == attr)));
      String s = builder.toString();
      if (s.isEmpty || s[s.length - 1] != ',')
        builder.write(',');
    }
    return builder.toString();
  }

  int GetPlayerDataStart(int player) {
    int ret = -1;
    if (player <= mMaxPlayers)
      ret = mPlayerStart + player * _cPlayerDataLength;
    return ret;
  }

  void GetPlayerAppearance(int player, StringBuffer builder) {
    for (AppearanceAttributes attr in mAppearanceOrder) {
      GetPlayerAppearanceAttribute(player, attr, builder);
    }
  }

  void SetPlayerAppearanceAttribute(int player, AppearanceAttributes attr, String strVal) {
    switch (attr) {
      case AppearanceAttributes.BodyType: SetBody(player, strVal); break;
      case AppearanceAttributes.Dreads: SetDreads(player, strVal); break;
      case AppearanceAttributes.EyeBlack: SetEyeblack(player, strVal); break;
      case AppearanceAttributes.Hand: SetHand(player, strVal); break;
      case AppearanceAttributes.Turtleneck: SetTurtleneck(player, strVal); break;
      case AppearanceAttributes.Face: SetFace(player, strVal); break;
      case AppearanceAttributes.FaceMask: SetFaceMask(player, strVal); break;
      case AppearanceAttributes.Visor: SetVisor(player, strVal); break;
      case AppearanceAttributes.Skin: SetSkin(player, strVal); break;
      case AppearanceAttributes.DOB: SetAttribute(player, PlayerOffsets.DOB, strVal); break;
      case AppearanceAttributes.Helmet: SetHelmet(player, strVal); break;
      case AppearanceAttributes.RightShoe: SetRightShoe(player, strVal); break;
      case AppearanceAttributes.LeftShoe: SetLeftShoe(player, strVal); break;
      case AppearanceAttributes.LeftGlove: SetLeftGlove(player, strVal); break;
      case AppearanceAttributes.MouthPiece: SetMouthPiece(player, strVal); break;
      case AppearanceAttributes.Sleeves: SetSleeves(player, strVal); break;
      case AppearanceAttributes.NeckRoll: SetNeckRoll(player, strVal); break;
      case AppearanceAttributes.RightGlove: SetRightGlove(player, strVal); break;
      case AppearanceAttributes.LeftWrist: SetLeftWrist(player, strVal); break;
      case AppearanceAttributes.RightWrist: SetRightWrist(player, strVal); break;
      case AppearanceAttributes.LeftElbow: SetLeftElbow(player, strVal); break;
      case AppearanceAttributes.Weight: SetAttribute(player, PlayerOffsets.Weight, strVal); break;
      case AppearanceAttributes.Height: SetAttribute(player, PlayerOffsets.Height, strVal); break;
      case AppearanceAttributes.RightElbow: SetRightElbow(player, strVal); break;
      case AppearanceAttributes.College: SetCollege(player, strVal); break;
      case AppearanceAttributes.YearsPro: SetAttribute(player, PlayerOffsets.YearsPro, strVal); break;
      case AppearanceAttributes.Photo: SetAttribute(player, PlayerOffsets.Photo, strVal); break;
      case AppearanceAttributes.PBP: SetAttribute(player, PlayerOffsets.PBP, strVal); break;
    }
  }

  void GetPlayerAppearanceAttribute(int player, AppearanceAttributes attr, StringBuffer builder) {
    switch (attr) {
      case AppearanceAttributes.BodyType: GetBody(player, builder); break;
      case AppearanceAttributes.Dreads: GetDreads(player, builder); break;
      case AppearanceAttributes.EyeBlack: GetEyeblack(player, builder); break;
      case AppearanceAttributes.Hand: GetHand(player, builder); break;
      case AppearanceAttributes.Turtleneck: GetTurtleneck(player, builder); break;
      case AppearanceAttributes.Face: GetFace(player, builder); break;
      case AppearanceAttributes.FaceMask: GetFaceMask(player, builder); break;
      case AppearanceAttributes.Visor: GetVisor(player, builder); break;
      case AppearanceAttributes.Skin: GetSkin(player, builder); break;
      case AppearanceAttributes.DOB:
        builder.write(GetAttribute(player, PlayerOffsets.DOB));
        builder.write(',');
        break;
      case AppearanceAttributes.Helmet: GetHelmet(player, builder); break;
      case AppearanceAttributes.RightShoe: GetRightShoe(player, builder); break;
      case AppearanceAttributes.LeftShoe: GetLeftShoe(player, builder); break;
      case AppearanceAttributes.LeftGlove: GetLeftGlove(player, builder); break;
      case AppearanceAttributes.MouthPiece: GetMouthPiece(player, builder); break;
      case AppearanceAttributes.Sleeves: GetSleeves(player, builder); break;
      case AppearanceAttributes.NeckRoll: GetNeckRoll(player, builder); break;
      case AppearanceAttributes.RightGlove: GetRightGlove(player, builder); break;
      case AppearanceAttributes.LeftWrist: GetLeftWrist(player, builder); break;
      case AppearanceAttributes.RightWrist: GetRightWrist(player, builder); break;
      case AppearanceAttributes.LeftElbow: GetLeftElbow(player, builder); break;
      case AppearanceAttributes.Weight:
        builder.write(GetAttribute(player, PlayerOffsets.Weight));
        builder.write(',');
        break;
      case AppearanceAttributes.Height:
        builder.write(GetAttribute(player, PlayerOffsets.Height));
        builder.write(',');
        break;
      case AppearanceAttributes.RightElbow: GetRightElbow(player, builder); break;
      case AppearanceAttributes.College:
        builder.write(GetCollege(player));
        builder.write(',');
        break;
      case AppearanceAttributes.YearsPro:
        builder.write(GetAttribute(player, PlayerOffsets.YearsPro));
        builder.write(',');
        break;
      case AppearanceAttributes.Photo:
        builder.write(GetAttribute(player, PlayerOffsets.Photo));
        builder.write(',');
        break;
      case AppearanceAttributes.PBP:
        builder.write(GetAttribute(player, PlayerOffsets.PBP));
        builder.write(',');
        break;
    }
  }

  void GetPlayerAttributes(int player, StringBuffer builder) {
    for (int i = 0; i < mAttributeOrder.length; i++) {
      builder.write(GetAttribute(player, mAttributeOrder[i]));
      builder.write(',');
    }
  }

  String GetAttribute(int player, PlayerOffsets attr) {
    String retVal = '';
    int loc = GetPlayerDataStart(player) + attr.value;
    int val = GameSaveData![loc];
    switch (attr) {
      case PlayerOffsets.Position:
        retVal = GetPlayerPosition(player);
        break;
      case PlayerOffsets.PowerRunStyle:
        // C# enum cast: undefined values stringify as the integer
        final matchingStyle = PowerRunStyle.values.where((e) => e.value == val);
        retVal = matchingStyle.isEmpty ? val.toString() : matchingStyle.first.name;
        break;
      case PlayerOffsets.Face:
        // C# enum cast: out-of-range values stringify as the integer
        retVal = val < Face.values.length ? Face.values[val].name : val.toString();
        break;
      case PlayerOffsets.JerseyNumber:
        val = GameSaveData![loc + 1] << 5 & 0x60;
        val += GameSaveData![loc] >> 3 & 0x1f;
        retVal = val.toString();
        break;
      case PlayerOffsets.DOB:
        int year = (GameSaveData![loc + 2] & 0x0f) << 3;
        year += GameSaveData![loc + 1] >> 5;
        int day = GameSaveData![loc + 1] & 0x1f;
        int month = GameSaveData![loc] >> 4;
        if (year > 54)
          year += 1900;
        else
          year += 2000;
        retVal = '$month/$day/$year';
        break;
      case PlayerOffsets.Weight:
        val += 150;
        retVal = val.toString();
        break;
      case PlayerOffsets.Height:
        int feet = val ~/ 12;
        int inches = val % 12;
        retVal = "$feet'$inches\"";
        break;
      case PlayerOffsets.College:
        retVal = GetCollege(player);
        break;
      case PlayerOffsets.PBP:
      case PlayerOffsets.Photo:
        val = GameSaveData![loc + 1] << 8;
        val += GameSaveData![loc];
        retVal = '$val';
        switch (retVal.length) {
          case 3: retVal = '0$retVal'; break;
          case 2: retVal = '00$retVal'; break;
          case 1: retVal = '000$retVal'; break;
        }
        break;
      default:
        retVal = '$val';
        break;
    }
    return retVal;
  }

  final RegExp mDobRegex = RegExp(r'([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})');

  void SetAttribute(int player, PlayerOffsets attr, String stringVal) {
    int loc = GetPlayerDataStart(player) + attr.value;
    int val = 0;
    int v1, v2, v3;
    switch (attr) {
      case PlayerOffsets.PowerRunStyle:
        PowerRunStyle style = PowerRunStyle.values.firstWhere((e) => e.name == stringVal);
        SetByte(loc, style.value);
        break;
      case PlayerOffsets.Face:
        final faceNumeric = int.tryParse(stringVal);
        SetByte(loc, faceNumeric ?? Face.values.firstWhere((e) => e.name == stringVal).index);
        break;
      case PlayerOffsets.JerseyNumber:
        val = int.parse(stringVal);
        v1 = GameSaveData![loc] & 7;
        v2 = GameSaveData![loc + 1] & 0xfc;
        v2 += val >> 5;
        v1 += (val & 0x1f) << 3;
        SetByte(loc, v1);
        SetByte(loc + 1, v2);
        break;
      case PlayerOffsets.DOB:
        RegExpMatch? m = mDobRegex.firstMatch(stringVal);
        if (m != null) {
          int month = int.parse(m.group(1)!);
          int day = int.parse(m.group(2)!);
          int year = int.parse(m.group(3)!);

          if (year < 1954) year = 1954;
          else if (year > 2050) year = 2050;

          if (year > 2000) year -= 2000;
          else if (year > 1900) year -= 1900;

          v1 = (GameSaveData![loc] & 0x0f) + (month << 4);
          v2 = day;
          v2 += ((year & 7) << 5);
          v3 = GameSaveData![loc + 2] & 0xf0;
          v3 += (year >> 3);
          SetByte(loc, v1);
          SetByte(loc + 1, v2);
          SetByte(loc + 2, v3);
        } else {
          Logger.log("#Note: DOB format = 'dd/mm/yyyy'");
          throw FormatException("Error! DOB incorrectly formatted '$stringVal'");
        }
        break;
      case PlayerOffsets.Weight:
        val = int.parse(stringVal);
        val -= 150;
        SetByte(loc, val);
        break;
      case PlayerOffsets.Height:
        val = GetInches(stringVal);
        SetByte(loc, val);
        break;
      case PlayerOffsets.College:
        SetCollege(player, stringVal);
        break;
      case PlayerOffsets.Position:
        Positions pos = Positions.values.firstWhere((e) => e.name == stringVal);
        SetByte(loc, pos.value);
        break;
      case PlayerOffsets.PBP:
      case PlayerOffsets.Photo:
        val = int.parse(stringVal);
        v1 = val & 0xff;
        v2 = val >> 8;
        SetByte(loc, v1);
        SetByte(loc + 1, v2);
        break;
      default:
        val = int.parse(stringVal);
        SetByte(loc, val);
        break;
    }
  }

  bool SetPlayerFirstName(int player, String firstName, bool useExistingName) {
    return SetPlayerNameText(player, firstName, false, useExistingName);
  }

  bool SetPlayerLastName(int player, String lastName, bool useExistingName) {
    return SetPlayerNameText(player, lastName, true, useExistingName);
  }

  bool SetPlayerNameText(int player, String name, bool isLastName, bool useExistingName) {
    bool retVal = true;
    int ptrLoc1 = player * _cPlayerDataLength + FirstPlayerFnamePointerLoc;
    if (isLastName) ptrLoc1 += 4;
    if (useExistingName) {
      List<int> locations = StaticUtils.FindStringInFile(name, GameSaveData!, mStringTableStart, mStringTableEnd, true);
      if (locations.isEmpty) {
        retVal = false;
      } else {
        int newPtrVal = locations[0] - ptrLoc1 + 1;
        SetByte(ptrLoc1, 0xff & newPtrVal);
        SetByte(ptrLoc1 + 1, 0xff & (newPtrVal >> 8));
        SetByte(ptrLoc1 + 2, 0xff & (newPtrVal >> 16));
      }
    } else {
      SetName(name, ptrLoc1);
    }
    return retVal;
  }

  void SetName(String name, int ptrLoc) {
    int stringLoc = GetPointerDestination(ptrLoc);

    // BUG FIX 4: Reject pointers that resolve outside the modifiable name
    // section.  Without this guard, ShiftDataDown/Up would start from an
    // out-of-bounds address and overwrite neighbouring file sections (boundary
    // overwrite).  The ensuing AdjustPlayerNamePointers call would then corrupt
    // all valid name pointers using the wrong shift origin.
    if (stringLoc < mStringTableStart || stringLoc >= mModifiableNameSectionEnd) {
      final msg = 'SetName: skipping – pointer at 0x${ptrLoc.toRadixString(16)} '
          'resolves to 0x${stringLoc.toRadixString(16)}, outside modifiable '
          'name range 0x${mStringTableStart.toRadixString(16)}–'
          '0x${mModifiableNameSectionEnd.toRadixString(16)}';
      Logger.log('#$msg');
      StaticUtils.AddError(msg);
      return;
    }

    String prevName = GetName(ptrLoc);
    if (prevName != name) {
      int diff = 2 * (name.length - prevName.length);

      // Overflow guard: reject growth that would push real data past the section
      // boundary.  ShiftDataDown is bounded at mModifiableNameSectionEnd, so
      // any non-zero bytes in the last `diff` bytes would be silently discarded
      // and the null terminator would be written past the boundary.
      if (diff > 0) {
        bool hasRoom = true;
        for (int i = mModifiableNameSectionEnd - diff;
            i < mModifiableNameSectionEnd;
            i++) {
          if (GameSaveData![i] != 0) { hasRoom = false; break; }
        }
        if (!hasRoom) {
          StaticUtils.AddError(
              'SetName: not enough space in player name section '
              '(need $diff more bytes). String not changed.');
          return;
        }
      }

      if (diff > 0)
        ShiftDataDown(stringLoc, diff, mModifiableNameSectionEnd);
      else if (diff < 0)
        ShiftDataUp(stringLoc, -1 * diff, mModifiableNameSectionEnd);

      AdjustPlayerNamePointers(stringLoc + 2 * prevName.length, diff);
      // BUG FIX 3: also slide any college-entry name pointers that were shifted.
      _adjustCollegeEntryPointers(stringLoc + 2 * prevName.length, diff);

      for (int i = 0; i < name.length; i++) {
        SetByte(stringLoc, name.codeUnitAt(i));
        SetByte(stringLoc + 1, 0);
        stringLoc += 2;
      }
      SetByte(stringLoc, 0);
      SetByte(stringLoc + 1, 0);
    }
  }

  bool CheckNameExists(String name) {
    List<int> locations = StaticUtils.FindStringInFile(name, GameSaveData!, mStringTableStart, mStringTableEnd, true);
    return locations.isNotEmpty;
  }

  bool SetPlayerField(int player, String fieldName, String val) {
    bool retVal = false;
    if (fieldName.toLowerCase() == 'firstname' || fieldName.toLowerCase() == 'fname')
      retVal = SetPlayerFirstName(player, val, false);
    else if (fieldName.toLowerCase() == 'lastname' || fieldName.toLowerCase() == 'lname')
      retVal = SetPlayerLastName(player, val, false);
    else if (AppearanceAttributes.values.any((e) => e.name.toLowerCase() == fieldName.toLowerCase())) {
      AppearanceAttributes aa = AppearanceAttributes.values.firstWhere((e) => e.name.toLowerCase() == fieldName.toLowerCase());
      if (aa != AppearanceAttributes.College)
        val = val.replaceAll(' ', '');
      SetPlayerAppearanceAttribute(player, aa, val);
      retVal = true;
    } else if (PlayerOffsets.values.any((e) => e.name.toLowerCase() == fieldName.toLowerCase())) {
      PlayerOffsets po = PlayerOffsets.values.firstWhere((e) => e.name.toLowerCase() == fieldName.toLowerCase());
      SetAttribute(player, po, val);
    }
    return retVal;
  }

  String GetPlayerField(int player, String fieldName) {
    String retVal = '';
    if (fieldName.toLowerCase() == 'firstname' || fieldName.toLowerCase() == 'fname')
      retVal = GetPlayerFirstName(player);
    else if (fieldName.toLowerCase() == 'lastname' || fieldName.toLowerCase() == 'lname')
      retVal = GetPlayerLastName(player);
    else if (AppearanceAttributes.values.any((e) => e.name.toLowerCase() == fieldName.toLowerCase())) {
      AppearanceAttributes aa = AppearanceAttributes.values.firstWhere((e) => e.name.toLowerCase() == fieldName.toLowerCase());
      StringBuffer sb = StringBuffer();
      GetPlayerAppearanceAttribute(player, aa, sb);
      String s = sb.toString();
      retVal = s.endsWith(',') ? s.substring(0, s.length - 1) : s;
    } else if (PlayerOffsets.values.any((e) => e.name.toLowerCase() == fieldName.toLowerCase())) {
      PlayerOffsets po = PlayerOffsets.values.firstWhere((e) => e.name.toLowerCase() == fieldName.toLowerCase());
      retVal = GetAttribute(player, po);
    }
    return retVal;
  }

  void ShiftDataDown(int startIndex, int amount, int dataEnd) {
    for (int i = dataEnd - 1; i > startIndex; i--) {
      SetByte(i, GameSaveData![i - amount]);
    }
  }

  void ShiftDataUp(int startIndex, int amount, int dataEnd) {
    for (int i = startIndex; i < dataEnd - amount; i++) {
      SetByte(i, GameSaveData![i + amount]);
    }
    // Zero the vacated tail so freed slack is clean and guards work correctly.
    for (int i = dataEnd - amount; i < dataEnd; i++) {
      SetByte(i, 0);
    }
  }

  String GetPlayerName(int player, String sepChar) {
    String retVal = '!!!!!!!!INVALID!!!!!!!!!!!!';
    if (player > -1 && player <= mMaxPlayers) {
      int ptrLoc = player * _cPlayerDataLength + FirstPlayerFnamePointerLoc;
      retVal = GetName(ptrLoc) + sepChar + GetName(ptrLoc + 4);
    }
    return retVal;
  }

  String GetPlayerFirstName(int player) {
    String retVal = '!!!!!!!!INVALID!!!!!!!!!!!!';
    if (player > -1 && player <= mMaxPlayers) {
      int ptrLoc = player * _cPlayerDataLength + FirstPlayerFnamePointerLoc;
      retVal = GetName(ptrLoc);
    }
    return retVal;
  }

  String GetPlayerLastName(int player) {
    String retVal = '!!!!!!!!INVALID!!!!!!!!!!!!';
    if (player > -1 && player <= mMaxPlayers) {
      int ptrLoc = player * _cPlayerDataLength + FirstPlayerFnamePointerLoc;
      retVal = GetName(ptrLoc + 4);
    }
    return retVal;
  }

  String GetPlayerCollege(int player) => GetCollege(player);

  String GetName(int namePointerLoc) {
    int dataLocation = GetPointerDestination(namePointerLoc);
    return GetString(dataLocation);
  }

  int GetPointerDestination(int pointerLoc) {
    int pointer = GameSaveData![pointerLoc + 3] << 24;
    pointer += GameSaveData![pointerLoc + 2] << 16;
    pointer += GameSaveData![pointerLoc + 1] << 8;
    pointer += GameSaveData![pointerLoc];
    if (pointer >= 0x80000000) pointer -= 0x100000000;
    int dataLocation = pointerLoc + pointer - 1;
    return dataLocation;
  }

  String GetString(int loc) {
    StringBuffer builder = StringBuffer();
    for (int i = loc; i < loc + 99; i += 2) {
      if (GameSaveData![i] == 0) break;
      builder.writeCharCode(GameSaveData![i]);
    }
    return builder.toString();
  }

  void SetCoachString(String name, int ptrLoc) {
    String prevName = GetName(ptrLoc);
    if (prevName != name) {
      int diff = 2 * (name.length - prevName.length);
      int stringLoc = GetPointerDestination(ptrLoc);

      int coachStringEnd = GetPointerDestination(GetPointerDestination(GetCoachPointer(0))) + mCoachStringSectionLength;

      // Issue D fix: ShiftDataDown discards the last `diff` bytes of the
      // section. Reject the write if those bytes contain real data (non-zero),
      // which would indicate the section is full and data would be lost.
      if (diff > 0) {
        bool hasRoom = true;
        for (int i = coachStringEnd - diff; i < coachStringEnd; i++) {
          if (GameSaveData![i] != 0) { hasRoom = false; break; }
        }
        if (!hasRoom) {
          StaticUtils.AddError(
              'SetCoachString: not enough space in coach string section '
              '(need $diff more bytes). String not changed.');
          return;
        }
      }

      if (diff > 0)
        ShiftDataDown(stringLoc, diff, coachStringEnd);
      else if (diff < 0)
        ShiftDataUp(stringLoc, -1 * diff, coachStringEnd);

      AdjustCoachStringPointers(stringLoc + 2 * prevName.length, diff);

      for (int i = 0; i < name.length; i++) {
        SetByte(stringLoc, name.codeUnitAt(i));
        SetByte(stringLoc + 1, 0);
        stringLoc += 2;
      }
      SetByte(stringLoc, 0);
      SetByte(stringLoc + 1, 0);
    }
  }

  void AdjustCoachStringPointers(int locationOfChange, int difference) {
    int firstNamePtrLoc = 0;
    int lastNamePtrLoc = 0;
    int info1StringPtrLoc = 0;
    int info2StringPtrLoc = 0;
    int info3StringPtrLoc = 0;
    int loc = 0;

    int coachStringEnd = GetPointerDestination(GetPointerDestination(GetCoachPointer(0))) + mCoachStringSectionLength;

    for (int coach = 0; coach < 32; coach++) {
      firstNamePtrLoc = GetPointerDestination(GetCoachPointer(coach));
      lastNamePtrLoc = firstNamePtrLoc + CoachOffsets.LastName.value;
      info1StringPtrLoc = firstNamePtrLoc + CoachOffsets.Info1.value;
      info2StringPtrLoc = firstNamePtrLoc + CoachOffsets.Info2.value;
      info3StringPtrLoc = firstNamePtrLoc + CoachOffsets.Info3.value;

      loc = GetPointerDestination(firstNamePtrLoc);
      if (loc < coachStringEnd && loc >= locationOfChange)
        AdjustPointer(firstNamePtrLoc, difference);

      loc = GetPointerDestination(lastNamePtrLoc);
      if (loc < coachStringEnd && loc >= locationOfChange)
        AdjustPointer(lastNamePtrLoc, difference);

      loc = GetPointerDestination(info1StringPtrLoc);
      if (loc < coachStringEnd && loc >= locationOfChange)
        AdjustPointer(info1StringPtrLoc, difference);

      loc = GetPointerDestination(info2StringPtrLoc);
      if (loc < coachStringEnd && loc >= locationOfChange)
        AdjustPointer(info2StringPtrLoc, difference);

      loc = GetPointerDestination(info3StringPtrLoc);
      if (loc < coachStringEnd && loc >= locationOfChange)
        AdjustPointer(info3StringPtrLoc, difference);
    }
  }

  void AdjustPlayerNamePointers(int locationOfChange, int difference) {
    int firstNamePtrLoc = 0;
    int lastNamePtrLoc = 0;
    int loc = 0;
    for (int player = 0; player <= mMaxPlayers; player++) {
      firstNamePtrLoc = player * _cPlayerDataLength + FirstPlayerFnamePointerLoc;
      lastNamePtrLoc = firstNamePtrLoc + 4;

      loc = GetPointerDestination(firstNamePtrLoc);
      if (loc < mModifiableNameSectionEnd && loc >= locationOfChange)
        AdjustPointer(firstNamePtrLoc, difference);

      loc = GetPointerDestination(lastNamePtrLoc);
      if (loc < mModifiableNameSectionEnd && loc >= locationOfChange)
        AdjustPointer(lastNamePtrLoc, difference);
    }
  }

  // BUG FIX 3: When SetName shifts bytes in the string table (via ShiftDataDown/Up),
  // player fname/lname pointers are updated by AdjustPlayerNamePointers, but the
  // college-entry table (~0xA830–0xAFA7) also holds relative pointers into the
  // string table for college name strings.  Those pointers were never adjusted,
  // causing GetCollege() to return stale (wrong) names after any name-length change.
  //
  // This helper adjusts the name pointer inside every college entry that points
  // to a location at or after [locationOfChange] in the string table.
  // [Colleges.values] gives the absolute file offset of each 8-byte college entry;
  // the first 4 bytes of that entry are a relative pointer to the college name string.
  void _adjustCollegeEntryPointers(int locationOfChange, int difference) {
    for (int entryLoc in Colleges.values) {
      int nameLoc = GetPointerDestination(entryLoc);
      if (nameLoc >= locationOfChange && nameLoc < mModifiableNameSectionEnd)
        AdjustPointer(entryLoc, difference);
    }
  }

  void AdjustPointer(int namePointerLoc, int change) {
    // BUG FIX 2: The original code read only bytes 0–2 (24 bits) and wrote
    // them back, leaving byte 3 stale.  GetPointerDestination reads all four
    // bytes as a signed 32-bit integer, so any carry out of byte 2 would make
    // the recovered destination wildly wrong on the next read.  The fix mirrors
    // the exact same 4-byte signed-integer scheme used by GetPointerDestination.
    int pointer = GameSaveData![namePointerLoc + 3] << 24;
    pointer += GameSaveData![namePointerLoc + 2] << 16;
    pointer += GameSaveData![namePointerLoc + 1] << 8;
    pointer += GameSaveData![namePointerLoc];
    // Sign-extend from 32-bit to Dart's 64-bit int (same logic as GetPointerDestination).
    if (pointer >= 0x80000000) pointer -= 0x100000000;

    pointer += change;

    // Write all four bytes back so the stored pointer stays consistent with
    // the 32-bit signed format that GetPointerDestination expects.
    SetByte(namePointerLoc,     pointer & 0xff);
    SetByte(namePointerLoc + 1, (pointer >> 8)  & 0xff);
    SetByte(namePointerLoc + 2, (pointer >> 16) & 0xff);
    SetByte(namePointerLoc + 3, (pointer >> 24) & 0xff);
  }

  Uint8List GetPlayerBytes(int player) {
    int loc = GetPlayerDataStart(player);
    return Uint8List.fromList(GameSaveData!.sublist(loc, loc + 0x54));
  }

  Uint8List? GetPlayerBytesByName(String position, String firstName, String lastName) {
    List<int> players = FindPlayer(position, firstName, lastName);
    if (players.isNotEmpty) {
      return GetPlayerBytes(players[0]);
    }
    return null;
  }

  int GetInches(String stringVal) {
    int inches = 0;
    if (stringVal.length == 3 && stringVal[2] == '"') {
      inches = int.tryParse(stringVal.substring(0, 2)) ?? 0;
      return inches;
    }
    if (stringVal[0] == '"' && stringVal[stringVal.length - 1] == '"')
      stringVal = stringVal.substring(1, stringVal.length - 2);
    int feet = stringVal.codeUnitAt(0) - 0x30;
    stringVal = stringVal.replaceAll('"', '');
    inches = int.tryParse(stringVal.substring(2)) ?? 0;
    inches += feet * 12;
    return inches;
  }

  String GetPlayerPosition(int player) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Position.value;
    Positions pos = Positions.values.firstWhere((e) => e.value == GameSaveData![loc]);
    return pos.name;
  }

  Positions GetPlayerPositionEnum(int player) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Position.value;
    return Positions.values.firstWhere((e) => e.value == GameSaveData![loc]);
  }

  void GetFaceMask(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.FaceMask.value;
    int b = GameSaveData![loc];
    b = (b & 0x7f) >> 2;
    FaceMask ret = FaceMask.values[b];
    builder.write(ret.name);
    builder.write(',');
  }

  void SetFaceMask(int player, String val) {
    val = val.replaceAll('Type', 'FaceMask');
    int loc = GetPlayerDataStart(player) + PlayerOffsets.FaceMask.value;
    FaceMask ret = FaceMask.values.firstWhere((e) => e.name == val);
    int dude = ret.index;
    dude = dude << 2;
    int b = GameSaveData![loc];
    b &= 0x83;
    b += dude;
    SetByte(loc, b);
  }

  void GetFace(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Face.value;
    int b = GameSaveData![loc];
    b = b >> 1;
    // C# allows casting any int to an enum; out-of-range values stringify as the integer
    if (b < Face.values.length)
      builder.write(Face.values[b].name);
    else
      builder.write(b);
    builder.write(',');
  }

  void SetFace(int player, String val) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Face.value;
    final numeric = int.tryParse(val);
    int dude = numeric ?? Face.values.firstWhere((e) => e.name == val).index;
    int b = GameSaveData![loc];
    b &= 0x01;
    b += dude << 1;
    SetByte(loc, b);
  }

  void GetTurtleneck(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Turtleneck_Body_EyeBlack_Hand_Dreads.value;
    int b = GameSaveData![loc];
    b &= 0x60;
    b = b >> 5;
    Turtleneck ret = Turtleneck.values[b];
    builder.write(ret.name);
    builder.write(',');
  }

  void SetTurtleneck(int player, String val) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Turtleneck_Body_EyeBlack_Hand_Dreads.value;
    Turtleneck ret = Turtleneck.values.firstWhere((e) => e.name == val);
    int dude = ret.index;
    dude = dude << 5;
    int b = GameSaveData![loc];
    b &= 0x9F;
    b += dude;
    SetByte(loc, b);
  }

  void GetBody(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Turtleneck_Body_EyeBlack_Hand_Dreads.value;
    int b = GameSaveData![loc];
    b &= 0x18;
    b = b >> 3;
    Body ret = Body.values[b];
    builder.write(ret.name);
    builder.write(',');
  }

  void SetBody(int player, String val) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Turtleneck_Body_EyeBlack_Hand_Dreads.value;
    Body ret = Body.values.firstWhere((e) => e.name == val);
    int dude = ret.index;
    dude = dude << 3;
    int b = GameSaveData![loc];
    b &= 0xe7;
    b += dude;
    SetByte(loc, b);
  }

  void GetEyeblack(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Turtleneck_Body_EyeBlack_Hand_Dreads.value;
    int b = GameSaveData![loc];
    b &= 0x4;
    b = b >> 2;
    YesNo ret = YesNo.values[b];
    builder.write(ret.name);
    builder.write(',');
  }

  void SetEyeblack(int player, String val) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Turtleneck_Body_EyeBlack_Hand_Dreads.value;
    YesNo ret = YesNo.values.firstWhere((e) => e.name == val);
    int dude = ret.index;
    dude = dude << 2;
    int b = GameSaveData![loc];
    b &= 0xfb;
    b += dude;
    SetByte(loc, b);
  }

  void GetHand(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Turtleneck_Body_EyeBlack_Hand_Dreads.value;
    int b = GameSaveData![loc];
    b &= 0x2;
    b = b >> 1;
    Hand ret = Hand.values[b];
    builder.write(ret.name);
    builder.write(',');
  }

  void SetHand(int player, String val) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Turtleneck_Body_EyeBlack_Hand_Dreads.value;
    Hand ret = Hand.values.firstWhere((e) => e.name == val);
    int dude = ret.index;
    dude = dude << 1;
    int b = GameSaveData![loc];
    b &= 0xfd;
    b += dude;
    SetByte(loc, b);
  }

  void GetDreads(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Turtleneck_Body_EyeBlack_Hand_Dreads.value;
    int b = GameSaveData![loc];
    b &= 0x1;
    YesNo ret = YesNo.values[b];
    builder.write(ret.name);
    builder.write(',');
  }

  void SetDreads(int player, String val) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Turtleneck_Body_EyeBlack_Hand_Dreads.value;
    YesNo ret = YesNo.values.firstWhere((e) => e.name == val);
    int dude = ret.index;
    int b = GameSaveData![loc];
    b &= 0xfe;
    b += dude;
    SetByte(loc, b);
  }

  void GetVisor(int player, StringBuffer builder) {
    int loc1 = GetPlayerDataStart(player) + PlayerOffsets.FaceMask.value;
    int loc2 = GetPlayerDataStart(player) + PlayerOffsets.Face.value;
    int fm = GameSaveData![loc1] & 0x80;
    int f = GameSaveData![loc2] & 0x01;
    Visor ret = Visor.None;
    if (fm > 0)
      ret = Visor.Clear;
    else if (f > 0)
      ret = Visor.Dark;
    builder.write(ret.name);
    builder.write(',');
  }

  void SetVisor(int player, String val) {
    int loc1 = GetPlayerDataStart(player) + PlayerOffsets.FaceMask.value;
    int loc2 = GetPlayerDataStart(player) + PlayerOffsets.Face.value;
    Visor ret = Visor.values.firstWhere((e) => e.name == val);

    int b1 = GameSaveData![loc1] & 0x7f;
    int b2 = GameSaveData![loc2] & 0xfe;

    switch (ret) {
      case Visor.Clear: b1 += 0x80; break;
      case Visor.Dark: b2 += 1; break;
      default: break;
    }
    SetByte(loc1, b1);
    SetByte(loc2, b2);
  }

  void GetSkin(int player, StringBuffer builder) {
    int loc1 = GetPlayerDataStart(player) + PlayerOffsets.DOB.value;
    int loc2 = GetPlayerDataStart(player) - 1 + PlayerOffsets.DOB.value;
    int sk = (GameSaveData![loc1] & 0xF) << 1;
    sk += GameSaveData![loc2] >> 7;
    Skin ret = Skin.values[sk];
    builder.write(ret.name);
    builder.write(',');
  }

  void SetSkin(int player, String val) {
    int loc1 = GetPlayerDataStart(player) + PlayerOffsets.DOB.value;
    int loc2 = GetPlayerDataStart(player) - 1 + PlayerOffsets.DOB.value;
    Skin sk = Skin.values.firstWhere((e) => e.name == val);
    int dude = sk.index;
    int b1 = GameSaveData![loc1] & 0xf0;
    int b2 = GameSaveData![loc2] & 0x7f;
    b1 += dude >> 1;
    b2 += (dude & 1) << 7;
    SetByte(loc1, b1);
    SetByte(loc2, b2);
  }

  void GetHelmet(int player, StringBuffer builder) {
    Helmet retVal = Helmet.Standard;
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Helmet_LeftShoe_RightShoe.value;
    int val = GameSaveData![loc] & 0x40;
    if (val > 0) retVal = Helmet.Revolution;
    builder.write(retVal.name);
    builder.write(',');
  }

  void SetHelmet(int player, String helmet) {
    Helmet h = Helmet.values.firstWhere((e) => e.name == helmet);
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Helmet_LeftShoe_RightShoe.value;
    int val = GameSaveData![loc] & 0xBF;
    val += h.index << 6;
    SetByte(loc, val);
  }

  void GetLeftShoe(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Helmet_LeftShoe_RightShoe.value;
    int val = GameSaveData![loc] & 0x7;
    Shoe retVal = Shoe.values[val];
    builder.write(retVal.name);
    builder.write(',');
  }

  void SetLeftShoe(int player, String shoe) {
    shoe = shoe.replaceAll('Style', 'Shoe');
    Shoe h = Shoe.values.firstWhere((e) => e.name == shoe);
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Helmet_LeftShoe_RightShoe.value;
    int val = GameSaveData![loc] & 0xf8;
    val += h.index;
    SetByte(loc, val);
  }

  void GetRightShoe(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Helmet_LeftShoe_RightShoe.value;
    int val = GameSaveData![loc] & 0x38;
    val = val >> 3;
    Shoe retVal = Shoe.values[val];
    builder.write(retVal.name);
    builder.write(',');
  }

  void SetRightShoe(int player, String shoe) {
    shoe = shoe.replaceAll('Style', 'Shoe');
    Shoe h = Shoe.values.firstWhere((e) => e.name == shoe);
    int loc = GetPlayerDataStart(player) + PlayerOffsets.Helmet_LeftShoe_RightShoe.value;
    int val = GameSaveData![loc] & 0xc7;
    val += (h.index << 3);
    SetByte(loc, val);
  }

  void GetMouthPiece(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.MouthPiece_LeftGlove_Sleeves_NeckRoll.value;
    int val = (GameSaveData![loc] & 0x20) >> 5;
    YesNo retVal = YesNo.values[val];
    builder.write(retVal.name);
    builder.write(',');
  }

  void SetMouthPiece(int player, String piece) {
    YesNo h = YesNo.values.firstWhere((e) => e.name == piece);
    int loc = GetPlayerDataStart(player) + PlayerOffsets.MouthPiece_LeftGlove_Sleeves_NeckRoll.value;
    int val = GameSaveData![loc] & 0xdf;
    val |= (h.index << 5);
    SetByte(loc, val);
  }

  void GetLeftGlove(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.MouthPiece_LeftGlove_Sleeves_NeckRoll.value;
    int val = (GameSaveData![loc] & 0xC0) >> 6;
    val += ((GameSaveData![loc + 1] & 0x03) << 2);
    Glove retVal = Glove.values[val];
    builder.write(retVal.name);
    builder.write(',');
  }

  void SetLeftGlove(int player, String glove) {
    Glove g = Glove.values.firstWhere((e) => e.name == glove);
    int loc = GetPlayerDataStart(player) + PlayerOffsets.MouthPiece_LeftGlove_Sleeves_NeckRoll.value;
    int val1 = GameSaveData![loc] & 0x3f;
    int val2 = GameSaveData![loc + 1] & 0xfc;
    val1 += (g.index & 3) << 6;
    val2 += (g.index >> 2);
    SetByte(loc, val1);
    SetByte(loc + 1, val2);
  }

  void GetRightGlove(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.RightGlove_LeftWrist.value;
    int val = (GameSaveData![loc] & 0x3c) >> 2;
    Glove retVal = Glove.values[val];
    builder.write(retVal.name);
    builder.write(',');
  }

  void SetRightGlove(int player, String glove) {
    Glove g = Glove.values.firstWhere((e) => e.name == glove);
    int loc = GetPlayerDataStart(player) + PlayerOffsets.RightGlove_LeftWrist.value;
    int val = GameSaveData![loc];
    val = (val & 0xc3) + (g.index << 2);
    SetByte(loc, val);
  }

  void GetSleeves(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.MouthPiece_LeftGlove_Sleeves_NeckRoll.value;
    int val = GameSaveData![loc] & 3;
    Sleeves retVal = Sleeves.values[val];
    builder.write(retVal.name);
    builder.write(',');
  }

  void SetSleeves(int player, String sleeve) {
    Sleeves s = Sleeves.values.firstWhere((e) => e.name == sleeve);
    int loc = GetPlayerDataStart(player) + PlayerOffsets.MouthPiece_LeftGlove_Sleeves_NeckRoll.value;
    int val = GameSaveData![loc] & 0xfc;
    val += s.index;
    SetByte(loc, val);
  }

  void GetNeckRoll(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.MouthPiece_LeftGlove_Sleeves_NeckRoll.value;
    int val = (GameSaveData![loc] & 0x1c) >> 2;
    NeckRoll retVal = NeckRoll.values[val];
    builder.write(retVal.name);
    builder.write(',');
  }

  void SetNeckRoll(int player, String roll) {
    NeckRoll s = NeckRoll.values.firstWhere((e) => e.name == roll);
    int loc = GetPlayerDataStart(player) + PlayerOffsets.MouthPiece_LeftGlove_Sleeves_NeckRoll.value;
    int val = GameSaveData![loc] & 0xe3;
    val += (s.index << 2);
    SetByte(loc, val);
  }

  void GetLeftWrist(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.RightGlove_LeftWrist.value;
    int val = ((GameSaveData![loc + 1] << 8) + GameSaveData![loc]) >> 6;
    val &= 0xf;
    Wrist retVal = Wrist.values[val];
    builder.write(retVal.name);
    builder.write(',');
  }

  void SetLeftWrist(int player, String w) {
    Wrist s = Wrist.values.firstWhere((e) => e.name == w);
    int val = s.index;
    int loc = GetPlayerDataStart(player) + PlayerOffsets.RightGlove_LeftWrist.value;
    int b1 = GameSaveData![loc] & 0x3f;
    int b2 = GameSaveData![loc + 1] & 0xfc;
    b1 += (0x3 & val) << 6;
    b2 += val >> 2;
    SetByte(loc, b1);
    SetByte(loc + 1, b2);
  }

  void GetRightWrist(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.RightWrist_LeftElbow.value;
    int val = (GameSaveData![loc] & 0x3c) >> 2;
    Wrist retVal = Wrist.values[val];
    builder.write(retVal.name);
    builder.write(',');
  }

  void SetRightWrist(int player, String w) {
    Wrist s = Wrist.values.firstWhere((e) => e.name == w);
    int loc = GetPlayerDataStart(player) + PlayerOffsets.RightWrist_LeftElbow.value;
    int val = GameSaveData![loc] & 0xc3;
    val += (s.index << 2);
    SetByte(loc, val);
  }

  void GetLeftElbow(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.RightWrist_LeftElbow.value;
    int val = ((GameSaveData![loc + 1] << 8) + GameSaveData![loc]) & 0x3c0;
    val = val >> 6;
    Elbow retVal = Elbow.values[val];
    builder.write(retVal.name);
    builder.write(',');
  }

  void SetLeftElbow(int player, String w) {
    Elbow s = Elbow.values.firstWhere((e) => e.name == w);
    int loc = GetPlayerDataStart(player) + PlayerOffsets.RightWrist_LeftElbow.value;
    int val1 = (GameSaveData![loc] & 0x3f) + ((s.index & 3) << 6);
    int val2 = (GameSaveData![loc + 1] & 0xfc) + ((s.index & 0xfc) >> 2);
    SetByte(loc, val1);
    SetByte(loc + 1, val2);
  }

  void GetRightElbow(int player, StringBuffer builder) {
    int loc = GetPlayerDataStart(player) + PlayerOffsets.RightElbow.value;
    int val = (GameSaveData![loc] & 0x3c) >> 2;
    Elbow retVal = Elbow.values[val];
    builder.write(retVal.name);
    builder.write(',');
  }

  void SetRightElbow(int player, String w) {
    Elbow s = Elbow.values.firstWhere((e) => e.name == w);
    int loc = GetPlayerDataStart(player) + PlayerOffsets.RightElbow.value;
    int val = (GameSaveData![loc] & 0xc3) + (s.index << 2);
    SetByte(loc, val);
  }

  List<String> GetColleges() {
    return Colleges.keys.toList();
  }

  Map<String, int> get Colleges {
    if (mColleges.isEmpty)
      PopulateColleges();
    return mColleges;
  }

  Map<String, int> mColleges = {};

  void PopulateColleges() {
    int loc = GetPlayerDataStart(0);
    int ptrDest = GetPointerDestination(loc);
    int i = ptrDest;
    while (GameSaveData![i] != 0)
      i -= 8;
    i += 8;
    String collegeName = '';
    while (true) {
      collegeName = GetName(i);
      mColleges[collegeName] = i;
      i += 8;
      if (collegeName.startsWith('Barnum & Bailey'))
        break;
    }
  }

  String GetCollege(int player) {
    int loc = GetPlayerDataStart(player);
    int pointerDest = GetPointerDestination(loc);
    String retVal = 'None';
    try {
      retVal = GetName(pointerDest);
      if (retVal.contains(','))
        retVal = '"$retVal"';
    } catch (e) {
      Logger.error('Invalid college detected for player ${GetPlayerName(player, ' ')}, on team ${GetPlayerTeam(player)}; Returning \'None\'.');
    }
    return retVal;
  }

  void SetCollege(int player, String college) {
    int ptrVal = 0;
    int loc = GetPlayerDataStart(player);
    if (college.startsWith('"'))
      college = college.replaceAll('"', '');

    if (Colleges.containsKey(college)) {
      ptrVal = mColleges[college]! - loc + 1;
    } else {
      List<int> ptrs = StaticUtils.FindPointersToString(college, GameSaveData!, 0, GameSaveData!.length);
      if (ptrs.isNotEmpty)
        ptrVal = ptrs[0] - loc + 1;
    }
    if (ptrVal != 0) {
      SetByte(loc, 0xff & ptrVal);
      SetByte(loc + 1, (ptrVal >> 8) & 0xff);
      SetByte(loc + 2, (ptrVal >> 16) & 0xff);
      SetByte(loc + 3, (ptrVal >> 24) & 0xff);
    }
  }

  void GetSkinPhotoMappings(StringBuffer builder) {
    String currentSkin;
    for (int j = 1; j < 23; j++) {
      currentSkin = 'Skin$j';
      builder.write(currentSkin);
      builder.write(':[');
      for (int i = 0; i <= mMaxPlayers; i++) {
        StringBuffer tmp = StringBuffer();
        GetSkin(i, tmp);
        if (tmp.toString().contains(currentSkin)) {
          GetPlayerAppearanceAttribute(i, AppearanceAttributes.Photo, builder);
        }
      }
      builder.write('],\r\n');
    }
  }

  Map<int, int> unknownStuff = {
    0x08: 4,
    0x0d: 11,
    0x1A: 2,
    0x23: 2,
    0x26: 3,
    0x2c: 9,
  };

  void GetPlayerDataUnknownData(int player, StringBuffer sb) {
    int loc = GetPlayerDataStart(player);
    int offset = 0;
    int length = 0;
    int num = 0;
    for (int i in unknownStuff.keys) {
      offset = loc + unknownStuff[i]!;
      length = unknownStuff[i]!;
      sb.write(++num);
      sb.write(':');
      for (int j = offset; j < offset + length; j++) {
        sb.write(GameSaveData![j].toRadixString(16).padLeft(2, '0'));
      }
      sb.write(',');
    }
    sb.write(GetPlayerTeam(player));
    sb.write(',');
    sb.write(GetPlayerPosition(player));
    sb.write(',');
    sb.write(GetPlayerName(player, ','));
    sb.write('\n');
  }

  void ZeroUnknownPlayerStuff(int player, int unkGrp) {
    int loc = GetPlayerDataStart(player);
    int offset = 0;
    int length = 0;
    int num = 0;
    for (int i in unknownStuff.keys) {
      offset = loc + unknownStuff[i]!;
      length = unknownStuff[i]!;
      ++num;
      if (unkGrp == num) {
        for (int j = offset; j < offset + length; j++) {
          GameSaveData![j] = 0;
        }
      }
    }
  }

  List<int> FindPlayer(String? pos, String firstName, String lastName) {
    List<int> retVal = [];
    for (int i = 0; i < mMaxPlayers; i++) {
      if (pos == null && GetPlayerLastName(i) == lastName && GetPlayerFirstName(i) == firstName)
        retVal.add(i);
      else if (pos != null && GetPlayerLastName(i) == lastName && GetPlayerFirstName(i) == firstName && GetPlayerPosition(i) == pos)
        retVal.add(i);
    }
    return retVal;
  }

  String? ApplyFormula(String formula, String targetAttribute, String targetValue,
      List<String> positions, FormulaMode formulaMode, bool applyChanges) {
    String? retVal;
    try {
      if (formulaMode != FormulaMode.Normal) {
        Logger.log("ApplyFormula('$formula','$targetAttribute','$targetValue', [${positions.join(',')}], ${formulaMode.name})");
      } else {
        Logger.log("ApplyFormula('$formula','$targetAttribute','$targetValue', [${positions.join(',')}])");
      }

      if (formula.toLowerCase() == 'always') formula = 'true';
      List<int> playerIndexes = GetPlayersByFormula(formula, positions);
      String targetValueParam = targetValue;

      if (playerIndexes.isNotEmpty) {
        String tmp = '';
        int temp_i = 0;
        StringBuffer sb = StringBuffer();
        int p = 0;

        sb.write('#Players affected = ');
        sb.write(playerIndexes.length);
        sb.write('\n');
        sb.write('#Team,FirstName,LastName,');
        sb.write(targetAttribute);
        sb.write('\n');
        int tmp_2 = 0;
        for (int i = 0; i < playerIndexes.length; i++) {
          p = playerIndexes[i];
          if (formulaMode == FormulaMode.Add) {
            tmp = GetPlayerField(p, targetAttribute);
            temp_i = int.tryParse(tmp) ?? 0;
            if (tmp == (temp_i.toString())) {
              tmp_2 = int.tryParse(targetValueParam) ?? 0;
              if (targetValueParam == tmp_2.toString() || int.tryParse(targetValueParam) != null)
                targetValue = (temp_i + tmp_2).toString();
              else
                return "Exception! value '$targetValueParam' is not an integer!";
            } else
              return "Exception! Field '$targetAttribute' is not a number!";
          } else if (formulaMode == FormulaMode.Percent) {
            tmp = GetPlayerField(p, targetAttribute);
            temp_i = int.tryParse(tmp) ?? 0;
            if (tmp == temp_i.toString()) {
              double percent = (double.tryParse(targetValueParam) ?? 0.0) * 0.01;
              targetValue = (temp_i * percent).toInt().toString();
            } else
              return "Exception! Cannot take a percent of '$targetAttribute'!";
          }
          if (applyChanges) {
            SetPlayerField(p, targetAttribute, targetValue);
          }
          sb.write(GetPlayerTeam(p));
          sb.write(',');
          sb.write(GetPlayerFirstName(p));
          sb.write(',');
          sb.write(GetPlayerLastName(p));
          sb.write(',');
          sb.write(targetValue);
          sb.write('\n');
        }
        retVal = sb.toString();
      }
    } catch (ex) {
      retVal = 'Exception! Check formula: ${ex.toString()}';
    }
    return retVal;
  }

  List<int> GetPlayersByFormula(String formula, List<String> positions) {
    List<int> retVal = [];
    if (formula.isNotEmpty) {
      String evaluationString = '';
      formula = formula
          .replaceAll('||', ' or ')
          .replaceAll('&&', ' and ')
          .replaceAll('!=', ' <> ')
          .replaceAll('>=', ' >= ')
          .replaceAll('<=', ' <= ');
      while (formula.contains('  '))
        formula = formula.replaceAll('  ', ' ');

      bool addMe = false;
      String pos = '';
      for (int i = 0; i < mMaxPlayers; i++) {
        pos = GetAttribute(i, PlayerOffsets.Position);
        if (positions.isEmpty || positions.contains(pos)) {
          evaluationString = SubstituteAttributesForValues(i, formula);
          evaluationString = SubstituteRandom(evaluationString);
          addMe = _EvaluateExpression(evaluationString);
          if (addMe) retVal.add(i);
        }
      }
    }
    return retVal;
  }

  final RegExp mRandomRegex = RegExp(r'[Rr]andom_([0-9]+)_([0-9]+)');
  final Random mRand = Random();

  String SubstituteRandom(String formula) {
    String retVal = formula;
    RegExpMatch? m = mRandomRegex.firstMatch(formula);
    if (m != null) {
      int min = int.parse(m.group(1)!);
      int max = int.parse(m.group(2)!);
      int val = mRand.nextInt(max - min) + min;
      retVal = formula.substring(0, m.start) + val.toString() + formula.substring(m.start + m[0]!.length);
    }
    return retVal;
  }

  String SubstituteAttributesForValues(int playerIndex, String formula) {
    String retVal = GetAppearanceAttributeExpression(formula, playerIndex);
    String playerTeam = '';
    List<String> parts = ('Team,' + GetDefaultKey(true, false)).split(',');

    for (String attr in parts) {
      if (attr == 'Team') {
        playerTeam = '${GetTeamIndex(GetPlayerTeam(playerIndex))}';
        retVal = retVal.replaceAll('Team', playerTeam);
        for (int j = 0; j < sTeamsDataOrder.length; j++) {
          if (retVal.contains(sTeamsDataOrder[j])) {
            retVal = retVal.replaceAll(sTeamsDataOrder[j], '$j');
          }
        }
      } else if (attr.isNotEmpty && formula.contains(attr)) {
        String tmp = GetPlayerField(playerIndex, attr);
        retVal = retVal.replaceAll(attr, tmp);
      }
    }
    return retVal;
  }

  String GetAppearanceAttributeExpression(String expr, int player) {
    List<String> attrs = [
      'Hand', 'BodyType', 'Skin', 'Face', 'Dreads', 'Helmet', 'FaceMask', 'Visor',
      'EyeBlack', 'MouthPiece', 'LeftGlove', 'RightGlove', 'LeftWrist', 'RightWrist', 'LeftElbow',
      'RightElbow', 'Sleeves', 'LeftShoe', 'RightShoe', 'NeckRoll', 'Turtleneck'
    ];
    for (String attr in attrs) {
      if (expr.contains(attr)) {
        List<String> values = _mTypeMap[attr]!;
        for (int i = 0; i < values.length; i++) {
          if (expr.contains(values[i]))
            expr = expr.replaceAll(values[i], '$i');
        }
        String v = GetPlayerField(player, attr);
        expr = expr.replaceAll(attr, '${values.indexOf(v)}');
      }
    }
    return expr;
  }

  static final Map<String, List<String>> _mTypeMap = {
    'BodyType': Body.values.map((e) => e.name).toList(),
    'Dreads': YesNo.values.map((e) => e.name).toList(),
    'EyeBlack': YesNo.values.map((e) => e.name).toList(),
    'MouthPiece': YesNo.values.map((e) => e.name).toList(),
    'LeftGlove': Glove.values.map((e) => e.name).toList(),
    'RightGlove': Glove.values.map((e) => e.name).toList(),
    'LeftWrist': Wrist.values.map((e) => e.name).toList(),
    'RightWrist': Wrist.values.map((e) => e.name).toList(),
    'LeftElbow': Elbow.values.map((e) => e.name).toList(),
    'RightElbow': Elbow.values.map((e) => e.name).toList(),
    'LeftShoe': Shoe.values.map((e) => e.name).toList(),
    'RightShoe': Shoe.values.map((e) => e.name).toList(),
    'Hand': Hand.values.map((e) => e.name).toList(),
    'Skin': Skin.values.map((e) => e.name).toList(),
    'Face': Face.values.map((e) => e.name).toList(),
    'Helmet': Helmet.values.map((e) => e.name).toList(),
    'FaceMask': FaceMask.values.map((e) => e.name).toList(),
    'Visor': Visor.values.map((e) => e.name).toList(),
    'Sleeves': Sleeves.values.map((e) => e.name).toList(),
    'NeckRoll': NeckRoll.values.map((e) => e.name).toList(),
    'Turtleneck': Turtleneck.values.map((e) => e.name).toList(),
    'PowerRunStyle': PowerRunStyle.values.map((e) => e.name).toList(),
  };

  // ── Team player-control (Franchise mode only) ──────────────────────────

  static const int _teamControlStartLoc = 0x913CC;

  /// Optional base roster data used by [autoFixSkinFromPhoto].
  /// Set this before calling that method (e.g. via gamesave_tool_io.dart).
  Uint8List? baseRosterData;

  /// Returns true if the team is set to user-controlled in the franchise save.
  bool isTeamPlayerControlled(String team) {
    int teamIndex = GetTeamIndex(team);
    int location = _teamControlStartLoc + teamIndex * 4;
    return GameSaveData![location] == 1;
  }

  /// Sets whether the given team is user-controlled (true) or CPU (false).
  void setTeamPlayerControlled(String team, bool userControlled) {
    int teamIndex = GetTeamIndex(team);
    int location = _teamControlStartLoc + teamIndex * 4;
    GameSaveData![location] = userControlled ? 1 : 0;
  }

  /// Sets all 32 teams to user-controlled.
  void setAllTeamsPlayerControlled() {
    for (int i = 0; i < 32; i++)
      setTeamPlayerControlled(sTeamsDataOrder[i], true);
  }

  /// Parses a line like `PlayerControlled=[ARI,DAL,...]` or
  /// `PlayerControlled=All` and applies the settings.
  void setPlayerControlledTeams(String line) {
    int index1 = line.indexOf('[');
    int index2 = line.indexOf(']');
    int count = 0;
    if (line.toLowerCase().contains('all')) {
      setAllTeamsPlayerControlled();
      return;
    }
    if (index1 > -1 && index2 > index1) {
      for (int i = 0; i < 32; i++) {
        String team = sTeamsDataOrder[i];
        if (!line.toLowerCase().contains(team.toLowerCase())) {
          setTeamPlayerControlled(team, false);
        } else {
          setTeamPlayerControlled(team, true);
          count++;
        }
      }
    }
    Logger.log('SetTeamsPlayerControlled: $count teams');
  }

  /// Returns a formatted `PlayerControlled=[...]` line for all currently
  /// user-controlled teams (franchise only).
  String getPlayerControlledTeams() {
    StringBuffer sb = StringBuffer();
    sb.write('PlayerControlled=[');
    int count = 0;
    if (mSaveType == SaveType.Franchise) {
      for (int i = 0; i < 32; i++) {
        String team = sTeamsDataOrder[i];
        if (isTeamPlayerControlled(team)) {
          count++;
          sb.write('$team,');
        }
      }
    }
    sb.write(']\n');
    sb.write('# PlayerControlledTeams=$count\n');
    if (mSaveType == SaveType.Roster)
      sb.write('#PlayerControlledTeams not applicable to Type = Roster');
    return sb.toString();
  }

  // ── Photo / skin auto-fix ───────────────────────────────────────────────

  /// Builds a photo→skin/face map from [baseRosterData] (or the stored
  /// [baseRosterData] field if [baseRosterData] arg is null) and updates any
  /// player in the current save whose skin or face doesn't match the map.
  void autoFixSkinFromPhoto([Uint8List? baseRosterOverride]) {
    Uint8List? baseData = baseRosterOverride ?? baseRosterData;
    if (baseData == null) {
      Logger.log('autoFixSkinFromPhoto: no base roster data provided; skipping.');
      return;
    }
    Logger.log('AutoFixSkinFromPhoto');
    const int playerLimit = 1928;
    GamesaveTool baseTool = GamesaveTool();
    baseTool.GameSaveData = baseData;
    baseTool.setupForSaveType();

    Map<String, String> photoSkinMap = {};
    Map<String, String> photoFaceMap = {};
    for (int player = 0; player < playerLimit; player++) {
      String photo = baseTool.GetPlayerField(player, 'Photo');
      String face  = baseTool.GetPlayerField(player, 'Face');
      String skin  = baseTool.GetPlayerField(player, 'Skin');
      if (photo != '0004' && !photoSkinMap.containsKey(photo)) {
        photoSkinMap[photo] = skin;
        photoFaceMap[photo] = face;
      }
    }

    for (int player = 0; player < playerLimit; player++) {
      String photo = GetPlayerField(player, 'Photo');
      String face  = GetPlayerField(player, 'Face');
      String skin  = GetPlayerField(player, 'Skin');
      if (photo != '0004' && photoSkinMap.containsKey(photo)) {
        if (face != photoFaceMap[photo] || skin != photoSkinMap[photo]) {
          try {
            SetAttribute(player, PlayerOffsets.Face, photoFaceMap[photo]!);
            SetPlayerField(player, 'Skin', photoSkinMap[photo]!);
            Logger.log('Updated Player ${GetPlayerPosition(player)} '
                '${GetPlayerName(player, ' ')} Photo=$photo;-> '
                '${photoSkinMap[photo]} ${photoFaceMap[photo]}');
          } catch (e) {
            Logger.log('autoFixSkinFromPhoto: skipping player $player '
                '(${GetPlayerName(player, ' ')}) – invalid value: $e');
          }
        }
      }
    }
  }

  bool _EvaluateExpression(String expr) {
    expr = expr.trim();
    String lower = expr.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;

    // Handle 'or' (lowest precedence)
    int idx = lower.indexOf(' or ');
    if (idx > -1) {
      return _EvaluateExpression(expr.substring(0, idx)) ||
             _EvaluateExpression(expr.substring(idx + 4));
    }

    // Handle 'and'
    idx = lower.indexOf(' and ');
    if (idx > -1) {
      return _EvaluateExpression(expr.substring(0, idx)) &&
             _EvaluateExpression(expr.substring(idx + 5));
    }

    // Single comparison operators (multi-char first)
    for (String op in ['<>', '>=', '<=', '>', '<', '=']) {
      int opIdx = expr.indexOf(op);
      if (opIdx > -1) {
        String left = expr.substring(0, opIdx).trim();
        String right = expr.substring(opIdx + op.length).trim();
        num? l = num.tryParse(left);
        num? r = num.tryParse(right);
        if (l != null && r != null) {
          switch (op) {
            case '<>': return l != r;
            case '>=': return l >= r;
            case '<=': return l <= r;
            case '>': return l > r;
            case '<': return l < r;
            case '=': return l == r;
          }
        }
      }
    }
    return false;
  }

}
