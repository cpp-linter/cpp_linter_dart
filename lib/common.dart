import 'dart:convert';
import 'dart:io';
import 'package:cpp_linter_dart/clang_format.dart';
import 'package:cpp_linter_dart/clang_tidy.dart';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as p;

/// Describes if using a CI environment (as detected from the `CI` env var).
const isOnRunner = bool.fromEnvironment('CI', defaultValue: false);

/// The name of the cached YAML output file used to parse clang-tidy advice.
const clangTidyYamlCache = '.cpp_linter_cache/clang_tidy_output.yml';

/// The name of the cached file containing stdout used to parse clang-tidy notes.
const clangTidyNoteCache = '.cpp_linter_cache/clang-tidy-output.txt';

/// The name of the cached XML output used to parse clang-format advice.
const clangFormatXmlCache = '.cpp_linter_cache/clang_format_output.xml';

/// A generic representation of a file. This is used to store information
/// commonly accessed by other functionality.
class FileObj {
  /// The ranges of line numbers in the diff. Not really used.
  List<List<int>> diffChunks = [];

  /// The list of numbers that were added (as evident in a diff).
  List<int> additions = [];

  /// The ranges of lines added. This is only set if the file was found as part
  /// of a git diff. It is a consolidated version of [additions].
  List<List<int>> linesAdded = [];

  /// The file name (using posix path delimiters).
  String name;

  /// Create a [FileObj] corresponding to the file's [name].
  FileObj(this.name);
}

/// Run an executable in a separate [Shell] instance. (asynchronous)
///
/// ## Parameters
/// - [exe] ([String]): The executable name.
/// - [args] ([List]<[String]>?]): A nullable list of strings that will be
///   passed as arguments to the executable. If null, no arguments are passed
///   to the executable.
/// - [captureStderr] ([List]<[String]>?]): A nullable list of strings that will
///   be used to capture the executable's error output (from stderr). If set to
///   null (the default value), then the executable's stderr is logged to the
///   console.
/// - [allowThrows] ([bool]): Set this to `false` to ignore unsuccessful exit
///   codes returned by the executable.
/// ## Returns
/// The executable's output (from stdout) is returned as a [String]
Future<String> subprocessRun(
  String exe, {
  List<String>? args,
  List<String>? captureStderr,
  bool allowThrows = true,
}) async {
  List<String> stdoutLines = [];
  var stdOutController = ShellLinesController();
  stdOutController.stream.listen((line) {
    stdoutLines.add(line);
  });
  var shell = Shell(
      stdout: stdOutController.sink, verbose: false, throwOnError: allowThrows);
  if (captureStderr != null) {
    var stderrController = ShellLinesController();
    stderrController.stream.listen((line) {
      captureStderr.add(line);
    });
    shell = Shell(
        stdout: stdOutController.sink,
        stderr: stderrController.sink,
        verbose: false);
  }
  try {
    if (args == null) {
      await shell.run(exe);
    } else {
      await shell.runExecutableArguments(exe, args);
    }
  } catch (e) {
    print(e);
  }
  return stdoutLines.join('\n');
}

/// Assemble an executable name for the clang [tool] based on the [version].
///
/// If the [version] argument is an integer, then this returns the [tool] name
/// with the [version] number and a system-appropriate suffix. On Windows, a
/// [version] integer is ignored since multiple versions of clang tools are not
/// installed to the same path.
///
/// If the [version] argument is an existing path, then the returned [String]
/// represents the absolute path to the found executable; relative paths are
/// resolved to the working [Directory] (which can be changed with the CLI arg
/// `--repo-root` or `-r`).
///
/// As a fallback, this simply returns the [tool] with an appropriate suffix
/// (`'.exe'` on Windows or `''` for others).
String makeClangToolExeVersion(String tool, String version) {
  var suffix = Platform.isWindows ? '.exe' : '';
  if (int.tryParse(version) != null) {
    // is version a number
    if (Platform.isWindows) return '$tool$suffix';
    return '$tool-$version$suffix';
  }
  // treat version as an explicit path
  var versionPath = p.absolute(version);
  var possibles = [
    File('$versionPath/bin/$tool$suffix'),
    File('$versionPath/$tool$suffix'),
  ];
  for (final possible in possibles) {
    if (possible.existsSync()) return possible.path;
  }
  // version path was non-existent or empty
  return '$tool$suffix';
}

/// Translates a byte [offset] into a [List] of [int]s that respectively
/// describe the [filename]'s number of lines and number of columns on the last
/// line.
(int, int) getLineAndColsFromOffset(String filename, int offset) {
  var contents = File(filename).readAsBytesSync().getRange(0, offset);
  var lines = utf8.decode(contents.toList()).split('\n');
  var cols = lines.last.length;
  return (lines.length, cols);
}

String makeComment(
  List<FormatFix> formatAdvice,
  List<TidyNotification> tidyNotes,
  bool linesChangedOnly,
) {
  var result = '';
  var formatComment = '';
  var tidyComment = '';
  for (final advice in formatAdvice) {
    if (advice.replacements.isNotEmpty) {
      var shouldNotify = true;
      if (linesChangedOnly) {
        for (final replacement in advice.replacements) {
          if (!replacement
              .any((element) => advice.file.additions.contains(element.line))) {
            shouldNotify = false;
          }
        }
      }
      if (shouldNotify) {
        formatComment += '\n- ${advice.file.name}';
      }
    }
  }
  for (final note in tidyNotes) {
    final shouldNotify =
        linesChangedOnly ? note.file.additions.contains(note.line) : true;
    if (shouldNotify) {
      var concernedCode = note.srcLines.join('\n');
      if (concernedCode.isNotEmpty && !concernedCode.endsWith('\n')) {
        concernedCode += '\n';
      }
      if (concernedCode.isNotEmpty) {
        concernedCode =
            '```${p.extension(note.file.name).replaceFirst('.', '')}\n'
            '$concernedCode```';
      }
      tidyComment +=
          '**${note.file.name}:${note.line}:${note.cols}:** ${note.type}: '
          '[${note.diagnostic}]\n> ${note.info}\n\n$concernedCode\n\n';
    }
  }
  if (formatComment.isNotEmpty || tidyComment.isNotEmpty) {
    result = ':warning:\nSome files did not pass the configured checks!\n';
    if (formatComment.isNotEmpty) {
      result += '\n<details><summary>clang-format reports: <strong>'
          '${formatAdvice.length} file(s) not formatted</strong></summary>\n'
          '$formatComment\n\n</details>';
    }
    if (tidyComment.isNotEmpty) {
      result += '\n<details><summary>clang-tidy reports: <strong>'
          '${tidyNotes.length} concerns(s)</strong></summary>\n\n'
          '$tidyComment</details>';
    }
  }
  return result;
}
