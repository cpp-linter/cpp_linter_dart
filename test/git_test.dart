// Dart imports:
import 'dart:io';

// Package imports:
import 'package:test/test.dart';

// Project imports:
import 'package:cpp_linter_dart/git.dart';

void main() {
  test("getSha", () async {
    var sha = await getSha();
    assert(RegExp(r'[0-9a-fA-F]{40}').matchAsPrefix(sha.trim()) != null);
  });
  test(
    "getDiff",
    () async {
      var diff = await getDiff(false);
      assert(diff.isNotEmpty);
    },
    skip: 'getDiff() only works on locally staged changes.',
  );
  test('parseDiff', () async {
    var diff = await File('test/HEAD..f9fd74.diff').readAsString();
    var files = parseDiff(diff);
    assert(files.length == 24);
    for (final file in files) {
      assert(file.additions.isNotEmpty); // verifies parsePatch()
      assert(file.linesAdded.isNotEmpty); // verifies parsePatch()
      assert(!file.name.contains('\\')); // getFileNameFromFrontMatter()
    }
  });

  test('consolidateListToRanges', () {
    <List<int>, List<List<int>>>{
      [1, 2, 3]: [
        [1, 4]
      ],
      [1, 3, 5]: [
        [1, 2],
        [3, 4],
        [5, 6],
      ],
    }.forEach((key, value) => expect(consolidateListToRanges(key), value));
  });
}
