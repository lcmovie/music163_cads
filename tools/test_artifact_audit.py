"""Regression cases for the failures found in the legacy handoff artifact."""
import struct
import os
import re
import tempfile
import unittest
from pathlib import Path
from audit_macho import audit

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.search(r'#define NC_VERSION @"([^"]+)"', (ROOT / 'Sources/NCAdShield.h').read_text(encoding='utf-8')).group(1)
GOOD = Path(os.environ.get('NC_TEST_ARTIFACT', ROOT / f'build/{VERSION}/music163_cads-{VERSION}.dylib'))
BAD = os.environ.get('NC_TEST_LEGACY_ARTIFACT')


class ArtifactAuditTests(unittest.TestCase):
    def check_changed(self, mutate):
        data = bytearray(GOOD.read_bytes())
        mutate(data, audit(GOOD))
        with tempfile.TemporaryDirectory(prefix='music163-audit-') as directory:
            path = Path(directory) / 'changed.dylib'
            path.write_bytes(data)
            return audit(path)

    def test_standard_linker_output_passes(self):
        result = audit(GOOD)
        self.assertTrue(result['passed'], result['errors'])
        self.assertTrue(result['uuid'])
        self.assertTrue(result['dependencies'])

    @unittest.skipUnless(BAD, 'Optional legacy fixture: set NC_TEST_LEGACY_ARTIFACT')
    def test_legacy_failures_are_detected_independently(self):
        errors = '\n'.join(audit(BAD)['errors'])
        for expected in ('LC_DYSYMTAB size 64', 'LC_ID_DYLIB invalid', 'outside __LINKEDIT', 'SHA256 code page mismatch'):
            self.assertIn(expected, errors)

    def test_last_partial_page_is_actually_checked(self):
        def mutate(data, info):
            data[info['signature']['code_limit'] - 1] ^= 1
        self.assertIn('SHA256 code page mismatch', '\n'.join(self.check_changed(mutate)['errors']))

    def test_signature_must_be_inside_linkedit(self):
        def mutate(data, info):
            cmd = next(c for c in info['commands'] if c['command'] == '0x19' and data[c['offset'] + 8:c['offset'] + 24].startswith(b'__LINKEDIT'))
            fileoff = struct.unpack_from('<Q', data, cmd['offset'] + 40)[0]
            struct.pack_into('<Q', data, cmd['offset'] + 48, info['signature']['offset'] - fileoff)
        self.assertIn('Code signature outside __LINKEDIT', '\n'.join(self.check_changed(mutate)['errors']))

    def test_symbol_command_ids_cannot_be_swapped(self):
        def mutate(data, info):
            for cmd in info['commands']:
                if cmd['command'] in ('0xb', '0xd'):
                    struct.pack_into('<I', data, cmd['offset'], 0xd if cmd['command'] == '0xb' else 0xb)
        self.assertFalse(self.check_changed(mutate)['passed'])

    def test_corrupt_load_command_chain_fails(self):
        def mutate(data, info):
            struct.pack_into('<I', data, 36, 7)
        self.assertIn('Invalid load command length', '\n'.join(self.check_changed(mutate)['errors']))


if __name__ == '__main__':
    unittest.main(verbosity=2)
