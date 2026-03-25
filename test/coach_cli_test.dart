import 'dart:io';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';
import 'package:nfl2k5tool_dart/program.dart';
import 'package:test/test.dart';

String testFile(String name) =>
    '${Directory.current.path}/test/test_files/$name';

/// Captures Logger output from [Program.RunMain].
String runCapture(List<String> args) {
  final buf = StringBuffer();
  final prev = Logger.logHandler;
  Logger.logHandler = buf.write;
  try {
    Program.RunMain(args);
  } finally {
    Logger.logHandler = prev;
  }
  return buf.toString();
}

/// Splits a coach CSV line, respecting double-quoted fields ("...") and
/// bracketed body fields ([...]).
List<String> _splitCoachLine(String line) {
  final fields = <String>[];
  final buf = StringBuffer();
  bool inQuote = false;
  bool inBracket = false;
  for (final ch in line.trimRight().runes.map(String.fromCharCode)) {
    if (ch == '"' && !inBracket) {
      inQuote = !inQuote;
    } else if (ch == '[' && !inQuote) {
      inBracket = true;
      buf.write(ch);
    } else if (ch == ']' && inBracket) {
      inBracket = false;
      buf.write(ch);
    } else if (ch == ',' && !inQuote && !inBracket) {
      fields.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  fields.add(buf.toString());
  return fields;
}

/// Parses a "CoachKEY=..." line and a "Coach,..." data line into a
/// field-name → value map.
Map<String, String> _parseCoachLine(String keyLine, String dataLine) {
  final keyPart = keyLine.contains('=') ? keyLine.split('=').skip(1).join('=') : keyLine;
  final keys = keyPart.trim().split(',');
  final values = _splitCoachLine(dataLine);
  final map = <String, String>{};
  for (int i = 0; i < keys.length && i < values.length; i++) {
    map[keys[i].trim()] = values[i].trim();
  }
  return map;
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // CLI -coach_all output sanity tests using Base2004Fran_Orig.zip
  // ───────────────────────────────────────────────────────────────────────────
  group('CLI -coach_all – Base2004Fran_Orig.zip', () {
    late String keyLine;
    late Map<String, String> erickson;
    late Map<String, String> dungy;

    setUpAll(() {
      final output = runCapture(
          [testFile('Base2004Fran_Orig.zip'), '-coach_all']);

      keyLine = output
          .split('\n')
          .firstWhere((l) => l.trimLeft().startsWith('CoachKEY='),
              orElse: () => '');

      final coachLines = output
          .split('\n')
          .where((l) => l.trimLeft().startsWith('Coach,'))
          .toList();

      final ericLine = coachLines.firstWhere(
          (l) => l.split(',').length > 1 && l.split(',')[1] == '49ers',
          orElse: () => '');
      final dungyLine = coachLines.firstWhere(
          (l) => l.split(',').length > 1 && l.split(',')[1] == 'Colts',
          orElse: () => '');

      erickson = _parseCoachLine(keyLine, ericLine);
      dungy = _parseCoachLine(keyLine, dungyLine);
    });

    // ── CoachKEY sanity ──────────────────────────────────────────────────────
    test('CoachKEY line present and contains key playcalling fields', () {
      expect(keyLine, startsWith('CoachKEY='));
      expect(keyLine, contains('Wins'));
      expect(keyLine, contains('PlaycallingRun'));
      expect(keyLine, contains('ShotgunRun'));
      expect(keyLine, contains('IFormRun'));
      expect(keyLine, contains('SplitbackRun'));
      expect(keyLine, contains('EmptyRun'));
      expect(keyLine, contains('EmptyPass'));
    });

    // ── Dennis Erickson / 49ers ──────────────────────────────────────────────
    group('Dennis Erickson (49ers)', () {
      test('parsed line is non-empty', () => expect(erickson, isNotEmpty));
      test('FirstName = Dennis',   () => expect(erickson['FirstName'], equals('Dennis')));
      test('LastName = Erickson',  () => expect(erickson['LastName'],  equals('Erickson')));

      test('Wins = 38',            () => expect(erickson['Wins'],            equals('38')));
      test('Losses = 42',          () => expect(erickson['Losses'],          equals('42')));
      test('Ties = 0',             () => expect(erickson['Ties'],            equals('0')));
      test('SeasonsWithTeam = 1',  () => expect(erickson['SeasonsWithTeam'], equals('1')));
      test('totalSeasons = 5',     () => expect(erickson['totalSeasons'],    equals('5')));
      test('WinningSeasons = 0',   () => expect(erickson['WinningSeasons'],  equals('0')));
      test('SuperBowls = 0',       () => expect(erickson['SuperBowls'],      equals('0')));
      test('SuperBowlWins = 0',    () => expect(erickson['SuperBowlWins'],   equals('0')));
      test('SuperBowlLosses = 0',  () => expect(erickson['SuperBowlLosses'], equals('0')));
      test('PlayoffWins = 0',      () => expect(erickson['PlayoffWins'],     equals('0')));
      test('PlayoffLosses = 0',    () => expect(erickson['PlayoffLosses'],   equals('0')));

      test('Overall = 60',         () => expect(erickson['Overall'],         equals('60')));
      test('OvrallOffense = 69',   () => expect(erickson['OvrallOffense'],   equals('69')));
      test('RushFor = 61',         () => expect(erickson['RushFor'],         equals('61')));
      test('PassFor = 76',         () => expect(erickson['PassFor'],         equals('76')));
      test('OverallDefense = 69',  () => expect(erickson['OverallDefense'],  equals('69')));
      test('PassRush = 69',        () => expect(erickson['PassRush'],        equals('69')));
      test('PassCoverage = 76',    () => expect(erickson['PassCoverage'],    equals('76')));

      test('QB = 72',              () => expect(erickson['QB'],              equals('72')));
      test('RB = 76',              () => expect(erickson['RB'],              equals('76')));
      test('TE = 75',              () => expect(erickson['TE'],              equals('75')));
      test('WR = 74',              () => expect(erickson['WR'],              equals('74')));
      test('OL = 68',              () => expect(erickson['OL'],              equals('68')));
      test('DL = 77',              () => expect(erickson['DL'],              equals('77')));
      test('LB = 80',              () => expect(erickson['LB'],              equals('80')));
      test('SpecialTeams = 76',    () => expect(erickson['SpecialTeams'],    equals('76')));

      test('Professionalism = 84', () => expect(erickson['Professionalism'], equals('84')));
      test('Preparation = 83',     () => expect(erickson['Preparation'],     equals('83')));
      test('Conditioning = 76',    () => expect(erickson['Conditioning'],    equals('76')));
      test('Motivation = 75',      () => expect(erickson['Motivation'],      equals('75')));
      test('Leadership = 76',      () => expect(erickson['Leadership'],      equals('76')));
      test('Discipline = 69',      () => expect(erickson['Discipline'],      equals('69')));
      test('Respect = 70',         () => expect(erickson['Respect'],         equals('70')));

      test('PlaycallingRun = 45',  () => expect(erickson['PlaycallingRun'],  equals('45')));
      test('ShotgunRun = 15',      () => expect(erickson['ShotgunRun'],      equals('15')));
      test('IFormRun = 14',        () => expect(erickson['IFormRun'],        equals('14')));
      test('SplitbackRun = 10',    () => expect(erickson['SplitbackRun'],    equals('10')));
      test('EmptyRun = 9',         () => expect(erickson['EmptyRun'],        equals('9')));
      test('ShotgunPass = 3',      () => expect(erickson['ShotgunPass'],     equals('3')));
      test('SplitbackPass = 12',   () => expect(erickson['SplitbackPass'],   equals('12')));
      test('IFormPass = 40',       () => expect(erickson['IFormPass'],       equals('40')));
      test('LoneBackPass = 38',    () => expect(erickson['LoneBackPass'],    equals('38')));
      test('EmptyPass = 7',        () => expect(erickson['EmptyPass'],       equals('7')));
    });

    // ── Tony Dungy / Colts ───────────────────────────────────────────────────
    group('Tony Dungy (Colts)', () {
      test('parsed line is non-empty', () => expect(dungy, isNotEmpty));
      test('FirstName = Tony',     () => expect(dungy['FirstName'], equals('Tony')));
      test('LastName = Dungy',     () => expect(dungy['LastName'],  equals('Dungy')));

      test('Wins = 76',            () => expect(dungy['Wins'],            equals('76')));
      test('Losses = 52',          () => expect(dungy['Losses'],          equals('52')));
      test('Ties = 0',             () => expect(dungy['Ties'],            equals('0')));
      test('SeasonsWithTeam = 2',  () => expect(dungy['SeasonsWithTeam'], equals('2')));
      test('totalSeasons = 8',     () => expect(dungy['totalSeasons'],    equals('8')));
      test('WinningSeasons = 6',   () => expect(dungy['WinningSeasons'],  equals('6')));
      test('SuperBowls = 0',       () => expect(dungy['SuperBowls'],      equals('0')));
      test('SuperBowlWins = 0',    () => expect(dungy['SuperBowlWins'],   equals('0')));
      test('SuperBowlLosses = 0',  () => expect(dungy['SuperBowlLosses'], equals('0')));
      test('PlayoffWins = 4',      () => expect(dungy['PlayoffWins'],     equals('4')));
      test('PlayoffLosses = 6',    () => expect(dungy['PlayoffLosses'],   equals('6')));

      test('Overall = 84',         () => expect(dungy['Overall'],         equals('84')));
      test('OvrallOffense = 89',   () => expect(dungy['OvrallOffense'],   equals('89')));
      test('RushFor = 84',         () => expect(dungy['RushFor'],         equals('84')));
      test('PassFor = 97',         () => expect(dungy['PassFor'],         equals('97')));
      test('OverallDefense = 88',  () => expect(dungy['OverallDefense'],  equals('88')));
      test('PassRush = 83',        () => expect(dungy['PassRush'],        equals('83')));
      test('PassCoverage = 80',    () => expect(dungy['PassCoverage'],    equals('80')));

      test('QB = 91',              () => expect(dungy['QB'],              equals('91')));
      test('RB = 84',              () => expect(dungy['RB'],              equals('84')));
      test('TE = 84',              () => expect(dungy['TE'],              equals('84')));
      test('WR = 91',              () => expect(dungy['WR'],              equals('91')));
      test('OL = 84',              () => expect(dungy['OL'],              equals('84')));
      test('DL = 77',              () => expect(dungy['DL'],              equals('77')));
      test('LB = 82',              () => expect(dungy['LB'],              equals('82')));
      test('SpecialTeams = 62',    () => expect(dungy['SpecialTeams'],    equals('62')));

      test('Professionalism = 92', () => expect(dungy['Professionalism'], equals('92')));
      test('Preparation = 92',     () => expect(dungy['Preparation'],     equals('92')));
      test('Conditioning = 91',    () => expect(dungy['Conditioning'],    equals('91')));
      test('Motivation = 83',      () => expect(dungy['Motivation'],      equals('83')));
      test('Leadership = 84',      () => expect(dungy['Leadership'],      equals('84')));
      test('Discipline = 83',      () => expect(dungy['Discipline'],      equals('83')));
      test('Respect = 91',         () => expect(dungy['Respect'],         equals('91')));

      test('PlaycallingRun = 40',  () => expect(dungy['PlaycallingRun'],  equals('40')));
      test('ShotgunRun = 40',      () => expect(dungy['ShotgunRun'],      equals('40')));
      test('IFormRun = 1',         () => expect(dungy['IFormRun'],        equals('1')));
      test('SplitbackRun = 12',    () => expect(dungy['SplitbackRun'],    equals('12')));
      test('EmptyRun = 1',         () => expect(dungy['EmptyRun'],        equals('1')));
      test('ShotgunPass = 40',     () => expect(dungy['ShotgunPass'],     equals('40')));
      test('SplitbackPass = 5',    () => expect(dungy['SplitbackPass'],   equals('5')));
      test('IFormPass = 7',        () => expect(dungy['IFormPass'],       equals('7')));
      test('LoneBackPass = 37',    () => expect(dungy['LoneBackPass'],    equals('37')));
      test('EmptyPass = 11',       () => expect(dungy['EmptyPass'],       equals('11')));
    });
  });
}
