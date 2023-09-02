// Dart imports:
import 'dart:io';

// Package imports:
import 'package:test/test.dart';

// Project imports:
import 'package:cpp_linter_dart/git.dart';
import 'package:cpp_linter_dart/run.dart';

void main() {
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
}
