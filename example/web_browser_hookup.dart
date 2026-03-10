                                                                                                                                                                                                                                        
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart';
import 'package:nfl2k5tool_dart/save_session.dart';

// Attaches to an input element. 
bool hookup(String inputId) {
  final input = document.getElementById(inputId);
  if (input == null || input is! HTMLInputElement) return false;

  // ensure that the 'type' and 'accept' fields are setup correctly.
  input.type = 'file';
  input.accept = '.zip,.dat,.max,.psu,.ps2,.bin,.img';

  input.addEventListener('change', (Event _) async {
    final file = input.files?.item(0);
    if (file == null) return;

    final name = file.name.toLowerCase();
    final buffer = await file.arrayBuffer().toDart;
    final bytes = Uint8List.view(buffer.toDart);

    try {
      SaveSession session;

      if (name.endsWith('.dat')) {
        session = SaveSession.fromRawDat(bytes);
      } else if (name.endsWith('.zip')) {
        session = SaveSession.fromXboxZip(bytes);
      } else if (name.endsWith('.max') || name.endsWith('.psu')) {
        session = SaveSession.fromPs2Save(bytes);
      } else if (name.endsWith('.ps2')) {
        session = SaveSession.fromPs2Card(bytes);
      } else if (name.endsWith('.bin') || name.endsWith('.img')) {
        try {
          session = SaveSession.fromXboxMU(bytes);
        } catch (_) {
          session = SaveSession.fromPs2Card(bytes);
        }
      } else {
        window.alert('Unsupported file type: $name');
        return;
      }

      print('Loaded: ${session.metadata.displayTitle}');
    } catch (e) {
      window.alert('Failed to load file: $e');
    }
  }.toJS);

  return true;
}
