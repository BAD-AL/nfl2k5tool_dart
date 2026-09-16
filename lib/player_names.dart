// Player-name overflow check + reduce feature.
//
// The player-name pool (S3b: every player's first+last name, UTF-16LE,
// null-terminated, packed contiguously) has a fixed physical capacity. This
// file models that pool independently of GameSaveData so a caller can read
// the current names, overlay pending text edits, evaluate reduction options
// (dedup / truncation), and commit a single, validated rewrite of the pool —
// rather than mutating the gamesave incrementally while decisions are still
// being made. See GAMESAVE_SECTIONS.md for the byte-level pool layout.
// ignore_for_file: non_constant_identifier_names

import 'dart:typed_data';

import 'gamesave_tool.dart';

/// Mirrors GamesaveTool._cPlayerDataLength, which is file-private there.
const int _kPlayerDataLength = 0x54;

/// One player's first- or last-name slot. Only ever constructed for Team +
/// FreeAgent players — draft-class players are entirely outside PlayerNames'
/// domain (see PlayerNames._load).
class NameRef {
  final int playerIndex;
  final bool isLastName;
  final bool isFreeAgent;

  /// Position within GetPlayerIndexesForTeam('FreeAgents'); null if not a
  /// free agent. Lower = listed earlier = higher priority (protected later).
  final int? freeAgentListOrder;

  String text;

  /// Null if this ref owns its own storage in the pool. Non-null means this
  /// ref's name is byte-identical to [dedupOwner]'s and shares its address —
  /// set only by [PlayerNames.applyDedup], never automatically.
  NameRef? dedupOwner;

  /// Filled in by [PlayerNames.commit] for whichever refs end up owning
  /// storage (i.e. dedupOwner == null at commit time).
  int? committedAddress;

  NameRef({
    required this.playerIndex,
    required this.isLastName,
    required this.text,
    required this.isFreeAgent,
    required this.freeAgentListOrder,
  });
}

class DedupGroupPlan {
  final bool isLastName;
  final String text;
  final NameRef canonical;
  final List<NameRef> redirected;
  final int savingsBytes;

  DedupGroupPlan({
    required this.isLastName,
    required this.text,
    required this.canonical,
    required this.redirected,
    required this.savingsBytes,
  });
}

class DedupPlan {
  final List<DedupGroupPlan> groups;
  final int totalSavings;
  DedupPlan(this.groups, this.totalSavings);
}

class TruncationEntry {
  final NameRef ref;
  final String originalText;
  final String newText;
  final int savingsBytes;

  TruncationEntry({
    required this.ref,
    required this.originalText,
    required this.newText,
    required this.savingsBytes,
  });
}

class TruncationPlan {
  final List<TruncationEntry> entries;
  final int totalSavings;
  TruncationPlan(this.entries, this.totalSavings);
}

class CommitResult {
  final bool success;
  final int bytesUsed;
  final int bytesFree;
  final List<String> warnings;

  CommitResult({
    required this.success,
    required this.bytesUsed,
    required this.bytesFree,
    this.warnings = const [],
  });
}

/// Models the player-name pool (S3b) independently of [GameSaveData] so a
/// caller can inspect it and decide on reductions before ever writing a byte.
///
/// Typical usage (this is exactly what player_names_apply.dart's two
/// functions do, for a caller driven by text/InputParser):
/// ```dart
/// // 1. Read the current save + overlay pending edits.
/// final names = PlayerNames.fromTool(tool);
/// names.overlayEdit(playerIndex, /*isLastName*/ false, 'NewName');
///
/// // 2. Check whether it fits. If not, inspect reduction options — each
/// //    plan reports its own best-case savings; nothing is applied yet.
/// if (names.requiredBytes > PlayerNames.budget) {
///   final dedup = names.planDedup();       // best case: names.planDedup()
///   final trunc = names.planTruncation();  // best case: names.planTruncation()
///   // ...show dedup.totalSavings / trunc.totalSavings to the caller so
///   // they can choose which technique(s) to use...
///
///   // 3. Apply whichever the caller picked (either, both, or a minimal
///   //    plan via planDedup(targetBytes: deficit) to touch fewer players).
///   names.applyDedup(dedup);
/// }
///
/// // 4. Commit exactly once. Validates fully before writing anything —
/// //    on failure, GameSaveData is left completely untouched.
/// final result = names.commit();
/// if (!result.success) {
///   // report result.warnings; nothing was written.
/// }
/// ```
///
/// Only [commit] ever touches [GameSaveData]. Steps 1–3 are pure in-memory
/// planning and can be repeated, undone (by discarding this [PlayerNames]
/// and starting over), or previewed to the caller freely.
class PlayerNames {
  final GamesaveTool tool;
  final List<NameRef> _firstNames = [];
  final List<NameRef> _lastNames = [];

  /// Empirical start of the player-name pool (S3b) — not a compile-time
  /// constant, computed once at load time the same way this session verified
  /// pool capacity: the lowest resolved player fname/lname pointer
  /// destination.
  late final int s3bStart;

  static const int budget = 54303;

  /// Snapshot of GameSaveData taken by collectPlayerNamesFromText before its
  /// InputParser pass writes any non-name attribute — needed because that
  /// pass mutates GameSaveData for everything except names before the caller
  /// ever finds out whether a name commit will succeed. If commit() fails,
  /// commitPlayerNamesAndApplyRest restores this so the tool ends up
  /// completely untouched rather than left with a half-applied edit (names
  /// unchanged, everything else changed). Null if this PlayerNames was built
  /// directly via [fromTool] for planning/inspection with no text pass.
  Uint8List? preCollectSnapshot;

  PlayerNames._(this.tool);

  factory PlayerNames.fromTool(GamesaveTool tool) {
    final names = PlayerNames._(tool);
    names._load();
    return names;
  }

  /// Team + FreeAgent players — the exclusive upper bound of PlayerNames'
  /// *editable* domain. Draft-class players (this index and above) are
  /// never edited through PlayerNames: edits to them are handled by the
  /// caller via the original SetPlayerFirstName/LastName(..., useExistingName)
  /// path — see player_names_apply.dart.
  ///
  /// In a Franchise save, every draft-class name pointer resolves outside
  /// S3b entirely (verified against real files — they point into the
  /// separate, pre-existing, read-only college-name section), so in that
  /// file type this is also where *modeling* stops. But in a Roster save,
  /// this same index range holds a handful of fixed, permanent entries (e.g.
  /// broadcast-booth names) whose pointers resolve *inside* S3b — that's
  /// real data physically living in the pool this class repacks. [_load]'s
  /// second pass finds and models those specific entries (read-only —
  /// never a dedup/truncation candidate, never edited) purely so [commit]'s
  /// repack preserves rather than silently zeroes them.
  static int get _modeledPlayerCount => GamesaveTool.FirstDraftClassPlayer;

  void _load() {
    final faIndexes = tool.GetPlayerIndexesForTeam('FreeAgents');
    final faOrder = <int, int>{};
    for (int i = 0; i < faIndexes.length; i++) {
      faOrder[faIndexes[i]] = i;
    }

    int computedS3bStart = tool.mModifiableNameSectionEnd;
    for (int p = 0; p < _modeledPlayerCount; p++) {
      final isFA = faOrder.containsKey(p);

      _firstNames.add(NameRef(
        playerIndex: p,
        isLastName: false,
        text: tool.GetPlayerFirstName(p),
        isFreeAgent: isFA,
        freeAgentListOrder: faOrder[p],
      ));
      _lastNames.add(NameRef(
        playerIndex: p,
        isLastName: true,
        text: tool.GetPlayerLastName(p),
        isFreeAgent: isFA,
        freeAgentListOrder: faOrder[p],
      ));

      for (final off in const [0, 4]) {
        final ptrLoc = p * _kPlayerDataLength + tool.FirstPlayerFnamePointerLoc + off;
        final dest = tool.GetPointerDestination(ptrLoc);
        if (dest >= tool.mStringTableStart &&
            dest < tool.mModifiableNameSectionEnd &&
            dest < computedS3bStart) {
          computedS3bStart = dest;
        }
      }
    }
    s3bStart = computedS3bStart;

    // Draft-class-range entries that actually live inside S3b (see the doc
    // comment on _modeledPlayerCount) — model them read-only so commit()'s
    // repack preserves them (retargeting their pointer to wherever they land)
    // instead of leaving an unmanaged, un-retargeted pointer whose fixed
    // relative offset can coincidentally alias newly-written content once
    // the pool is repacked. This must include empty-text entries too — an
    // empty one left un-retargeted is exactly what silently aliased a real
    // repacked string once the pool moved (confirmed reproducible against
    // the Roster fixture, not just theoretical): its old destination address
    // was empty at load time, but after repacking, something else legitimate
    // ended up written at that same address, making the untouched pointer
    // appear to newly "share" it with whatever field owns that string.
    for (int p = _modeledPlayerCount; p <= tool.mMaxPlayers; p++) {
      for (final off in const [0, 4]) {
        final ptrLoc = p * _kPlayerDataLength + tool.FirstPlayerFnamePointerLoc + off;
        final dest = tool.GetPointerDestination(ptrLoc);
        if (dest < s3bStart || dest >= tool.mModifiableNameSectionEnd) continue;
        final isLast = off == 4;
        final text = isLast ? tool.GetPlayerLastName(p) : tool.GetPlayerFirstName(p);
        (isLast ? _lastNames : _firstNames).add(NameRef(
          playerIndex: p,
          isLastName: isLast,
          text: text,
          isFreeAgent: false,
          freeAgentListOrder: null,
        ));
      }
    }
  }

  /// Only ever call this for Team/FreeAgent players (player < FirstDraftClassPlayer).
  /// Draft-class edits must go through the original SetPlayerFirstName/
  /// LastName(..., useExistingName) path instead — see player_names_apply.dart.
  void overlayEdit(int player, bool isLastName, String text) {
    assert(player < _modeledPlayerCount,
        'overlayEdit called for a draft-class player ($player) — draft-class '
        'edits must bypass PlayerNames entirely, see player_names_apply.dart');
    (isLastName ? _lastNames : _firstNames)[player].text = text;
  }

  int get requiredBytes {
    int sum = 0;
    for (final r in _firstNames) sum += (r.text.length + 1) * 2;
    for (final r in _lastNames) sum += (r.text.length + 1) * 2;
    return sum;
  }

  /// Hypothetical: what the pool would need if every exact-duplicate group
  /// (within each field) were collapsed to one copy — a display-only ceiling,
  /// independent of whether dedup has actually been planned/applied.
  int get requiredBytesAfterDedup {
    int sum = 0;
    for (final group in _groupByText(_firstNames).values) {
      sum += (group.first.text.length + 1) * 2;
    }
    for (final group in _groupByText(_lastNames).values) {
      sum += (group.first.text.length + 1) * 2;
    }
    return sum;
  }

  Map<String, List<NameRef>> _groupByText(List<NameRef> refs) {
    final map = <String, List<NameRef>>{};
    for (final r in refs) {
      map.putIfAbsent(r.text, () => []).add(r);
    }
    return map;
  }

  /// Lower = higher priority = more protected = preferred dedup owner.
  int _ownerPriorityScore(NameRef r) {
    if (r.isFreeAgent) return 1000000 + (r.freeAgentListOrder ?? 0);
    return 0;
  }

  NameRef _resolveOwner(NameRef r) {
    var cur = r;
    while (cur.dedupOwner != null) {
      cur = cur.dedupOwner!;
    }
    return cur;
  }

  /// Same-field-only duplicate detection (first names only match other first
  /// names; last names only match other last names — no cross-field
  /// matching). [targetBytes], if given, is the deficit to close; the
  /// returned plan greedily includes the largest-savings groups first and
  /// stops once satisfied. Omit it for the full best-case plan.
  DedupPlan planDedup({int? targetBytes}) {
    final candidateGroups = <DedupGroupPlan>[];
    for (final isLast in const [false, true]) {
      final refs = isLast ? _lastNames : _firstNames;
      for (final entry in _groupByText(refs).entries) {
        final members = List<NameRef>.from(entry.value);
        if (members.length < 2) continue;
        members.sort((a, b) => _ownerPriorityScore(a).compareTo(_ownerPriorityScore(b)));
        final canonical = members.first;
        final redirected = members.sublist(1);
        final savings = redirected.length * (entry.key.length + 1) * 2;
        candidateGroups.add(DedupGroupPlan(
          isLastName: isLast,
          text: entry.key,
          canonical: canonical,
          redirected: redirected,
          savingsBytes: savings,
        ));
      }
    }
    candidateGroups.sort((a, b) => b.savingsBytes.compareTo(a.savingsBytes));

    if (targetBytes == null) {
      final total = candidateGroups.fold<int>(0, (s, g) => s + g.savingsBytes);
      return DedupPlan(candidateGroups, total);
    }
    final selected = <DedupGroupPlan>[];
    int accumulated = 0;
    for (final g in candidateGroups) {
      if (accumulated >= targetBytes) break;
      selected.add(g);
      accumulated += g.savingsBytes;
    }
    return DedupPlan(selected, accumulated);
  }

  void applyDedup(DedupPlan plan) {
    for (final g in plan.groups) {
      for (final r in g.redirected) {
        r.dedupOwner = g.canonical;
      }
    }
  }

  /// First-name-only, free-agents-only (this phase), candidates >4 chars,
  /// longest name first (fewest players touched), tie-broken by
  /// last-listed-free-agent-first. [targetBytes] behaves as in [planDedup].
  TruncationPlan planTruncation({int? targetBytes}) {
    final candidates =
        _firstNames.where((r) => r.isFreeAgent && r.text.length > 4).toList();
    candidates.sort((a, b) {
      final lenCompare = b.text.length.compareTo(a.text.length);
      if (lenCompare != 0) return lenCompare;
      return (b.freeAgentListOrder ?? 0).compareTo(a.freeAgentListOrder ?? 0);
    });

    final entries = candidates.map((c) {
      final newText = '${c.text[0]}.';
      final savings = (c.text.length - 2) * 2;
      return TruncationEntry(
          ref: c, originalText: c.text, newText: newText, savingsBytes: savings);
    }).toList();

    if (targetBytes == null) {
      final total = entries.fold<int>(0, (s, e) => s + e.savingsBytes);
      return TruncationPlan(entries, total);
    }
    final selected = <TruncationEntry>[];
    int accumulated = 0;
    for (final e in entries) {
      if (accumulated >= targetBytes) break;
      selected.add(e);
      accumulated += e.savingsBytes;
    }
    return TruncationPlan(selected, accumulated);
  }

  void applyTruncation(TruncationPlan plan) {
    for (final e in plan.entries) {
      e.ref.text = e.newText;
    }
  }

  void _writeAbsolutePointer(int pointerLoc, int destination) {
    final value = destination - pointerLoc + 1;
    tool.SetByte(pointerLoc, value & 0xff);
    tool.SetByte(pointerLoc + 1, (value >> 8) & 0xff);
    tool.SetByte(pointerLoc + 2, (value >> 16) & 0xff);
    tool.SetByte(pointerLoc + 3, (value >> 24) & 0xff);
  }

  /// The single real write: lays out every remaining unique name string
  /// starting at [s3bStart], re-targets every player name pointer, then
  /// validates. Fully validates before writing anything — on failure,
  /// [tool]'s GameSaveData is left byte-for-byte untouched.
  CommitResult commit() {
    final owners = <NameRef>[];
    final seenOwners = <NameRef>{};
    final allRefs = [..._firstNames, ..._lastNames];
    for (final r in allRefs) {
      final owner = _resolveOwner(r);
      if (seenOwners.add(owner)) owners.add(owner);
    }

    int total = 0;
    for (final o in owners) {
      total += (o.text.length + 1) * 2;
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

    // Safety check: refuse if a pointer this class doesn't manage (coach
    // strings, college-institution names) currently resolves inside the pool
    // we're about to overwrite. Repacking would silently destroy that data
    // rather than just leave a stale pointer — coach strings live in S2
    // (always before S3b) so this should never fire for them in practice,
    // but college-institution names are confirmed (via GamesaveTool's own
    // _adjustCollegeEntryPointers bug-fix history) to sometimes land inside
    // this range in real files.
    //
    // Draft-class-range player pointers don't need an equivalent live
    // re-check here: any of them that already resolved into S3b *before*
    // this operation began was already found and modeled read-only by
    // _load()'s system-resident pass (so it gets safely repacked, not
    // refused), and any that a caller's edit newly points into S3b during
    // pass 1 (a draft-class row reusing an S3b string via useExistingName)
    // is correctly re-resolved by pass 2 after this repack, once the commit
    // that pass 2 depends on is allowed to succeed — see
    // player_names_apply.dart's two-pass design. A live re-read here would
    // wrongly refuse exactly that legitimate case, since it can't tell "was
    // already stale before we started" apart from "pass 1 just pointed it
    // here as part of this same, self-correcting edit".
    final overlaps = <String>[];
    for (int team = 0; team < 32; team++) {
      final coachRecBase = tool.GetPointerDestination(tool.GetCoachPointer(team));
      for (final off in const [0x0, 0x4, 0x8, 0xc, 0x10]) {
        final dest = tool.GetPointerDestination(coachRecBase + off);
        if (dest >= s3bStart && dest < tool.mModifiableNameSectionEnd) {
          overlaps.add('coach[$team] field@0x${off.toRadixString(16)} '
              '-> 0x${dest.toRadixString(16)}');
        }
      }
    }
    for (final entryLoc in tool.Colleges.values) {
      final dest = tool.GetPointerDestination(entryLoc);
      if (dest >= s3bStart && dest < tool.mModifiableNameSectionEnd) {
        overlaps.add('college entry@0x${entryLoc.toRadixString(16)} '
            '-> 0x${dest.toRadixString(16)}');
      }
    }
    if (overlaps.isNotEmpty) {
      return CommitResult(
        success: false,
        bytesUsed: total,
        bytesFree: budget - total,
        warnings: [
          'Refusing to commit: repacking would overwrite data this feature '
              'does not manage: ${overlaps.join('; ')}'
        ],
      );
    }

    // Write. Nothing above this point touched GameSaveData.
    int offset = s3bStart;
    for (final o in owners) {
      o.committedAddress = offset;
      for (int i = 0; i < o.text.length; i++) {
        tool.SetByte(offset, o.text.codeUnitAt(i) & 0xff);
        tool.SetByte(offset + 1, 0);
        offset += 2;
      }
      tool.SetByte(offset, 0);
      tool.SetByte(offset + 1, 0);
      offset += 2;
    }
    for (int i = offset; i < tool.mModifiableNameSectionEnd; i++) {
      tool.SetByte(i, 0);
    }

    for (final r in allRefs) {
      final ptrLoc =
          r.playerIndex * _kPlayerDataLength + tool.FirstPlayerFnamePointerLoc + (r.isLastName ? 4 : 0);
      _writeAbsolutePointer(ptrLoc, _resolveOwner(r).committedAddress!);
    }

    final warnings = <String>[];
    final dedupApplied = allRefs.any((r) => r.dedupOwner != null);
    if (!dedupApplied) {
      // checkNamePointers() returns true when it FOUND a problem (shared
      // pointers) — false means clean. A non-dedup commit should never
      // produce shared pointers, so a true here indicates a real bug.
      if (tool.checkNamePointers()) {
        warnings.add('checkNamePointers reported an issue after commit.');
      }
    }

    return CommitResult(
      success: true,
      bytesUsed: total,
      bytesFree: budget - total,
      warnings: warnings,
    );
  }
}
