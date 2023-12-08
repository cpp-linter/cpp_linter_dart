// Dart imports:
import 'dart:io';

// Package imports:
import 'package:cpp_linter_dart/cli.dart';
import 'package:test/test.dart';

// Project imports:
import 'package:cpp_linter_dart/git.dart';
import 'package:cpp_linter_dart/run.dart';
import '../bin/cpp_linter_dart.dart' as bin;

void main() async {
  test('parseIgnore', () {
    <String, (Set<String>, Set<String>)>{
      '.github': ({'.github'}, {}),
      '.github|': ({'.github', ''}, {}),
      '.github|./': ({'.github', ''}, {}),
      '.github|!./': ({'.github'}, {''}),
      '.github|!.cpp_linter_cache': ({'.github'}, {'.cpp_linter_cache'}),
    }.forEach((key, value) {
      var (ignored, notIgnored) = parseIgnoredOption(key);
      expect(ignored, value.$1);
      expect(notIgnored, value.$2);
    });
  });

  test('list/filterSourceFiles', () {
    var extensions = ['.cpp', '.hpp'];
    var filesWalked = listSourceFiles(extensions, {'.github'}, {});
    var filesFromDiff = parseDiff(
      File('test/HEAD..f9fd74.diff').readAsStringSync(),
    );
    filterOutNonSourceFiles(filesFromDiff, extensions, {'.github'}, {}, true);
    // instances of `FileObj` will differ, but the List.length should be equal
    expect(filesWalked.length, filesFromDiff.length);
  });

  /*
   * This test basically does what main() in bin/cpp_linter_dart.dart does.
   * Here we limit the input options (see the List of parsed args below).
   */
  test('main-mock', () async {
    final argParser = getParser();
    var args = argParser.parse(
      [
        '--version',
        String.fromEnvironment('CLANG_TOOLS_VERSION', defaultValue: '12'),
        '--verbosity', // enable debug output
        '-p', // database path
        'test/demo', // will be made absolute
        '--', // the rest will be clang-tidy extra-args
        '--std=cxx14',
      ],
    );
    final ext = (args['extensions'] as String)
        .split(',')
        .map((e) => e.startsWith('.') ? e : '.$e')
        .toList();
    final (ignored, notIgnored) = parseIgnoredOption(args['ignore']);
    final files = listSourceFiles(ext, ignored, notIgnored);
    Directory('.cpp_linter_cache').createSync();
    final (formatAdvice, _, tidyNotes) = await captureClangToolsOutput(
      files,
      args['version'],
      args['lines-changed-only'],
      args['style'],
      args['tidy-checks'],
      args['database'],
      args.rest,
      args['verbosity'],
    );
    expect(
      tidyNotes.map((element) => element.file.name).toSet().toList(),
      ['test/demo/demo.cpp', 'test/demo/demo.hpp'],
    );
    expect(
      formatAdvice.map((element) => element.file.name).toSet().toList(),
      ['test/demo/demo.cpp', 'test/demo/demo.hpp'],
    );
  });

  /*
   * This test runs actual main() in bin/cpp_linter_dart.dart
   * Since the function only output a exit code, introspection isn't
   * suitable here. Instead, we'll just just assert that the exit code is as
   * expected.
   */
  test('main-actual', () async {
    expect(await bin.main(['--help']), 0);
    expect(await bin.main([]), 8);
  });
}
