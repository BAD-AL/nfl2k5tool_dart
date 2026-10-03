# NFL 2K5 SAVEGAME.DAT — Binary Section Reference

Primary reference is **Roster** mode. Franchise offsets are noted where they differ.
All values are hexadecimal. Ranges are inclusive (`start – end`).

---

## Save-Type Detection

The first 4 bytes of the file identify the save type.

| Magic bytes | ASCII | Save type |
|---|---|---|
| `52 4F 53 54` | `ROST` | Roster |
| anything else | — | Franchise |

---

## High-Level File Layout

| Section | Roster start | Roster end | Franchise start | Franchise end | Notes |
|---|---|---|---|---|---|
| Header / magic | `0x00000` | `0x00003` | `0x00000` | `0x00003` | 4-byte magic (see above) |
| Misc. metadata | `0x00004` | `0x041C7` | `0x00004` | `0x044A7` | Free-agent count, free-agent pointer, and other fixed counters (see Constants table) |
| Team blocks | `0x041C8` | `0x08047` | `0x044A8` | `0x08327` | 32 NFL teams × `0x1F4` bytes each (see Team Block layout) |
| Coach records | in misc. region | — | in misc. region | — | Fixed-size records pointed to by coach pointer in each team block |
| Unknown game data | `0x08048` | `0x0AFA7` | `0x08328` | `0x0B287` | Likely draft-pick state, trade records, other fixed data |
| Player data array | `0x0AFA8`¹ | `0x32D33` | `0x0B288` | `0x3AACB` | Fixed 84-byte (`0x54`) player records × 1,943 (Roster) / 2,317 (Franchise) |
| Depth charts + misc. game data | `0x32D34` | `0x75960` | `0x3AACC` | `0x75C40` | Depth-chart orders for all 32 teams + special teams; schedule; other game state |
| String table | `0x75960` | `0x88D8F` | `0x75C40` | `0x8906F` | 78,896 bytes — subdivided into S1a / S2 / S3a / S3b (see String Table section) |
| Unknown / padding | `0x88D90` | `0x8B7CF` | `0x8906F` | `0x8BAB0` | ~10,816 bytes — contents not yet fully mapped |
| College player names | `0x8B7D0` | `0x8F00F` | `0x8BAB0` | `0x8F2EF` | Read-only UTF-16LE college player name strings; referenced by player records via signed relative pointers |
| Franchise schedule year | — | — | `0x917EF` | `0x917EF` | 1 byte — current year offset from 2000 (also bytes[4] of the first game record) |
| Franchise live schedule | — | — | `0x917EB` | ~`0x09239A` | 22 weeks × 136 bytes — regular season (wks 1–17) + playoffs (wks 18–22). Same 8-byte game record format as `.nfl2k5` files: `[home, away, month, day, year, hour, min, played_flag]`. Wild Card at `0x0920F3`, Divisional at `0x09217B`, Championship at `0x092203`, Pro Bowl at `0x09228B`, Super Bowl at `0x092313`. |

¹ `mPlayerStart` defaults to `0xAFA8` for the base roster. Community-edited rosters (e.g. Flying Finn) may use `0xAFF0`.

---

## Team Block Layout (per-team entry, stride `0x1F4` = 500 bytes)

Base address of team `i`: `m49ersPlayerPointersStart + i × 0x1F4`

| Offset within block | Size | Field | Notes |
|---|---|---|---|
| `+0x000` | 4 × N bytes | Player pointer array | Signed 32-bit LE relative pointers to player records. `N` = number of players on this team |
| `+0x104` | 4 bytes | S3a nickname pointer | Signed 32-bit LE relative pointer to this team's S3a string block (Nickname is the first field) |
| `+0x118` | 1 byte | Stadium index | Index into the S1a stadium list (0–85+). Used to look up stadium name and city |
| `+0x14C` | 4 bytes | Coach pointer | Signed 32-bit LE relative pointer to this team's coach record |
| `+0x154` | 1 byte | Logo / PBP index | Same numeric value as stadium index for all 32 NFL teams. Also stored as a 2-char decimal UTF-16LE string in S3a field 2 (kept in sync on write) |
| `+0x156` | 30 bytes | Uniform year data | 15 × uint16 LE — start/end year pairs for each selectable jersey uniform, matching the uniform selection list order |
| `+0x192` | 1 byte | Default jersey index | 0-based index into this team's jersey selection list. Variable count per team (up to 15 entries for some teams) |
| `+0x194` | 1 byte | Holder (FG/PAT) | Roster-local index (into this team's player pointer array, `+0x000`) of the field-goal/PAT holder. See "Special Teamer Slots" below |
| `+0x195` | 1 byte | Kick returner 1 (KR1) | Roster-local index of the primary kick returner |
| `+0x196` | 1 byte | Kick returner 2 (KR2) | Roster-local index of the backup kick returner |
| `+0x197` | 1 byte | Placekicker (PK) | Roster-local index of the placekicker |
| `+0x198` | 1 byte | Long snapper (LS) | Roster-local index of the long snapper |
| `+0x199` | 1 byte | Punt returner (PR) | Roster-local index of the punt returner |

**Free Agents** player pointer list is not stored in a team block; its location is read from `mFreeAgentPlayersPointer` (see Constants).

### Special Teamer Slots (`+0x194`–`+0x199`)

Six contiguous 1-byte slots, each holding a **roster-local index** (an index
into that team's player pointer array at `+0x000`, *not* a global player
index) of the player assigned to that special-teams role. `GamesaveTool`
models these as the `SpecialTeamer` enum (`Holder`, `KR1`, `KR2`, `PK`,
`LS`, `PR`) and exposes them via `GetSpecialTeamPosition`/
`SetSpecialTeamPosition`, editable as `Holder,POS#` / `KR1,POS#` / etc.
lines in the text format (see `InputParser.SetSpecialTeamPlayer`).

`PK` is named that (not `K`) deliberately: a player-data line's first field
is that player's Position, so a kicker's own row literally starts with
`K,` — using `K,` as a text-format dispatch prefix would hijack every
kicker's row. `Holder,` has no such collision (no position is named
"Holder").

**Holder confirmed against the stock 2004 roster** (`Base2004Fran_un-modded.zip`):
checked all 32 teams' `+0x194` byte against each team's starting punter.
17/32 teams use the punter as holder; the rest use a backup QB (14/32,
e.g. Bears → Craig Krenzel, Broncos → Danny Kanell), one uses the
*starting* QB (Seahawks → Matt Hasselbeck), and one uses a 3rd-string WR
(Rams → Dane Looker) — i.e. it is a genuinely independent, per-team
assignment, not simply "whoever is the punter." `KR1`/`KR2`/`LS`/`PR` were
already known (used by `AutoUpdateSpecialTeams`); `PK`'s offset was found
by scanning the byte window around the known special-teamer slots and
checking which offset resolves to the team's kicker in all 32/32 teams.

**Holder is not duplicated/derived elsewhere in the file.** The "Depth
charts + misc. game data" region noted in the High-Level File Layout table
(`0x32D34`–`0x75960` Roster / `0x3AACC`–`0x75C40` Franchise) is a large,
still-unmapped catch-all whose description ("depth-chart orders... +
special teams; schedule; other game state") was speculative, not verified.
Confirmed it holds no mirror of these bytes by loading the same file into
two `GamesaveTool` instances, changing only one team's Holder via
`SetSpecialTeamPosition`, and diffing the two in-memory buffers byte for
byte across the entire ~720KB file: exactly one byte differed, at the
expected team-block offset (`0x4830` for the Bears in
`Base2004Fran_Orig.zip`). Nothing in that other region moved. The same
reasoning applies to `KR1`/`KR2`/`PK`/`LS`/`PR` (same storage mechanism,
same block).

`AutoUpdateDepthChart()` (→ `AutoUpdateSpecialTeams` per team) now also
sets `Holder` to the team's punter automatically, alongside its existing
`KR1`/`KR2`/`PR`/`LS` auto-assignment -- a sensible default given 17/32
stock teams already use the punter, and every team has exactly one punter
to fall back on (unlike "fastest returner," which needs a speed
comparison).

---

## Team Season Stats (within Team Block, offset `+0x1AA`)

A 74-byte (`0x4A`) block of accumulating season stats lives at the very end of each team's `0x1F4`-byte team block, running to the next team's block boundary. All values are zero in a fresh franchise file and accumulate as games are simulated. Verified byte-for-byte by diffing a franchise save from before any games were played against the same save after one week of games were simulated, cross-checked against the in-game stat viewer's actual week-1 numbers for two teams (49ers, Chargers) with materially different stat lines — every identified field below matched exactly for both teams.

Base address of team `i`'s stats block: `m49ersPlayerPointersStart + i × 0x1F4 + 0x1AA`

| Offset (rel. to team block) | Size | Field |
|---|---|---|
| `+0x1AA` | 2 B LE | Passing yards |
| `+0x1AC` | 2 B LE | Rushing yards |
| `+0x1AE` | 2 B LE | Passing yards allowed |
| `+0x1B0` | 2 B LE | Rushing yards allowed |
| `+0x1B2` | 2 B LE | Number of pass plays |
| `+0x1B4` | 2 B LE | Number of rush plays |
| `+0x1B6` | 2 B LE | 1st downs |
| `+0x1B8` | 2 B LE | 2-point conversion attempts |
| `+0x1BA` | 2 B LE | 2-point conversions made |
| `+0x1BC` | 2 B LE | 3rd down attempts |
| `+0x1BE` | 2 B LE | 3rd downs made |
| `+0x1C0` | 2 B LE | 4th down conversion attempts |
| `+0x1C2` | 2 B LE | 4th downs made |
| `+0x1C4` | 2 B LE | Red zone attempts |
| `+0x1C6` | 2 B LE | Red zone TDs |
| `+0x1C8` | 2 B LE | Red zone FGs |
| `+0x1CA` | 2 B LE | Defensive red zone attempts allowed |
| `+0x1CC` | 2 B LE | Red zone TDs allowed |
| `+0x1CE` | 2 B LE | Red zone FGs allowed |
| `+0x1D0` | 2 B LE | Number of penalties |
| `+0x1D2` | 2 B LE | Total yards penalized |
| `+0x1D4` | 2 B LE | Turnovers |
| `+0x1D6` | 2 B LE | Points off turnovers |
| `+0x1D8` | 2 B LE | Total points scored |
| `+0x1DA` | 2 B LE | Total points allowed |
| `+0x1DC – +0x1F2` | 2 B LE × 12 | *Unidentified* — confirmed to change after games are played (non-zero, differs between teams) but not yet matched against real values. Likely candidates: FG/XP made & attempted, sacks, interceptions thrown, fumbles lost, safeties |

The block ends exactly at `+0x1F4`, where the next team's block (player pointer array) begins — confirmed by an unchanged value straddling that boundary in both the before and after snapshots.

---

## Player Record Layout (84 bytes / `0x54` per player)

Base address of player `i`: `mPlayerStart + i × 0x54`

| Offset | Size | Field group |
|---|---|---|
| `+0x00` | 4 bytes | First-name pointer (signed 32-bit LE relative → string in S3b) |
| `+0x04` | 4 bytes | Last-name pointer (signed 32-bit LE relative → string in S3b) |
| `+0x08` | varies | Ability ratings (speed, agility, strength, …) |
| `+0x10` | 4 bytes | First-name pointer (duplicate or college section ptr) |
| varies | varies | Appearance attributes (skin, face, college index, …) |

Pointer formula: `destination = pointerLocation + signedValue − 1`
Negative pointer values point backwards (e.g. into the college name section).

**Draft class:** Players at indices `1937–1942` (Roster, 6 slots) or `1937–2316` (Franchise, 380 slots) are the draft-class players.

---

## Player Stats Pointer (within Player Record, offset `+0x2C`)

Byte `+0x2C` of each player's 84-byte record is a signed 32-bit relative pointer (same formula as the name pointers above) to that player's stats block — game-by-game *and* full career history, embedded directly in the save file. Unlike every other structure in this document, this block is **not** fixed-size — it's a variable-length list of 4-byte `(value: uint16, tag: uint16)` pairs, and the pointer itself changes week to week as the block is reallocated.

A ready-to-use extraction tool lives at `bin/player_stats.dart` (`dart run bin/player_stats.dart <gamesave-file> --player "First Last"`) — see its header comment for full usage.

### Zone structure

The pair list divides into contiguous **128-wide zones** by `tag ~/ 128` — one zone per season of the player's career, in chronological order, with the **highest-numbered zone always being the current (possibly in-progress) season**. The zone index is not arbitrary: it equals the player's career year number. Confirmed via zone counts matching real NFL experience: Drew Bledsoe (entered the league 1993) has exactly 11 completed zones plus a 12th current one in a 2004 save; Curtis Conway (entered 1993 also) likewise has 11 completed zones; Carson Palmer (essentially a rookie in 2004) has none; a likely-2001 Bledsoe zone shows `Games=2`, matching his real injury-shortened season.

Within one zone, offsets are relative to that zone's first `tag`:

| Rel. offset | Field |
|---|---|
| `+0` | Games played |
| `+1` | Rush attempts |
| `+2` | Rush yards |
| `+3` | Rush TDs |
| `+4` | Fumbles (well confirmed for single-game data; less certain for season totals) |
| `+5` | Unidentified — usually absent |
| `+6` | Pass attempts |
| `+7` | Completions |
| `+8` | Passing yards |
| `+9` | Passing TDs |
| `+10` | Interceptions (thrown, offense) |
| `+11` | Sacks taken (offense) |
| `+12` | Receptions |
| `+13` | Receiving yards |
| `+14` | Receiving TDs |
| `+16` | Longest rush |
| `+17` | Longest reception |
| `+18` | Tackles — may include special-teams tackles for some players; one observed case (a linebacker) didn't match his defense-only tackle count while every other confirmed field for that player matched |
| `+19` | Sacks made (defense) — stored at **half-sack precision**: the raw value is 2× the real stat (e.g. 7 sacks is stored as 14) |
| `+20` | Passes intercepted (defense) |
| `+21` | Forced fumbles |
| `+22` | Fumbles recovered |
| `+23` | Defensive TDs — any TD scored off a takeaway or return, for a player of **any** position (e.g. a receiver's fumble-recovery-return TD counts here too) |
| `+24` | Interception-return TDs specifically — a subset of `+23`. When both are present but differ, the difference is the count of non-interception defensive TDs (fumble return, etc.) |
| `+25` | PATs made |
| `+26` | PATs attempted |
| `+32` | Punts |
| `+33` | Punt yards |
| `+34` | Punts inside the 20 |
| `+46` | Longest pass. Absent on the most-recently-completed season in one observed case, replaced by a distinct large sentinel tag instead |
| `+48` | Broken tackles |
| `+51` | Tackles for loss |
| `+52` | Assist(ed) tackles |
| `+53` | Sack yards |
| `+54` | Passes defensed |
| `+55` | Interception return yards (defense) — sum across all interceptions that game, confirmed via a 2-interception game (26 total from two returns) |
| `+56` | Interception return long (defense) — the longest single return, not a sum, confirmed via the same 2-interception game (20, the longer of the two, not 26) |
| `+58` | Field goals blocked |
| `+61` / `+62` | FGs made / attempted, 1–29 yards |
| `+63` / `+64` | FGs made / attempted, 30–39 yards |
| `+65` / `+66` | FGs made / attempted, 40–49 yards |
| `+67` / `+68` | FGs made / attempted, 50+ yards (pattern-inferred from the other three distance buckets — not directly confirmed, and one known gap: a real 50+ attempt for one confirmed season didn't appear at this offset) |
| `+69` | Points scored via defensive/return TDs — 6 points per `+23` TD (confirmed: 1 TD → 6, 2 TDs → 12) |
| `+71` | Punt touchbacks — confirmed for 2 of 3 known real seasons; missing where expected in the 3rd (same kind of gap as the `+67`/`+68` FG-50+ case above) |

Total FGs made/attempted are **not** stored anywhere directly — they're just the sum of the four distance-bucket pairs above (confirmed: Todd Peterson's real season FGM/FGA totals matched the bucket sums exactly across three years).

**Documented unknown: `+83`/`+84`/`+85`.** Small values (usually 1, occasionally 2), seen scattered across defensive players in the current (2004) season only. Two theories were tested and ruled out:
- "Correlates with having an interception that game" — contradicted by a full-season case with 8 interceptions spread across multiple season-zones where the field never appeared.
- "Represents safeties" — directly ruled out via Kevin Carter, whose real 1995 season (confirmed via Pro Football Reference to include a safety) is fully seeded in this save with correct real tackles/sacks/assists/etc. for that year, yet shows none of `+83`/`+84`/`+85` — if this were a real historically-seeded safety count, it should have appeared there.

The value sometimes appears directly in the current season's own zone, and sometimes in a separate zone at a fixed `current + 32` offset (occasionally both, with different values in each) — this second location was also observed once holding data completely disconnected from a player's normal sequential season numbering, appearing as a highly-numbered "stray zone." Whatever this represents, it appears to be populated only by live simulation of the current season, not seeded from the game's historical data — so further identification will likely require some way to observe what actually happened during a specific simulated game (a play-by-play log or box score not yet located), rather than comparison against real-world stats.

All fields above are confirmed by matching real player stats: passing/rushing via Drew Bledsoe's real 2002 and 2003 season lines (every field matched exactly) and Tim Rattay's real week-1 game line (sacks, longest rush, longest pass, fumbles); receiving via Curtis Conway's real 2002/2003/2004 season lines (receptions, yards, TDs all matched exactly across three separate years) and via Kevan Barlow/Rudi Johnson/Anthony Thomas's real week-1 broken-tackle counts; defense via Julian Peterson's real 2002/2003/2004 season lines (tackles, sacks made, passes intercepted, forced fumbles, interception return yards all matched exactly across three separate years), a week-1 2004 cross-team defensive box score covering Julian Peterson, Derek Smith, Jeff Ulbrich, Ahmed Plummer (49ers), Nick Barnett (Packers), Mike Doss (Colts), Darren Woodson (Cowboys), and Mike Brown (Bears) (tackles for loss, assists, sack yards, passes defensed, and interception return long all confirmed across multiple players), and full 2004-season lines for Jerry Rice (a non-defensive player's defensive-TD-via-fumble-recovery) and Brian Dawkins (8 interceptions, 2 defensive TDs of which 1 was interception-specific) that separated `+23` from `+24` and confirmed `+22` and `+69`; kicking via Todd Peterson's real 2002/2003/2004 season lines (PATs and all four FG distance buckets matched almost exactly across three separate years); punting via Brad Maynard's real 2002/2003/2004 season lines (punts, punt yards, and inside-20 matched exactly across three separate years; touchbacks matched in 2 of 3).

A season's field is omitted entirely (not stored as zero) when its value is 0 that season — this is why different players' zones show different sets of fields present.

Occasional sentinel values (`0xFFFF`, or large tags ≥ 30000 terminating a player's list) appear and don't represent real data — `player_stats.dart` filters the former to `n/a` and separates the latter out under `--raw`.

**Identifying the current season on a save file with multiple weeks/seasons played:** "current" must be the highest-numbered zone that actually has a `+0` (Games) field, not simply the numerically highest zone — the fixed, non-sequential zone mentioned above (e.g. zone 37) can have a higher number than the real current season without being a real season at all, and naively picking the max zone would mask the real data. `bin/player_stats.dart` implements this correctly.

Unresolved: `+5` and the exact conditions under which `+46` is replaced by a sentinel; the "current game" schema is otherwise identical to a completed-season zone.

---

## String Table — Subsection Breakdown

The string table is 78,896 bytes in both modes. It is subdivided into four contiguous subsections.

| Subsection | Mnemonic | Roster start | Franchise start | Length | Mutability | Contents |
|---|---|---|---|---|---|---|
| Stadium names | **S1a** | `0x75960` | `0x75C40` | dynamic (to S2 start) | Read-only via tool | UTF-16LE stadium entries. Each entry: short name, city, stadium code (`sNN`), long name. Scanned once at load to build stadium index |
| Coach strings | **S2** | dynamic¹ | `0x780DE` | `0x14B1` (5,297 B) | Grow/shrink (shift) | 32 coaches × up to 5 strings: FirstName, LastName, Info1, Info2, Info3 (UTF-16LE, null-terminated). Section is **completely full** in the base franchise file — growing any string silently truncates the tail |
| Team strings | **S3a** | after S2 | after S2 | fixed per file | Same-or-shorter only | 32 teams × 5 fixed-length UTF-16LE fields in order: `[0]` Nickname (e.g. "49ers"), `[1]` Abbrev (e.g. "SF"), `[2]` LogoNumStr (2-char decimal matching stadium/logo index, e.g. "25"), `[3]` City (e.g. "San Francisco"), `[4]` AbbrAlt (e.g. "SF"). Shorter writes are right-padded with spaces to preserve length. Growing is rejected with `AddError` |
| Player names | **S3b** | after S3a | after S3a | to `mModifiableNameSectionEnd` | Grow/shrink (shift) | Player first + last names (UTF-16LE, null-terminated). Overflow guard: writes that would exceed `mModifiableNameSectionEnd` are rejected with `AddError` and the name is left unchanged |

¹ S2 start in Roster mode = destination of coach 0's FirstName pointer (dynamic, computed at load time).

**S2 pointer adjustment:** After any grow/shrink in S2, `AdjustCoachStringPointers()` updates all 32 coaches' 5 string pointers. After any grow/shrink in S3b, `AdjustPlayerNamePointers()` updates all player first/last-name pointers.

---

## Playbook Table

An absolute table of 32 × 8-byte entries, one per team in the same order as the team blocks.

| Mode | Base address |
|---|---|
| Roster | `0x29B0` |
| Franchise | `0x2C90` |

Each entry is two consecutive 4-byte signed relative string pointers:

| Offset within entry | Size | Field | Resolves to |
|---|---|---|---|
| `+0x0` | 4 bytes | Offense pointer | Full playbook name string, e.g. `"49ers"`, `"West Coast"` |
| `+0x4` | 4 bytes | Defense pointer | Short playbook abbreviation string, e.g. `"SF"`, `"WCO"` |

Both pointers use the standard formula: `destination = pointerLocation + signedValue − 1`.

The playbook name strings are stored consecutively in the string table immediately after the S1a stadium block. The 32 team-named playbooks are followed by 4 generic entries:

| Token | Offense name | Abbrev |
|---|---|---|
| `PB_West_Coast` | `West Coast` | `WCO` |
| `PB_General` | `General` | `GEN` |
| `PB_User_A` | `User A` | `UA` |
| `PB_User_B` | `User B` | `UB` |

**Stored pointer values differ per team slot** even when multiple teams share the same playbook, because the pointer is relative to each slot's own address. The tool builds a name→address lookup at load time by walking the string table from team 0's offense pointer address.

---

## Coach Record Layout (offsets within the coach record)

Pointed to by the coach pointer in each team block.

| Offset | Size | Field | Notes |
|---|---|---|---|
| `+0x00` | 4 B | FirstName ptr | → S2 string |
| `+0x04` | 4 B | LastName ptr | → S2 string |
| `+0x08` | 4 B | Info1 ptr | → S2 string |
| `+0x0C` | 4 B | Info2 ptr | → S2 string |
| `+0x10` | 4 B | Info3 ptr | → S2 string |
| `+0x18` | 1 B | Body | Coach model enum index |
| `+0x1C` | 2 B | SeasonsWithTeam | Little-endian |
| `+0x1E` | 2 B | TotalSeasons | Little-endian |
| `+0x20` | 2 B | Wins | Little-endian |
| `+0x22` | 2 B | Losses | Little-endian |
| `+0x24` | 2 B | Ties | Little-endian |
| `+0x30` | 2 B | WinningSeasons | Little-endian |
| `+0x32` | 2 B | SuperBowls | Little-endian |
| `+0x34` | 2 B | PlayoffWins | Little-endian |
| `+0x36` | 2 B | PlayoffLosses | Little-endian |
| `+0x38` | 2 B | SuperBowlWins | Little-endian |
| `+0x3A` | 2 B | SuperBowlLosses | Little-endian |
| `+0x40` | 2 B | Photo | Little-endian; displayed as 4-digit zero-padded string |
| `+0x42` | 1 B | Overall | |
| `+0x43–0x58` | 1 B each | Rating fields | QB, RB, OL, DL, LB, DB, ST, Motivation, Discipline, Professionalism, OffScheme, DefScheme |
| `+0x59` | 1 B | PlaycallingRun | |
| `+0x5A–0x82` | 41 B | Playcalling data | Non-zero; formation percentages |
| `+0x83` | 1 B | ShotgunRun / IFormRun | **Shared offset** — setting one sets the other |
| `+0x87` | 1 B | SplitbackRun / EmptyRun | **Shared offset** — setting one sets the other |
| `+0x88–0x8C` | 1 B each | ShotgunPass, IFormPass, SplitbackPass, EmptyPass | |

---

## Key Constants

| Constant | Roster | Franchise | Description |
|---|---|---|---|
| `m49ersPlayerPointersStart` | `0x041C8` | `0x044A8` | Base address of team 0 (49ers) block |
| `m49ersNumPlayersAddress` | `0x042E4` | `0x045C4` | Address of team 0 player count |
| `mCoachPointerOffset` | `0x14C` | `0x14C` | Offset within team block to coach pointer |
| `_cTeamDiff` | `0x1F4` | `0x1F4` | Stride between consecutive team blocks |
| `_cTeamDataPtrOffset` | `0x104` | `0x104` | Offset within team block to S3a nickname pointer |
| `_cTeamStadiumByteOffset` | `0x118` | `0x118` | Offset within team block to stadium index byte |
| `_cTeamLogoByteOffset` | `0x154` | `0x154` | Offset within team block to logo/PBP index byte (= stadium index for all NFL teams; also stored in S3a[2]) |
| `_cTeamDefaultJerseyOffset` | `0x192` | `0x192` | Offset within team block to default jersey index byte |
| `_cPlaybookTableBase` | `0x29B0` | `0x2C90` | Base of playbook pointer table (absolute); stride 8 bytes per team |
| `mFreeAgentPlayersPointer` | `0x007C` | `0x035C` | Address of free-agent player-list pointer |
| `mFreeAgentCountLocation` | `0x0078` | `0x0358` | Address of free-agent player count |
| `mPlayerStart` | `0x0AFA8`¹ | `0x0B288` | Address of first player record |
| `_cPlayerDataLength` | `0x54` | `0x54` | Bytes per player record |
| `mMaxPlayers` | `1943` | `2317` | Total player slots (including free agents + draft class) |
| `FirstDraftClassPlayer` | `1937` | `1937` | Player index of first draft-class slot |
| `mStringTableStart` | `0x75960` | `0x75C40` | Start of string table (= S1a start) |
| `mStringTableEnd` | `0x88D80` | `0x94D10` | End of string data |
| `mModifiableNameSectionEnd` | `0x88D8F` | `0x8906F` | Hard overflow boundary for S3b player-name writes |
| `mCoachStringSectionLength` | `0x14B1` | `0x14B1` | Size of S2 coach string section in bytes |
| `mCollegePlayerNameSectionStart` | `0x8B7D0` | `0x8BAB0` | Start of read-only college name strings |
| `mCollegePlayerNameSectionEnd` | `0x8F00F` | `0x8F2EF` | End of read-only college name strings |
| `FranchiseGameOneYearLocation` | — | `0x917EF` | 1-byte current year (2000 + value) |

¹ `0xAFF0` for community-edited rosters (Flying Finn format) where the player array is shifted by `0x48` bytes.
