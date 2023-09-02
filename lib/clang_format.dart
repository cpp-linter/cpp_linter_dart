import 'dart:io';
import 'package:xml/xml.dart';
import 'package:cpp_linter_dart/logger.dart';
import 'common.dart';

/// A single piece of clang-format advice about a single line.
class FormatReplacement {
  /// The number of columns where the advice begins.
  int offset;

  /// The total number of columns being removed as part of the advice.
  int rmLength;

  /// The line number where the replacement starts.
  int line;

  /// The column number of the line where the replacement starts.
  int cols;

  /// The modified text resulting from the advice.
  String text;

  /// Create an object to represent singular clang-format advice.
  FormatReplacement(
    this.offset,
    this.rmLength,
    this.line,
    this.cols,
    this.text,
  );
}

/// Advice parsed from clang-format for a [file].
class FormatFix {
  /// The [FileObj] that corresponds to the advice in [replacements].
  FileObj file;

  /// Create an object used to represent advice from clang-format.
  FormatFix(this.file);

  /// A [List] of advice about a single line.
  List<List<FormatReplacement>> replacements = [];

  /// Use [logCommander] to output clang-format advice for a single file.
  String logCommand(String style, bool linesChangedOnly) {
    List<String> knownStyles = [
      'llvm',
      'gnu',
      'google',
      'chromium',
      'microsoft',
      'mozilla',
      'webkit',
    ];
    final String displayStyle;
    if (!knownStyles.contains(style)) {
      displayStyle = 'Custom';
    } else {
      if (['gnu', 'llvm'].contains(style)) {
        displayStyle = style.toUpperCase();
      } else {
        displayStyle = '${style[0].toUpperCase()}${style.substring(1)}';
      }
    }

    List<int> lines = [];
    if (!linesChangedOnly) {
      for (final replacement in replacements) {
        lines.add(replacement.first.line);
      }
    } else {
      lines = replacements
          .where((lineFixes) => file.additions.contains(lineFixes.first.line))
          .map((e) => e.first.line)
          .toList();
    }

    if (lines.isEmpty) return '';
    return '::notice file=${file.name},title=Run clang-format on ${file.name}::'
        'File ${file.name} does not conform to $displayStyle style guidelines. '
        '(lines ${lines.join(", ")})';
  }

  /// NOTE: This is currently broken and needs much improvement!
  List<String> getSuggestions({bool lineChangesOnly = false}) {
    List<int>? linesChanged;
    if (lineChangesOnly) {
      linesChanged = file.additions;
    }
    var content = File(file.name).readAsStringSync();
    var result = <String>[];
    for (final lineFixes in replacements) {
      if (lineChangesOnly &&
          linesChanged != null &&
          !linesChanged.contains(lineFixes.first.line)) {
        continue;
      }
      var lastOffset = 0;
      var replaced = '';
      for (final fix in lineFixes.asMap().entries) {
        if (replaced.isEmpty) {
          // starting our first replacement for a line
          replaced = content.replaceRange(
            fix.value.offset,
            fix.value.offset + fix.value.rmLength,
            fix.value.text,
          );
          lastOffset =
              fix.value.offset + fix.value.rmLength + fix.value.text.length;
        } else {
          // starting a subsequent replacement for the same line
          var adjustedOffset = 0;
          for (final prev in lineFixes.take(fix.key)) {
            adjustedOffset += prev.text.length - prev.rmLength;
          }
          replaced = replaced.replaceRange(
              fix.value.offset + adjustedOffset,
              fix.value.offset + adjustedOffset + fix.value.rmLength,
              fix.value.text);
          lastOffset = adjustedOffset +
              fix.value.offset -
              fix.value.rmLength +
              fix.value.text.length;
        }
      }
      var lineStart = content.lastIndexOf('\n', lineFixes.first.offset - 1) + 1;
      var lineEnd = replaced.indexOf('\n', lastOffset + 1);
      assert(lineEnd >= lineStart);
      result.add(
        '```suggestion\n${replaced.substring(lineStart, lineEnd)}\n```',
      );
    }
    return result;
  }
}

/// Parse the [xmlOut] from running clang-format on a single [file].
FormatFix parseFormatReplacementsXml(String xmlOut, FileObj file) {
  FormatFix advice = FormatFix(file);
  final document = XmlDocument.parse(xmlOut);
  for (final child in document.root.findAllElements('replacement')) {
    var offset = int.parse(
      child.attributes.firstWhere((p0) => p0.name.toString() == 'offset').value,
    );
    var (line, cols) = getLineAndColsFromOffset(file.name, offset);
    var rmLength =
        child.attributes.firstWhere((p0) => p0.name.toString() == 'length');
    var replacement = FormatReplacement(
      offset,
      int.parse(rmLength.value),
      line,
      cols,
      child.innerText,
    );
    if (advice.replacements.isEmpty ||
        advice.replacements.last.last.line != line) {
      // replacement happens on a different line
      advice.replacements.add([replacement]);
    } else {
      // replacement happens on the same line as the last replacement
      advice.replacements.last.add(replacement);
    }
  }
  return advice;
}

/// Run clang-format (of specified [version]) on a [file] for compliance with a
/// specified [style]. If [linesChangedOnly] is `true`, then only lines with
/// additions is of focus.
Future<FormatFix> runClangFormat(
  FileObj file,
  String version,
  String style,
  bool linesChangedOnly,
  bool debug,
) async {
  if (style.isEmpty) return FormatFix(file);
  var args = ['-style=$style', '--output-replacements-xml'];
  var ranges = file.linesAdded;
  if (linesChangedOnly) {
    for (final range in ranges) {
      args.add('--lines=${range.first}:${range.last}');
    }
  }
  args.add(file.name);
  var stderrLines = <String>[];
  var exe = makeClangToolExeVersion('clang-format', version);
  log.info('Running "$exe ${args.join(' ')}"');
  var xmlOut = await subprocessRun(
    exe,
    args: args,
    captureStderr: stderrLines,
    allowThrows: false,
  );
  if (debug) File(clangFormatXmlCache).writeAsStringSync(xmlOut);
  if (stderrLines.isNotEmpty) {
    log.info('clang-format encountered the following errors:\n\t'
        '${stderrLines.join("\n\t")}');
  }
  return parseFormatReplacementsXml(xmlOut, file);
}
