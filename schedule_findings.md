# Schedule Format Findings

Analysis of `schedule_bin/NFL2017-18.nfl2k5` and `lib/scheduler_helper.dart`.

---

## Binary Format

### Game Record (8 bytes)

Each game is a fixed 8-byte struct (matches `enum Game` in `enum_definitions.dart`):

```
[0] home_team    – team index (0x00–0x1F, 0xFF = null)
[1] away_team    – team index
[2] month        – calendar month (1=Jan, 9=Sep, etc.)
[3] day          – day of month
[4] year_2digit  – two-digit year (e.g. 0x11 = 2017)
[5] hour_of_day  – hour (not confirmed for 2017 file, see Year notes)
[6] minute       – minute of hour
[7] null_byte    – always 0x00 in real games; becomes 0x07 when the NEXT
                   slot is a bye/null (see Null Game Sentinel below)
```

### Week Structure

Each week occupies exactly **136 bytes**:
```
[16 game slots × 8 bytes] + [1 separator slot × 8 bytes]
```

The separator slot is never read as a game by the code. Its purpose is
purely to provide 8 bytes of spacing so weeks are evenly spaced, and to
carry the `0x07` sentinel that the null-game check depends on.

### File Layout

Both `NFL2017-18.nfl2k5` and `NFL2004-05.nfl2k5` are **2992 bytes**.

| | 2004 file | 2017 file |
|---|---|---|
| `WeekOneStartLoc` | 2 (2-byte header: `00 00`) | **0 (no header)** |
| Separator pattern | `00 00 00 00 00 00 00 00` | `07 00 00 00 00 00 00 00` |
| Schedule data | 17 wks × 136 = 2312 B | 17 wks × 136 = 2312 B |
| Trailing padding | 678 B (84 slots) | **680 B (85 slots)** |

**Notable:** The 2017 file has NO 2-byte header — `WeekOneStartLoc` must be
set to `0` (not `2`) when loading it. The `_mScheduleFileWeekOneStartLoc = 2`
constant in the Dart code would be wrong for this file.

---

## Separator / Null Game Sentinel

### The `0x07` Sentinel Mechanism

The comment in the code calls the separator `0x0007000000000000`. In
practice the first byte of the separator slot is `0x07` — making the slot
read as "cardinals (7) at 49ers (0)" if decoded naively. This is how it
works:

- `GameLocation(week, gameOfWeek)` returns the byte offset of each game slot.
- `GameLocation(week, 16)` returns the separator slot (one past the last game).
- `GetGame()` detects a bye by checking `data[location - 1] == 0x07`.

For the separator at offset `S` (= `GameLocation(w, 16)`):
```
data[S-1] = last byte of game slot 15 (the NullByte field) = 0x07
```
This `0x07` comes from the separator slot itself starting with `07`, so
`data[S-1]` = last byte of the real game = ... wait, actually:

**Real mechanism** (from `ScheduleGameByIndex` null path):
```dart
location -= 2;
Tool.SetByte(location + 0, 0x00);  // overwrites minute of prev slot
Tool.SetByte(location + 1, 0x07);  // overwrites null_byte of prev slot  ← sentinel!
Tool.SetByte(location + 2..7, 0x00); // zeroes home, away, month, day, year, hour of this slot
```
The write at `location - 2` places `0x07` at `location - 1`, which is
byte [7] (NullByte) of the *previous* game slot. `GetGame` checks
`data[location - 1] == 0x07` which fires correctly.

For the **week separator slot** (game index 16), the `07` in the first
byte of the separator fulfils the same role for the *next* slot written
past it (if any).

### Bye Week Slots

Weeks 3–10 of the 2017 schedule each have **2 null/bye slots** (14 real
games + 2 byes). This matches the actual 2017 NFL regular season bye week
pattern (4 teams on bye = 2 missing games per week in the middle of the
season). The file correctly encodes this.

---

## Decoding the 2017 vs 2004 Season Structure

```
Week  1: 16 real,  0 byes   (both years)
Week  2: 16 real,  0 byes
Weeks 3-10: 14 real, 2 byes (bye-week teams have null slots)
Weeks 11-17: 16 real, 0 byes
```

Both files follow the **same structural template**: 16 slots per week
regardless of byes (null slots fill the gaps). This matches the
`mGamesPerWeek = [16, 16, 16, ...]` array in the code.

---

## Year Field Anomaly in 2017 File

The year values (`slot[4]`) in the 2017 file are inconsistent — only
weeks around October/November show `0x11` (= 2017). Weeks 1–2 show years
like `0x09` (2009), `0x13` (2019), etc. The month/day dates themselves
appear to be correctly mapped to the 2017 NFL calendar. The year anomaly
may be a quirk of the tool that built the file (possibly a year-offset
calculation bug, or a franchise-year vs. calendar-year mismatch).

---

## Adding More Games Per Week

### Current Hardcodes

Two places in the code need to change to support more games per week:

1. **`mGamesPerWeek`** (scheduler_helper.dart line 78):
   ```dart
   final List<int> mGamesPerWeek = [16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16];
   ```
   All 17 entries are 16. This drives `GameLocation()`, `GetWeek()`, and
   `CloseWeek()`.

2. **`ReLayoutScheduleWeeks`** (line 377):
   ```dart
   List<int> gamesPerWeek = [16, 16, 14, 14, 14, 14, 14, 14, 14, 14, 16, 16, 16, 16, 16, 16, 16];
   ```
   This is the *redistribution* table used when normalizing a text
   schedule input. It correctly accounts for bye-week weeks having fewer
   matchups, but it is **separate** from `mGamesPerWeek`.

### Is It Possible in the Binary?

**Yes, the binary format supports variable games per week.** There is no
fixed-size record or magic number that locks the file to 16 games. The
structure is positional — `GameLocation()` computes byte offsets from the
`mGamesPerWeek` table. Changing the table changes where every game lives.

For a **17-game NFL season** (like 2021+), the weekly footprint would
increase:
```
17 games × 8 bytes + 8 byte separator = 144 bytes/week
18 weeks × 144 bytes = 2592 bytes  (vs 2312 currently)
```
The existing 2992-byte file has 680 bytes of trailing padding, giving
**85 unused game slots** — comfortably enough to fit an extra game in
each week of an 18-week season without resizing the file.

### Step-by-Step Change Required in Dart

To support e.g. 17 games per week over 18 weeks:

1. Change `mGamesPerWeek` to 18 entries of 17:
   ```dart
   final List<int> mGamesPerWeek = [17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17];
   ```
2. Update `ReLayoutScheduleWeeks` to use the matching redistribution
   table for the target season (e.g. 2021 bye schedule).
3. Remove or raise the 256-game warning in `ScheduleGameFromLine` (17 × 18
   = 306 games total).
4. If applying to a franchise file, check that the franchise schedule
   region has enough room (the standalone `.nfl2k5` file clearly does).

### Big Unknown: The Game Engine

The tool can write a schedule with more games per week, but **NFL 2K5
itself reads the schedule using its own hardcoded lookup table** that
almost certainly matches the original 2004 season (16 games/week, 17
weeks). Writing 17 game slots per week will likely cause the game to
misread the schedule — it will use the wrong byte offsets for weeks 2+
and display garbled matchups.

Whether the game engine uses the same positional formula as the Dart code
(and therefore can be made to work by understanding where the game reads
from) or whether it has a fully hardcoded schedule table is unknown
without disassembly of the game binary.

---

## Summary of Key Findings

| Finding | Detail |
|---|---|
| Game record | 8 bytes: `[home, away, month, day, year, hour, min, null]` |
| Week footprint | 16 slots × 8 B + 8 B separator = 136 bytes |
| Separator | `07 00 00 00 00 00 00 00` (2017); `00 00...` (2004) |
| File size | 2992 bytes for both files |
| Trailing padding | 85 free game slots (680 bytes) in 2017 file |
| Bye weeks | Weeks 3–10 have 2 null slots each (4 teams on bye) |
| 2017 header | No 2-byte header — `WeekOneStartLoc` must be 0, not 2 |
| More games/week | **Binary format supports it** — code changes are small |
| Game engine risk | Engine likely hardcodes 16 games/week; unknown if flexible |
