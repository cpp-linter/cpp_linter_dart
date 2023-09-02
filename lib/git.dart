// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:path/path.dart' as p;

// Project imports:
import 'package:cpp_linter_dart/logger.dart';
import 'common.dart';

/// Get the SHA of the commit's [parent]. By default this get the last commit's
/// SHA, but the [parent] value can be increased to fetch the SHA of grandparent
/// commit (ie. getSha(3) returns the third previous commit's SHA).
Future<String> getSha({int parent = 1}) async {
  return subprocessRun('git', args: ["log", "-$parent", "--format=%H"]);
}

/// Get the diff for the currently staged files or the current commit if no
/// changes were made.
Future<String> getDiff(bool debug) async {
  var sha = await getSha();
  log.info('Getting diff between HEAD..$sha');
  var result = await subprocessRun('git', args: ['status', '-v']);
  var diffStart = result.indexOf('diff --git');
  if (diffStart < 0) {
    log.warning('There was no diff found.');
    return '';
  }
  var diff = result.substring(diffStart);
  if (debug) {
    var diffName = p.join(
      p.current,
      '.cpp_linter_cache',
      'HEAD..${sha.substring(0, 6)}.diff',
    );
    File(diffName).writeAsStringSync(
      diff,
      mode: FileMode.writeOnly,
      encoding: utf8,
    );
  }
  return diff;
}

/// Parses a file's name from the diff chunk's front matter. Binary files are
/// ignored (returns `null`).
String? getFileNameFromFrontMatter(String frontMatter) {
  var diffFileName = RegExp(r"^\+\+\+\sb?/(.*)$", multiLine: true);
  var fileNameMatch = diffFileName.firstMatch(frontMatter);
  if (fileNameMatch != null) {
    var match = fileNameMatch.group(1);
    if (match != null) return match;
  }

  var diffRenamedFile = RegExp(r"^rename to (.*)$", multiLine: true);
  var isRenamed = diffRenamedFile.firstMatch(frontMatter);
  if (isRenamed != null) {
    var match = isRenamed.group(1);
    if (match != null && frontMatter.trimLeft().startsWith('similarity')) {
      return match;
    }
  }

  var diffBinaryFile = RegExp(r"^Binary\sfiles\s", multiLine: true);
  var isBinary = diffBinaryFile.firstMatch(frontMatter);
  if (isBinary != null) {
    log.config('Unrecognized diff chunk starting with:\n$frontMatter');
  }
  return null;
}

/// Consolidates a [List]<[int]> of line numbers into a [List] of ranges
/// ([List]<[int]>) describing the beginning and ending of the multiple ranges.
List<List<int>> consolidateListToRanges(List<int> numbers) {
  List<List<int>> result = [];
  int i = 0;
  for (final number in numbers) {
    if (i == 0) {
      // start first range
      result.add([number]);
    } else if (number - 1 != numbers[i - 1]) {
      // end of a range
      result.last.add(numbers[i - 1] + 1); // complete the range
      result.add([number]); // start a new range
    }
    i++;
  }
  result.last.add(numbers.last + 1); // complete last range
  return result;
}

/// A [RegExp] pattern that matches a diff hunk's line information.
RegExp hunkInfo = RegExp(r'@@\s\-\d+,\d+\s\+(\d+,\d+)\s@@', multiLine: true);

/// Parses a s diff [patch] for a single [file]. Line changes are stored to the
/// [FileObj.linesAdded] or [FileObj.diffChunks].
void parsePatch(String patch, FileObj file) {
  List<int> additions = [];
  var lineNumberInDiff = 0; // should correspond to the file's line number
  for (final line in patch.split('\n')) {
    var hunkHeader = hunkInfo.firstMatch(line);
    if (hunkHeader != null) {
      // starting new hunk
      var match = hunkHeader.group(1);
      var range = match!.split(',');
      lineNumberInDiff = int.parse(range.first);
      continue;
    }
    if (line.startsWith('+')) {
      additions.add(lineNumberInDiff);
    }
    if (!line.startsWith('-')) {
      lineNumberInDiff++;
    }
  }
  file.linesAdded = consolidateListToRanges(additions);
  file.additions = additions;
}

/// Parses a complete [diff] into a [List] of [FileObj]s (binary files are
/// ignored).
List<FileObj> parseDiff(String diff) {
  List<FileObj> files = [];
  if (diff.isEmpty) return files;
  var fileChunks = diff.split(RegExp(r'^diff --git a/.*$', multiLine: true));
  fileChunks.removeWhere((element) => element.isEmpty);
  for (var chunk in fileChunks) {
    var firstHunk = chunk.indexOf(hunkInfo);
    if (firstHunk < 0) {
      continue; // chunk start is unrecognized
    }
    var chunkFrontMatter = chunk.substring(0, firstHunk);
    var fileName = getFileNameFromFrontMatter(chunkFrontMatter);
    if (fileName == null) {
      continue;
    }
    files.add(FileObj(fileName));
    parsePatch(chunk.substring(firstHunk), files.last);
  }
  return files;
}
