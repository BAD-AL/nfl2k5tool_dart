// ignore_for_file: non_constant_identifier_names

import 'enum_definitions.dart';

enum SavePlatform { xbox, ps2, unknown }

/// Metadata that identifies a save across Xbox and PS2 platforms.
class SaveMetadata {
  /// The user-visible name of the save (from SaveMeta.xbx or icon.sys).
  String displayTitle = 'NFL2K5 Save';

  /// The Xbox directory hex ID (e.g., 42E8F759D2E9).
  String xboxDirId = '000000000000';

  /// The PS2 directory name (e.g., BASLUS-20919...).
  String ps2DirName = 'BASLUS-20919';

  /// Roster vs Franchise.
  SaveType type = SaveType.Franchise;

  /// The platform this save was originally loaded from.
  SavePlatform sourcePlatform = SavePlatform.unknown;

  SaveMetadata({
    this.displayTitle = 'NFL2K5 Save',
    this.xboxDirId = '000000000000',
    this.ps2DirName = 'BASLUS-20919',
    this.type = SaveType.Franchise,
    this.sourcePlatform = SavePlatform.unknown,
  });

  /// Synthesizes a PS2 directory name from an Xbox display title.
  static String synthesizePs2Name(String xboxName) {
    // Standard NFL2K5 PS2 prefix
    const prefix = 'BASLUS-20919';
    // Remove non-alphanumeric characters for the suffix
    final suffix = xboxName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    return prefix + suffix;
  }
}
