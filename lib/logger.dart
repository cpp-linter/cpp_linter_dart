// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:http/http.dart' show Response;
import 'package:logging/logging.dart' as logging;

// Project imports:
import 'package:cpp_linter_dart/common.dart';

/// A logger used to prompt for user-related output.
final log = logging.Logger('CPP-LINTER');

/// A logger used to GitHub CI log commands.
final logCommander = logging.Logger('CI log commands');

/// Setup loggers [log] and [logCommander]. The [debugging] parameter controls
/// the [logging.Level] in correspondence to the CLI argument `--verbose` or
/// `-v`.
void setupLoggers(bool debugging) {
  // needed to control logging levels independently from root logger
  logging.hierarchicalLoggingEnabled = true;
  logging.Logger.root.level = logging.Level.INFO; // good practice?

  log.level = debugging ? logging.Level.CONFIG : logging.Level.INFO;
  log.onRecord.listen((event) {
    var level = switch (event.level) {
      // translate CONFIG level as DEBUG messages
      logging.Level.CONFIG => 'DEBUG',
      // translate SHOUT level as WARNING messages
      logging.Level.SHOUT => 'WARNING',
      // all other levels use expected descriptions
      _ => event.level.toString(),
    };
    print('$level: ${event.loggerName}: ${event.message}');
  });
  logCommander.level = logging.Level.INFO;
  logCommander.onRecord.listen((event) => print(event.message));
}

/// Use the [logCommander] to start a group of CI log statements.
void startLogGroup(String name) {
  logCommander.info('::group::$name');
}

/// Use the [logCommander] to end a group of CI log statements.
void endLogGroup() {
  logCommander.info('::endgroup::');
}

/// Use the [log] logger to show any unsuccessful HTTP requests (as indicated by
/// [response]).
void logRequestResponse(Response response) {
  if (response.statusCode >= 400) {
    log.shout(
        'response returned ${response.statusCode} message: ${response.body}');
  }
}

/// Use the [logCommander] to set Github Action output variable in CI to
/// [status].
int setExitCode(int status) {
  var ghOutPath = String.fromEnvironment('GITHUB_OUTPUT');
  if (ghOutPath.isNotEmpty) {
    var ghOut = File(ghOutPath);
    ghOut.writeAsStringSync(
      'checks-failed=$status\n',
      mode: FileMode.append,
      encoding: utf8,
    );
  }
  return status;
}

/// Use the [log] logger to display the [files] getting attention.
void lsFiles(List<FileObj> files) {
  if (files.isEmpty) {
    log.info('No source files found.');
  } else {
    log.info('Giving attention to the following files:');
    for (final file in files) {
      log.info('\t${file.name}');
    }
  }
}
