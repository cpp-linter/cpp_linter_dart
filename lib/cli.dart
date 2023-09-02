// Package imports:
import 'package:args/args.dart';

/// Create an [ArgParser] for parsing the CLI arguments
ArgParser getParser() {
  var parser = ArgParser();
  parser.addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Show this information and exit',
  );
  parser.addFlag(
    'verbosity',
    abbr: 'v',
    negatable: false,
    help: 'Show verbose debugging output',
  );
  parser.addOption(
    'database',
    abbr: 'p',
    defaultsTo: '',
    help: 'The path to the compilation database.',
  );
  parser.addOption(
    'style',
    abbr: 's',
    defaultsTo: 'llvm',
    help: 'The style guidelines to use for clang-format. '
        'Accepted values depend on the version of clang being used.',
  );
  parser.addOption(
    'tidy-checks',
    abbr: 't',
    defaultsTo: 'boost-*,bugprone-*,performance-*,readability-*,portability-*,'
        'modernize-*,clang-analyzer-*,cppcoreguidelines-*',
    help: 'The checks to use for clang-tidy. Set this to an empty string '
        "('') to use clang-tidy file(s). Use '-*' to disable clang-tidy "
        'analysis.',
  );
  parser.addOption(
    'version',
    abbr: 'V',
    defaultsTo: '',
    help: 'The clang version to use.',
  );
  parser.addOption(
    'extensions',
    abbr: 'e',
    defaultsTo: 'c,h,C,H,cpp,hpp,cc,hh,c++,h++,cxx,hxx',
    help: 'A comma-separated list of file extensions to analyze',
  );
  parser.addOption(
    'repo-root',
    abbr: 'r',
    defaultsTo: '.',
    help: 'The path to the repository root',
  );
  parser.addOption(
    'ignore',
    abbr: 'i',
    defaultsTo: '.github',
    help: 'A bar separated list of paths to ignore. A path can be explicitly '
        'included by prefixing the path with a exclamation mark (`!`).',
  );
  parser.addFlag(
    'lines-changed-only',
    abbr: 'l',
    negatable: false,
    help: 'Only analyze lines changed in the commit or pull request.',
  );
  parser.addFlag(
    'files-changed-only',
    abbr: 'f',
    help: 'Only analyze files changed in the commit or pull request. '
        'This is automatically enabled when `--lines-changed-only` is enabled. '
        'For private repositories, a `GITHUB_TOKEN` is required.',
  );
  parser.addOption(
    'thread-comments',
    abbr: 'c',
    defaultsTo: 'false',
    allowed: ['true', 'false', 'update'],
    allowedHelp: {
      'true': 'deletes an old thread comment (if any) and creates a new one',
      'false': 'does not delate or create a thread comment',
      'update': 'updates the content of a thread comment or creates one if none'
          ' exist',
    },
    help: 'Enable feedback in the form of a thread comment ',
  );
  parser.addFlag(
    'step-summary',
    abbr: 'w',
    defaultsTo: false,
    negatable: false,
    help: 'Enable the use of thread comments as feedback. '
        'For private repositories, a `GITHUB_TOKEN` is required.',
  );
  parser.addFlag(
    'file-annotations',
    abbr: 'a',
    defaultsTo: true,
    help: '',
  );
  parser.addFlag(
    'lgtm',
    abbr: 'g',
    defaultsTo: false,
    help: 'Post a "Looks Good To Me" when checks pass. '
        'Only applies to `thread-comments` feature.',
  );
  return parser;
}

/// Display usage/help in the console.
void showHelp(ArgParser parser) {
  print('Usage: cpp-linter [OPTIONS] [-- extra-args to clang-tidy]');
  print('\n${parser.usage}');
}
