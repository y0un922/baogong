import 'dart:convert';
import 'dart:io';

import 'package:baocode/models/pi_upstreams.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // This diagnostic reads the user's real setup, which CI does not have.
  test('their own pi setup', () {
    final file = PiUpstreams.file();
    // ignore: avoid_print
    print('file: ${file.path} exists=${file.existsSync()}');
    final (:taken, :skipped) = PiUpstreams.parse(
      jsonDecode(file.readAsStringSync()),
    );
    for (final entry in taken) {
      // ignore: avoid_print
      print(
        '+ ${entry.upstream.name} [${entry.upstream.protocol.id}] '
        '${entry.upstream.baseUrl} '
        'key=${entry.upstream.key.isEmpty ? 'none' : 'yes'} '
        'models=${entry.models.length}: '
        '${entry.models.take(5).map((m) => m.id).join(', ')}',
      );
    }
    // ignore: avoid_print
    print('skipped: $skipped');
  }, skip: Platform.environment['BAOCODE_TEST_PI_SETUP'] != '1');
}
