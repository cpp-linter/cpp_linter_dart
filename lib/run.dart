// Dart imports:
import 'dart:io';

// Package imports:
import 'package:ini/ini.dart' show Config;
import 'package:path/path.dart' as p;

// Project imports:
import 'clang_format.dart';
import 'clang_tidy.dart';
import 'common.dart' show FileObj;
import 'logger.dart';

/// Parse the [userInput] (from CLI `--ignore` or `-i` argument) into a [List]
/// of [Set]s that respectively correspond to ignored and not-ignored files.
(Set<String>, Set<String>) parseIgnoredOption(String userInput) {
  Set<String> ignored = {};
  Set<String> notIgnored = {};
  for (var path in userInput.split('|')) {
    bool isNotIgnored = path.startsWith("!");
    path = path.replaceFirst(RegExp(r'[!]?(?:.\/)?'), '');
    if (isNotIgnored) {
      notIgnored.add(path);
    } else {
      ignored.add(path);
    }
  }

  // check against git submodule paths
  var gitModules = p.join(p.current, '.gitmodules');
  if (File(gitModules).existsSync()) {
    var config = Config.fromStrings(File(gitModules).readAsLinesSync());
    for (final section in config.sections()) {
      var path = config.get(section, 'path');
      if (notIgnored.contains(path!)) {
        // if explicitly not ignored
        ignored.add(path);
      }
    }
  }

  if (ignored.isNotEmpty) {
    log.info('Ignoring the following paths/files:');
    for (final path in ignored) {
      log.info('\t$path');
    }
  }
  if (notIgnored.isNotEmpty) {
    log.info('Not ignoring the following paths/files:');
    for (final path in notIgnored) {
      log.info('\t$path');
    }
  }
  return (ignored, notIgnored);
}

/// Is the specified [file] in the specified [fileSet]?
bool isFileInSet(FileObj file, Set<String> fileSet) {
  for (final filePath in fileSet) {
    if (Directory(filePath).existsSync()) {
      if (p.isWithin(filePath, file.name)) {
        return true;
      }
    }
  }
  return fileSet.contains(file.name);
}

/// Filter [files] that don't use the specified [extensions] in accordance
/// to the specified [ignored] and/or [notIgnored] sets of paths/files. If
/// [linesChangedOnly] is set `true`, then only [files] with a non-empty list of
/// [FileObj.linesAdded] will be included.
void filterOutNonSourceFiles(
  List<FileObj> files,
  List<String> extensions,
  Set<String> ignored,
  Set<String> notIgnored,
  bool linesChangedOnly,
) {
  files.removeWhere((file) {
    var ext = p.extension(file.name);
    if (extensions.contains(ext)) {
      bool ignore = isFileInSet(file, ignored);
      if (ignore && isFileInSet(file, notIgnored)) {
        ignore = false;
      }
      if (!ignore && linesChangedOnly && file.linesAdded.isEmpty) {
        ignore = true;
      }
      return ignore;
    }
    return true;
  });
  lsFiles(files);
}

/// Aggregate a [List] of [FileObj]s by walking the working [Directory] (as set
/// with the CLI `--repo-root` or `-r` arguments).
List<FileObj> listSourceFiles(
  List<String> extensions,
  Set<String> ignored,
  Set<String> notIgnored,
) {
  List<FileObj> walkDir(Directory dir) {
    if (dir.path != Directory.current.path) {
      log.config('Crawling ${p.relative(dir.path)}');
    }
    List<FileObj> result = [];
    for (final path in dir.listSync(followLinks: true)) {
      var entityType = path.statSync().type;
      if (entityType == FileSystemEntityType.directory) {
        if (p.basename(path.path).startsWith('.')) {
          continue; // dir is hidden; skip it
        }
        result.addAll(walkDir(Directory(path.path)));
      } else if (entityType != FileSystemEntityType.file) {
        continue;
      }

      var ext = p.extension(path.path);
      if (!extensions.contains(ext)) {
        continue;
      }

      var relPath = p.relative(path.path);
      var file = FileObj(relPath);
      var ignore = isFileInSet(file, ignored);
      if (ignore && isFileInSet(file, notIgnored)) {
        ignore = true;
      }
      if (!ignore) {
        result.add(file);
      }
    }
    return result;
  }

  var result = walkDir(Directory.current);
  lsFiles(result);
  return result;
}

/// Capture and parse output from clang-tody and clang-format (of a specified
/// [version]) about specified [files] considering [linesChangedOnly], and
/// clang-format [style].
Future<(List<FormatFix>, List<TidyAdvice>, List<TidyNotification>)>
    captureClangToolsOutput(
  List<FileObj> files,
  String version,
  bool linesChangedOnly,
  String style,
  String checks,
  String database,
  List<String>? extraArgs,
  bool debug,
) async {
  var formatAdvice = <FormatFix>[];
  const tidyAdvice = <TidyAdvice>[];
  var tidyNotifications = <TidyNotification>[];
  for (final file in files) {
    startLogGroup('Performing checkup on ${file.name}');
    var notes = await runClangTidy(
      file,
      version,
      style,
      checks,
      linesChangedOnly,
      database,
      extraArgs,
      debug,
    );
    if (notes.isNotEmpty) tidyNotifications.addAll(notes);
    // For deployment, we are not actually using the yaml output
    // var advice = parseYmlAdvice(file);
    // if (advice.diagnostics.isNotEmpty) tidyAdvice.add(advice);

    var fmtOut = await runClangFormat(
      file,
      version,
      style,
      linesChangedOnly,
      debug,
    );
    if (fmtOut.replacements.isNotEmpty) {
      formatAdvice.add(fmtOut);
    }
    endLogGroup();
  }
  return (formatAdvice, tidyAdvice, tidyNotifications);
}
