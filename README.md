<!-- markdownlint-disable MD001 MD041 -->
[![Dart](https://github.com/cpp-linter/cpp_linter_dart/actions/workflows/dart.yml/badge.svg)](https://github.com/cpp-linter/cpp_linter_dart/actions/workflows/dart.yml)
[![code coverage](https://codecov.io/gh/cpp-linter/cpp_linter_dart/graph/badge.svg?token=iXV4BqcvQy)](https://codecov.io/gh/cpp-linter/cpp_linter_dart)

# cpp_linter_dart

This is an experimental port of the
[cpp-linter python package](https://github.com/cpp-linter/cpp-linter). Like the
python package, this dart package is not meant to be used as a importable library.
Although, some library parts may be useful to other applications. For example,
`lib/git.dart` can be used to parse a diff into a `List<FileObj>` that describes a file's changed lines.

This dart port is meant to optimize away any runtime compilation. By using dart, we
can ship a binary executable (native to Linux, Windows, or MacOS) instead of
downloading executable scripts from pypi.

The application entrypoint's source is in `bin/`, and the application's library code
is in `lib/`. Unit tests are in `test/` which are used to calculate code coverage and detect bugs early.
