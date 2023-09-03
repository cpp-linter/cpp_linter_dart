import 'package:cpp_linter_dart/common.dart';
import 'package:test/test.dart';
import 'dart:io';

void main() {
  test('makeExeName', () {
    expect(
      makeClangToolExeVersion('clang-tidy', '12'),
      'clang-tidy${Platform.isWindows ? '.exe' : '-12'}',
    );
  });
}
