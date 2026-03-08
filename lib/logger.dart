// ignore_for_file: non_constant_identifier_names

/// A simple logging interface to decouple core logic from dart:io.
class Logger {
  static void Function(String message) logHandler = (msg) => print(msg);
  static void Function(String message) errorHandler = (msg) => print('ERROR: $msg');

  static void log(String message) {
    logHandler(message);
  }

  static void error(String message) {
    errorHandler(message);
  }
}
