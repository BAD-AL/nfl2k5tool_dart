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
| Franchise schedule year | — | — | `0x917EF` | `0x917EF` | 1 byte — current year offset from 2000 |

¹ `mPlayerStart` defaults to `0xAFA8` for the base roster. Community-edited rosters (e.g. Flying Finn) may use `0xAFF0`.

---

## Team Block Layout (per-team entry, stride `0x1F4` = 500 bytes)

Base address of team `i`: `m49ersPlayerPointersStart + i × 0x1F4`

| Offset within block | Size | Field | Notes |
|---|---|---|---|
| `+0x000` | 4 × N bytes | Player pointer array | Signed 32-bit LE relative pointers to player records. `N` = number of players on this team |
| `+0x104` | 4 bytes | S3a nickname pointer | Signed 32-bit LE relative pointer into the S3a team-string section |
| `+0x14C` | 4 bytes | Coach pointer | Signed 32-bit LE relative pointer to this team's coach record |
| `+0x1C4`² | 1 byte | Stadium index (primary) | Index into the stadium list; maps to S1a stadium entry |
| `+0x1C8`² | 1 byte | Stadium index (copy) | Duplicate stadium byte kept in sync |

² Exact stadium byte offsets — see `_cTeamStadiumByteOffset` in `gamesave_tool.dart`.

**Free Agents** player pointer list is not stored in a team block; its location is read from `mFreeAgentPlayersPointer` (see Constants).

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

## String Table — Subsection Breakdown

The string table is 78,896 bytes in both modes. It is subdivided into four contiguous subsections.

| Subsection | Mnemonic | Roster start | Franchise start | Length | Mutability | Contents |
|---|---|---|---|---|---|---|
| Stadium names | **S1a** | `0x75960` | `0x75C40` | dynamic (to S2 start) | Read-only via tool | UTF-16LE stadium entries. Each entry: short name, city, stadium code (`sNN`), long name. Scanned once at load to build stadium index |
| Coach strings | **S2** | dynamic¹ | `0x780DE` | `0x14B1` (5,297 B) | Grow/shrink (shift) | 32 coaches × up to 5 strings: FirstName, LastName, Info1, Info2, Info3 (UTF-16LE, null-terminated). Section is **completely full** in the base franchise file — growing any string silently truncates the tail |
| Team strings | **S3a** | after S2 | after S2 | fixed per file | Same-or-shorter only | 32 teams × 5 fixed-length fields: Nickname, City, Abbreviation, StadiumNum, Conference (UTF-16LE). Shorter writes are right-padded with spaces to preserve length. Growing is rejected with `AddError` |
| Player names | **S3b** | after S3a | after S3a | to `mModifiableNameSectionEnd` | Grow/shrink (shift) | Player first + last names (UTF-16LE, null-terminated). Overflow guard: writes that would exceed `mModifiableNameSectionEnd` are rejected with `AddError` and the name is left unchanged |

¹ S2 start in Roster mode = destination of coach 0's FirstName pointer (dynamic, computed at load time).

**S2 pointer adjustment:** After any grow/shrink in S2, `AdjustCoachStringPointers()` updates all 32 coaches' 5 string pointers. After any grow/shrink in S3b, `AdjustPlayerNamePointers()` updates all player first/last-name pointers.

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
