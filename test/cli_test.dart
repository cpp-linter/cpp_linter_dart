import 'package:test/test.dart';
import 'package:cpp_linter_dart/cli.dart';

void main() {
  test('validate flags', () {
    var argParser = getParser();
    <String, (String, dynamic)>{
      // <abbreviated option>: (<full option name>, <expected value>)
      '-h': ('help', true),
      '-v': ('verbosity', true),
      '-l': ('lines-changed-only', true),
      '-f': ('files-changed-only', true),
      '-w': ('step-summary', true),
      '-a': ('file-annotations', true),
      '-g': ('lgtm', true),
    }.forEach(
      (key, value) {
        expect(argParser.parse(['cpp-linter', key])[value.$1], value.$2);
      },
    );
  });

  test('validate options', () {
    var argParser = getParser();
    <(String, String), (String, String)>{
      ('-p', 'path'): ('database', 'path'),
      ('-s', 'file'): ('style', 'file'),
      ('-t', '-*'): ('tidy-checks', '-*'),
      ('-V', '12'): ('version', '12'),
      ('-e', 'cpp,hpp'): ('extensions', 'cpp,hpp'),
      ('-r', 'path'): ('repo-root', 'path'),
      ('-i', 'file|!path'): ('ignore', 'file|!path'),
      ('-c', 'update'): ('thread-comments', 'update'),
    }.forEach((key, value) {
      expect(
        argParser.parse(['cpp-linter', key.$1, key.$2])[value.$1],
        value.$2,
      );
    });
  });
}
