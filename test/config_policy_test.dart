import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Standing rule #1 (docs/IPHONE_BEACON_COMPLETION_HANDOFF.md §16.4): any
// value that decides whether a production code path runs must resolve
// identically in debug, profile, and release. In this codebase that means
// AppConfig._env() (dart-define first, dotenv second) — never a direct
// dotenv read outside config/bootstrap, and never an assert-stripped API.
//
// Two production incidents motivate pinning this at source level:
//  - BindingBase.debugBindingType() is assigned inside an assert block, so
//    it is null in release/profile — gating the native location coordinator
//    on it disabled the feature on every real device while tests stayed
//    green (106a619).
//  - INRANGE_SUBTLE_WAKE was read via dotenv.maybeGet directly; release
//    builds load only .env.example into dotenv, so the whole wake stack was
//    silently false in every release build (f6bf21e).
//
// A behavioural test cannot catch either class — `flutter test` always runs
// with asserts on and with dotenv fully loaded. Walking the sources can.
void main() {
  // Files allowed to touch dotenv: the config owner (app_config) and the
  // bootstrap loader (main). Everything else must go through AppConfig.
  const allowedDotenv = <String>{
    'lib/core/config/app_config.dart',
    'lib/main.dart',
  };

  Iterable<File> dartFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  String stripComments(String src) => src
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('no direct dotenv reads outside config/bootstrap', () {
    final offenders = <String>[];
    for (final f in dartFiles()) {
      if (allowedDotenv.any((a) => f.path.endsWith(a))) continue;
      final code = stripComments(f.readAsStringSync());
      if (code.contains('dotenv.maybeGet') ||
          code.contains('dotenv.env[') ||
          code.contains('dotenv.get')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'feature flags read through AppConfig._env() so dart-define '
            'wins in release; a direct dotenv read is silently false there');
  });

  test('no assert-stripped debug APIs gate production paths', () {
    final offenders = <String>[];
    for (final f in dartFiles()) {
      final code = stripComments(f.readAsStringSync());
      if (code.contains('debugBindingType')) offenders.add(f.path);
    }
    expect(offenders, isEmpty,
        reason: 'debugBindingType() is null in release/profile — gating on '
            'it disables the path on every real device');
  });
}
