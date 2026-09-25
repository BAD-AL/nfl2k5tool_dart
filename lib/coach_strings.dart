// Coach-string overflow check + reduce feature.
//
// The coach-string pool (FirstName/LastName/Info1/Info2/Info3 for all 32
// coaches, UTF-16LE, null-terminated, sharing one fixed-size byte budget)
// has a fixed physical capacity — architecturally the same shape as the
// player-name pool (S3b) PlayerNames models in player_names.dart, just much
// smaller and, unlike S3b, with no existing sharing to exploit (every coach
// string in the stock file is independently stored). See that class's doc
// comment for the general read-overlay-commit design this mirrors.
// ignore_for_file: non_constant_identifier_names

import 'enum_definitions.dart';
import 'gamesave_tool.dart';
import 'player_names.dart' show CommitResult;

/// One coach string field's current value and location.
class CoachStringRef {
  final int coachIndex;
  final CoachOffsets attr;
  String text;

  CoachStringRef({
    required this.coachIndex,
    required this.attr,
    required this.text,
  });
}

/// The five string-typed coach attributes that live in the shared pool —
/// Body/Photo/etc. are fixed-size, non-string fields stored elsewhere.
const List<CoachOffsets> kCoachStringAttrs = [
  CoachOffsets.FirstName,
  CoachOffsets.LastName,
  CoachOffsets.Info1,
  CoachOffsets.Info2,
  CoachOffsets.Info3,
];

/// Models the coach-string pool independently of [GameSaveData] so a caller
/// can inspect it and decide on reductions before ever writing a byte — see
/// PlayerNames for the full design this is based on.
class CoachStrings {
  final GamesaveTool tool;
  final List<CoachStringRef> _refs = [];

  /// Empirical start of the coach-string pool — the lowest resolved string
  /// pointer destination among all 160 fields, the same way PlayerNames
  /// computes s3bStart, rather than assuming any particular coach's field
  /// is always first (GameSaveTool's own internal code hardcodes coach 0's
  /// FirstName for this, which happens to agree with this empirical value
  /// in every file checked so far, but isn't guaranteed by anything).
  late final int _sectionStart;

  static const int budget = 5297;

  /// Maximum characters a single field can hold and still be read back
  /// correctly. GamesaveTool.GetString (which GetName/GetCoachAttribute —
  /// and every other reader in the app — rely on) scans at most 99 bytes
  /// from a string's start (49.5 UTF-16 characters, floor 49) looking for
  /// its null terminator; a 50-character string's terminator lands exactly
  /// on the scan boundary and still gets read correctly (verified against
  /// GetString's exact loop), but 51+ characters silently drops everything
  /// past the 50th, even though commit() wrote it correctly. commit()
  /// refuses rather than let that happen invisibly — this is a per-field
  /// ceiling independent of, and tighter than, the pool-wide [budget].
  static const int maxFieldChars = 50;

  CoachStrings._(this.tool);

  factory CoachStrings.fromTool(GamesaveTool tool) {
    final strings = CoachStrings._(tool);
    strings._load();
    return strings;
  }

  void _load() {
    int minAddr = 1 << 30;
    for (int coach = 0; coach < 32; coach++) {
      final coachPtr = tool.GetPointerDestination(tool.GetCoachPointer(coach));
      for (final attr in kCoachStringAttrs) {
        final ptrLoc = coachPtr + attr.value;
        final dest = tool.GetPointerDestination(ptrLoc);
        if (dest < minAddr) minAddr = dest;
        // Read the raw stored string directly via GetName — NOT
        // GetCoachAttribute, which wraps comma-containing strings in
        // synthesized quotes for CSV-display safety on the way out. Those
        // quotes are never actually stored, so counting them would overcount
        // the real byte cost (confirmed against the stock franchise file:
        // GetCoachAttribute-based counting comes out ~44 bytes over what's
        // physically stored — this is the same over-counting bug the web
        // app's existing "Coach Strings" indicator currently has).
        final text = tool.GetName(ptrLoc);
        _refs.add(CoachStringRef(coachIndex: coach, attr: attr, text: text));
      }
    }
    _sectionStart = minAddr;
  }

  /// Only ever call this for a (coachIndex, attr) pair loaded by [_load] —
  /// i.e. one of [kCoachStringAttrs].
  void overlayEdit(int coachIndex, CoachOffsets attr, String text) {
    final ref = _refs.firstWhere(
        (r) => r.coachIndex == coachIndex && r.attr == attr);
    ref.text = text;
  }

  /// Naive total: every field's own storage cost, no sharing considered.
  /// Meaningful as-is (not just a ceiling) because, unlike player names,
  /// there's no existing sharing among coach strings to model separately.
  int get requiredBytes {
    int sum = 0;
    for (final r in _refs) {
      sum += (r.text.length + 1) * 2;
    }
    return sum;
  }

  void _writeAbsolutePointer(int pointerLoc, int destination) {
    final value = destination - pointerLoc + 1;
    tool.SetByte(pointerLoc, value & 0xff);
    tool.SetByte(pointerLoc + 1, (value >> 8) & 0xff);
    tool.SetByte(pointerLoc + 2, (value >> 16) & 0xff);
    tool.SetByte(pointerLoc + 3, (value >> 24) & 0xff);
  }

  /// The single real write: lays out every remaining string starting at
  /// [_sectionStart], re-targets every coach string pointer, then zero-fills
  /// the rest of the pool. Fully validates before writing anything — on
  /// failure, [tool]'s GameSaveData is left byte-for-byte untouched.
  CommitResult commit() {
    int total = 0;
    final tooLong = <String>[];
    for (final r in _refs) {
      total += (r.text.length + 1) * 2;
      if (r.text.length > maxFieldChars) {
        tooLong.add('coach${r.coachIndex}.${r.attr.name} (${r.text.length} chars)');
      }
    }

    if (tooLong.isNotEmpty) {
      return CommitResult(
        success: false,
        bytesUsed: total,
        bytesFree: budget - total,
        warnings: [
          'The following fields exceed the $maxFieldChars-character limit '
              'this save format can read back correctly, and would be '
              'silently truncated everywhere else in the app: '
              '${tooLong.join(', ')}.'
        ],
      );
    }

    if (total > budget) {
      return CommitResult(
        success: false,
        bytesUsed: total,
        bytesFree: budget - total,
        warnings: [
          'Required $total bytes exceeds the $budget-byte budget by ${total - budget} bytes.'
        ],
      );
    }

    // Write. Nothing above this point touched GameSaveData.
    int offset = _sectionStart;
    for (final r in _refs) {
      final addr = offset;
      for (int i = 0; i < r.text.length; i++) {
        tool.SetByte(offset, r.text.codeUnitAt(i) & 0xff);
        tool.SetByte(offset + 1, 0);
        offset += 2;
      }
      tool.SetByte(offset, 0);
      tool.SetByte(offset + 1, 0);
      offset += 2;

      final coachPtr = tool.GetPointerDestination(tool.GetCoachPointer(r.coachIndex));
      _writeAbsolutePointer(coachPtr + r.attr.value, addr);
    }
    for (int i = offset; i < _sectionStart + budget; i++) {
      tool.SetByte(i, 0);
    }

    return CommitResult(success: true, bytesUsed: total, bytesFree: budget - total);
  }
}
