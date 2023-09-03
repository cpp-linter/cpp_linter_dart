// Dart imports:
import 'dart:io';

// Package imports:
import 'package:path/path.dart' as p;

// Project imports:
import 'package:cpp_linter_dart/cli.dart' as cli;
import 'package:cpp_linter_dart/common.dart';
import 'package:cpp_linter_dart/github_requests.dart';
import 'package:cpp_linter_dart/logger.dart';
import 'package:cpp_linter_dart/run.dart';

Future<int> main(List<String> arguments) async {
  var argParser = cli.getParser();
  var args = argParser.parse(arguments);
  if (args['help']) {
    cli.showHelp(argParser);
    return 0;
  }

  // force files-changed-only to reflect value of lines-changed-only
  bool linesChangedOnly = args['lines-changed-only'];
  bool filesChangedOnly = args['files-changed-only'];
  if (linesChangedOnly) {
    filesChangedOnly = true;
  }

  String extList = args['extensions'];
  var extensions = extList.split(',');
  extensions.removeWhere((element) => element.isEmpty);
  for (var ext in extensions.asMap().entries) {
    if (!ext.value.startsWith('.')) {
      extensions[ext.key] = '.${ext.value}';
    }
  }

  setupLoggers(args['verbosity']);

  var (ignored, notIgnored) = parseIgnoredOption(args['ignore']);

  var repoRoot = args['repo-root'];
  if (repoRoot != '.') {
    if (p.isAbsolute(repoRoot)) {
      Directory.current = repoRoot;
    } else {
      var current = Directory.current;
      Directory.current = p.normalize(p.join(current.toString(), repoRoot));
    }
  }
  // create a temp cache dir
  Directory('.cpp_linter_cache').create();

  log.info('Processing $githubEventName event');

  startLogGroup('Get list of specified source files');
  var files = <FileObj>[];
  if (filesChangedOnly) {
    files.addAll(await getListOfChangedFiles(args['verbosity']));
    filterOutNonSourceFiles(
      files,
      extensions,
      ignored,
      notIgnored,
      linesChangedOnly,
    );
  } else {
    files = listSourceFiles(extensions, ignored, notIgnored);
  }
  endLogGroup();

  if (files.isEmpty) {
    return setExitCode(0);
  }
  var (formatAdvice, _, tidyNotes) = await captureClangToolsOutput(
    files,
    args['version'],
    linesChangedOnly,
    args['style'],
    args['tidy-checks'],
    args['database'],
    args.rest,
    args['verbosity'],
  );

  startLogGroup('Posting comment(s)');
  final commentBody = makeComment(formatAdvice, tidyNotes, linesChangedOnly);
  final commentPreamble = '<!-- cpp linter action -->\n# Cpp-Linter Report ';
  final commentPs = '\n\nHave any feedback or feature suggestions? [Share it '
      'here.](https://github.com/cpp-linter/cpp-linter-action/issues)';
  final lgtm = '$commentPreamble:heavy_check_mark:\nNo problems need attention.'
      '$commentPs';
  final fullComment = '$commentPreamble$commentBody$commentPs';

  var threadCommentsAllowed = true;
  if (githubEventPath.isNotEmpty) {
    var repoInfo = ghEventPayload['repository'] as Map<String, Object>?;
    if (repoInfo != null && repoInfo.keys.contains('private')) {
      threadCommentsAllowed = repoInfo['private'] as bool == false;
    }
  }
  if (args['thread-comments'] != 'false' && threadCommentsAllowed) {
    bool updateOnly = args['thread-comments'] == 'update';
    if (args['lgtm'] && commentBody.isEmpty) {
      postResults(lgtm, updateOnly);
    } else {
      postResults(commentBody.isNotEmpty ? fullComment : '', updateOnly);
    }
  }
  if (args['step-summary'] && githubStepSummary.isNotEmpty) {
    File(githubStepSummary).writeAsString(
      '\n${commentBody.isNotEmpty ? fullComment : lgtm}\n',
      mode: FileMode.append,
    );
  }
  var exitCode = makeAnnotations(
    formatAdvice,
    tidyNotes,
    args['file-annotations'],
    args['style'],
    linesChangedOnly,
  );
  endLogGroup();

  return setExitCode(exitCode);
}
