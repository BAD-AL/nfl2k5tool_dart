# NFL2K5Tool Dart

A Dart translation of `NFL2K5Tool`, designed to read and modify NFL 2K5 game save files (rosters and franchise saves) for both Xbox and PlayStation 2.

**Why Dart?**
Dart is a cross-platform language that can be run as a script (via the dart runtime) or can be natively compiled to Linux, Windows, Mac, iOS, Android, or Browser(JavaScript / wasm).

As the Windows operating system declines, I feel it's important to enable programs to move to other platforms more easily.

## Features

- **Read Save Data:** Extract player, coach, and schedule information from multiple formats.
- **Modify Save Data:** Apply changes made to your game saves.
- **Platform Support:** Handles both Xbox and PS2 save formats via `xbox_memory_unit_tool` and `dart_mymc`.
- **Supported Formats:**
  - **Xbox:**
    - `SAVEGAME.DAT` (Raw data)
    - `.zip` (Compressed save bundle)
    - `.bin`/`.img` (Full XEMU Memory Unit images )
  - **PlayStation 2:**
    - `.max` (Action Replay Max)
    - `.psu` (EMS Memory Adapter)
    - `.ps2` (Full PCSX2 Memory Card images)

## Prerequisites

- [Dart SDK](https://dart.dev/get-dart) (^3.10.8 or later)

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/BAD-AL/nfl2k5tool_dart.git
   cd nfl2k5tool_dart
   ```

2. Get dependencies:
   ```bash
   dart pub get
   ```
3. Compile:
  ```bash
  # compile Linux
  dart compile exe bin/nfl2k5tool_dart.dart -o nfl2k5tool

  # compile windows
  dart compile exe bin/nfl2k5tool_dart.dart -o nfl2k5tool.exe
  ```
## Data Import/Export

NFL2K5Tool Dart provides robust support for a variety of save formats across platforms, making it easy to transfer data between emulators (Xemu, PCSX2), real hardware (via memory card tools), and community roster files.

### Xbox
- **Raw Save Data (`SAVEGAME.DAT`):** Direct reading and writing of the core save data. The tool automatically signs the data and manages the companion `EXTRA` file for authenticity.
- **Save Bundles (`.zip`):** Directly load and save to Xbox save bundles. This is the preferred format for sharing community rosters.
- **Memory Unit Images (`.bin`, `.img`):** Extract and export saves directly to/from Xbox Memory Unit images (XEMU).

### PlayStation 2
- **Action Replay Max (`.max`):** Import and export to the Action Replay Max format.
- **EMS Memory Adapter (`.psu`):** Support for the PSU format, widely used with PS2 Save Builder and various memory card adapters.
- **Memory Card Images (`.ps2`):** Import and export to PS2 memory card images, such as those used with the PCSX2 emulator.

## Cross-Platform Conversions

One of the most powerful features of NFL2K5Tool Dart is the ability to convert saves between platforms. For example, you can load an Xbox roster and save it directly as a PS2 `.max` file:

```bash
dart bin/nfl2k5tool_dart.dart MyXboxRoster.dat -out:MyPs2Roster.max
```

The tool automatically handles:
- **Signing:** Applies the correct Xbox (`HMAC-SHA1`) or PS2 signature to the save data.
- **Metadata:** Synthesizes necessary metadata (like `icon.sys` or `SaveMeta.xbx`) when moving between platforms.
- **Structure:** Packages the save correctly for the target format (MAX, PSU, ZIP, or Memory Image).

## Usage

```bash
# compile Linux
dart compile exe bin/nfl2k5tool_dart.dart -o nfl2k5tool

# compile windows
dart compile exe bin/nfl2k5tool_dart.dart -o nfl2k5tool.exe

# use
nfl2k5tool [save_file] [data_to_apply.txt] [options]
```



### Options

- `-app`            Print appearance data.
- `-st`             Print Special teams players.
- `-ab`             Print player abilities (speed, agility, ...).
- `-audc`           Auto update the depth chart.
- `-aupbp`          Auto update the play-by-play info for each player.
- `-auph`           Auto update the photo for each player.
- `-sch`            Print schedule.
- `-fa`             Print Free Agents.
- `-dc`             Print draft class.
- `-coach`          Print coaches.
- `-stdin`          Read data from standard in.
- `-Key:<key>`      Specify a specific player/team key.
- `-CoachKey:<key>` Specify a Coach Key.
- `-out:<file>`     Save modified save file to `<file>`.
- `-help`           Show the help message.

## Examples

**Print all player abilities from a save file:**
```bash
dart bin/nfl2k5tool_dart.dart MyRoster.dat -ab
```

**Apply changes from a text file and save to a new file:**
```bash
dart bin/nfl2k5tool_dart.dart MyRoster.zip input.txt -out:MyRoster_mod.zip
```

**Apply changes, auto-update depth charts, and print abilities for all players (including draft/FA):**
```bash
dart bin/nfl2k5tool_dart.dart MyRoster.zip input.txt -audc -dc -fa -ab
```

## API

`nfl2k5tool_dart` is fully compatible with Dart/Flutter Web. Since the browser does not have a file system (`dart:io`), you should use the `SaveSession` class to handle byte buffers directly.

The library's "super power" is its ability to produce and consume structured CSV-like text, which makes it easy to integrate with UI tables or bulk-editing tools.

### Web/Library Usage Example

```dart
import 'dart:typed_data';
import 'package:nfl2k5tool_dart/nfl2k5tool_dart.dart';

void onFilePicked(Uint8List fileBytes) {
  // 1. Initialize a session from bytes (handles Xbox/PS2 formats & signing)
  SaveSession session = SaveSession.fromXboxZip(fileBytes); 
  GamesaveTool engine = session.engine;

  // 2. Extract data as CSV-formatted strings
  // Get all player abilities (Speed, Agility, etc.)
  String playerCsv = engine.GetLeaguePlayers(true, false, false);
  String modifiedCsv = myFunctionThatDoesStuff(playerCsv);

  // 3. Apply modifications using InputParser
  InputParser parser = InputParser(engine);
  parser.ProcessText(modifiedCsv);
  
  // 4. Export the modified save as bytes for download
  Uint8List modifiedFile = session.exportToXboxZip();
  // ... save via browser download or 'dart:io' stuff ...
}
```

### Core Classes

- **`SaveSession`**: The entry point for loading and saving different formats (`fromXboxZip`, `fromPs2Save`, `exportToPs2Max`, etc.). It manages the platform-specific signing and metadata automatically.
- **`GamesaveTool`**: The core engine that performs byte-level operations. Use its `Get...` methods to extract data as strings.
- **`InputParser`**: A high-level utility to process text.

## Related Projects

- [NFL2K5Tool (C#)](https://github.com/BAD-AL/NFL2K5Tool) - The original C# implementation.
- [dart_mymc](https://github.com/BAD-AL/dart_mymc) - PS2 Memory Card tool for Dart.
- [xbox_memory_unit_tool](https://github.com/BAD-AL/xbox_memory_unit_tool) - Xbox Memory Unit tool for Dart.

## License

This project is open source. Refer to the original [NFL2K5Tool](https://github.com/BAD-AL/NFL2K5Tool)  for licensing details if not specified here.
