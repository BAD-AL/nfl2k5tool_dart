// Translated from EnumDefinitions.cs
// ignore_for_file: constant_identifier_names, non_constant_identifier_names

enum SaveType { Roster, Franchise }

/// Code to map player attributes to locations.
/// Addresses are based on a franchise file, not a roster file.
enum PlayerOffsets {
  College(0),
  PBP(4),
  Photo(6),
  Helmet_LeftShoe_RightShoe(0x0c),
  Turtleneck_Body_EyeBlack_Hand_Dreads(0x18),
  DOB(0x19),
  MouthPiece_LeftGlove_Sleeves_NeckRoll(0x1c),
  RightGlove_LeftWrist(0x1d),
  RightWrist_LeftElbow(0x1e),
  RightElbow(0x1f),
  JerseyNumber(0x20),
  FaceMask(0x21),
  Face(0x22),
  YearsPro(0x25),
  Depth(0x29),
  Weight(0x2a),
  Height(0x2b),
  Position(0x35),
  Speed(0x36),
  Agility(0x37),
  PassArmStrength(0x38),
  Stamina(0x39),
  KickPower(0x3a),
  Durability(0x3b),
  Strength(0x3c),
  Jumping(0x3d),
  Coverage(0x3e),
  RunRoute(0x3f),
  Tackle(0x40),
  BreakTackle(0x41),
  PassAccuracy(0x42),
  PassReadCoverage(0x43),
  Catch(0x44),
  RunBlocking(0x45),
  PassBlocking(0x46),
  HoldOntoBall(0x47),
  PassRush(0x48),
  RunCoverage(0x49),
  KickAccuracy(0x4a),
  Leadership(0x4c),
  PowerRunStyle(0x4d),
  Composure(0x4e),
  Scramble(0x4f),
  Consistency(0x50),
  Aggressiveness(0x51);

  const PlayerOffsets(this.value);
  final int value;
}

enum AppearanceAttributes {
  College(200),
  DOB(201),
  YearsPro(202),
  PBP(203),
  Photo(204),
  Hand(205),
  Weight(206),
  Height(207),
  BodyType(208),
  Skin(209),
  Face(210),
  Dreads(211),
  Helmet(212),
  FaceMask(213),
  Visor(214),
  EyeBlack(215),
  MouthPiece(216),
  LeftGlove(217),
  RightGlove(218),
  LeftWrist(219),
  RightWrist(220),
  LeftElbow(221),
  RightElbow(222),
  Sleeves(223),
  LeftShoe(224),
  RightShoe(225),
  NeckRoll(226),
  Turtleneck(227);

  const AppearanceAttributes(this.value);
  final int value;
}

/// Enum for positions
enum Positions {
  QB(0),
  K(1),
  P(2),
  WR(3),
  CB(4),
  FS(5),
  SS(6),
  RB(7),
  FB(8),
  TE(9),
  OLB(10),
  ILB(11),
  C(12),
  G(13),
  T(14),
  DT(15),
  DE(16);

  const Positions(this.value);
  final int value;
}

/// Power run style enum
enum PowerRunStyle {
  Finesse(1),
  Balanced(0x32),
  Power(0x63);

  const PowerRunStyle(this.value);
  final int value;
}

enum Turtleneck { None, White, Black, Team }

enum Body { Skinny, Normal, Large, ExtraLarge }

enum YesNo { No, Yes }

enum Hand { Left, Right }

enum Face {
  Face1, Face2, Face3, Face4, Face5, Face6, Face7, Face8,
  Face9, Face10, Face11, Face12, Face13, Face14, Face15
}

enum FaceMask {
  FaceMask1, FaceMask2, FaceMask3, FaceMask4, FaceMask5,
  FaceMask6, FaceMask7, FaceMask8, FaceMask9, FaceMask10,
  FaceMask11, FaceMask12, FaceMask13, FaceMask14, FaceMask15,
  FaceMask16, FaceMask17, FaceMask18, FaceMask19, FaceMask20,
  FaceMask21, FaceMask22, FaceMask23, FaceMask24, FaceMask25,
  FaceMask26, FaceMask27
}

enum Visor { None, Dark, Clear }

enum Skin {
  Skin1, Skin2, Skin3, Skin4, Skin5, Skin6, Skin7, Skin8,
  Skin9, Skin10, Skin11, Skin12, Skin13, Skin14, Skin15,
  Skin16, Skin17, Skin18, Skin19, Skin20, Skin21, Skin22
}

enum Helmet { Standard, Revolution }

enum Shoe { Shoe1, Shoe2, Shoe3, Shoe4, Shoe5, Shoe6, Taped }

enum Glove {
  None, Type1, Type2, Type3, Type4,
  Team1, Team2, Team3, Team4, Taped
}

enum Sleeves { None, White, Black, Team }

enum NeckRoll { None, Collar, Roll, Washboard, Bulging }

enum Wrist {
  None, SingleWhite, DoubleWhite, SingleBlack, DoubleBlack,
  NeopreneSmall, NeopreneLarge, ElasticSmall, ElasticLarge,
  SingleTeam, DoubleTeam, TapedSmall, TapedLarge, Quarterback
}

enum Elbow {
  None, White, Black, WhiteBlackStripe, BlackWhiteStripe,
  BlackTeamStripe, Team, WhiteTeamStripe, Elastic, Neoprene,
  WhiteTurf, BlackTurf, Taped, HighWhite, HighBlack, HighTeam
}

enum Game {
  HomeTeam(0),
  AwayTeam(1),
  Month(2),
  Day(3),
  YearTwoDigit(4),
  HourOfDay(5),
  MinuteOfHour(6),
  NullByte(7);

  const Game(this.value);
  final int value;
}

enum SpecialTeamer {
  KR1(0x195),
  KR2(0x196),
  LS(0x198),
  PR(0x199);

  const SpecialTeamer(this.value);
  final int value;
}

enum CoachOffsets {
  FirstName(0x0),
  LastName(0x4),
  Info1(0x8),
  Info2(0xc),
  Info3(0x10),
  Body(0x18),
  Wins(0x20),
  Losses(0x22),
  Ties(0x24),
  SeasonsWithTeam(0x1c),
  totalSeasons(0x1e),
  WinningSeasons(0x30),
  SuperBowls(0x32),
  SuperBowlWins(0x38),
  SuperBowlLosses(0x3a),
  PlayoffWins(0x34),
  PlayoffLosses(0x36),
  Photo(0x40),
  Overall(0x42),
  OvrallOffense(0x43),
  RushFor(0x44),
  PassFor(0x45),
  OverallDefense(0x46),
  PassRush(0x47),
  PassCoverage(0x48),
  QB(0x49),
  RB(0x4a),
  TE(0x4b),
  WR(0x4c),
  OL(0x4d),
  DL(0x4e),
  LB(0x4f),
  DB(0x50),
  SpecialTeams(0x51),
  Professionalism(0x52),
  Preparation(0x53),
  Conditioning(0x54),
  Motivation(0x55),
  Leadership(0x56),
  Discipline(0x57),
  Respect(0x58),
  PlaycallingRun(0x59),
  ShotgunRun(0x83),
  IFormRun(0x83),
  SplitbackRun(0x87),
  EmptyRun(0x87),
  ShotgunPass(0x88),
  SplitbackPass(0x89),
  IFormPass(0x8a),
  LoneBackPass(0x8b),
  EmptyPass(0x8c);

  const CoachOffsets(this.value);
  final int value;
}

enum TeamDataOffsets {
  Nickname,      // S3a[0] e.g. "49ers"
  Abbrev,        // S3a[1] e.g. "SF"
  Stadium,       // special: reads S1a via byte index; writes via SetStadiumIndex
                 // formatted with [brackets] in text files, e.g. "[San Francisco Park]"
  City,          // S3a[3] e.g. "San Francisco"
  AbbrAlt,       // S3a[4] e.g. "SF" (repeated for a second display context)
  Logo,          // logo/PBP team index byte (teamBlock+0x154) + S3a[2] string; decimal int
  Playbook,      // playbook selection; stored as two relative pointers (name + abbrev).
                 // value format: "PB_" + name with spaces replaced by "_"
                 // e.g. "PB_49ers", "PB_West_Coast", "PB_General"
                 // get/set updates both offense and defense pointers atomically
  DefaultJersey, // default jersey index byte (teamBlock+0x192); 0=home 1=away
}

enum FormulaMode { Normal, Add, Percent }
