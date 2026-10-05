import 'package:flutter_test/flutter_test.dart';

import '../../tool/cdm/browser_output_trace.dart';

void main() {
  test('reports only status and validated numeric masks', () {
    expect(
      outputProtectionTraceResult({
        'name': 'CdmAdapter::OnQueryOutputProtectionStatusDone',
        'args': {
          'success': true,
          'link_mask, protection_mask': '0x08, 0x01',
          'session_id': 'must-not-escape',
        },
      }),
      {'success': true, 'link_mask': 8, 'protection_mask': 1},
    );
  });

  test('does not expose arbitrary trace arguments or malformed masks', () {
    expect(
      outputProtectionTraceResult({
        'name': 'CdmAdapter::OnQueryOutputProtectionStatusDone',
        'args': {'success': false, 'link_mask, protection_mask': 'opaque-data'},
      }),
      {'success': false},
    );
    expect(
      outputProtectionTraceResult({
        'name': 'OnSessionMessage',
        'args': {'message': 'opaque-data'},
      }),
      isNull,
    );
    expect(
      outputProtectionTraceResult({
        'name': 'CdmAdapter::OnQueryOutputProtectionStatusDone',
        'args': {'success': 'opaque-data'},
      }),
      isNull,
    );
  });
}
