import 'package:test/test.dart';
import 'package:cpp_linter_dart/logger.dart';

void main() {
  setUp(() => setupLoggers(true));
  test('setExitCode()', () {
    expect(setExitCode(42), 42);
  });
}
