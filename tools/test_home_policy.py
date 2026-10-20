"""Run the exact shipped C policy, including a sweep of original App defaults."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.search(r'#define NC_VERSION @"([^"]+)"', (ROOT/'Sources/NCAdShield.h').read_text(encoding='utf-8')).group(1)
OUT = ROOT/'build'/VERSION
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = ROOT/'Sources/NCHomePolicy.c'
LIBRARY = OUT/'home-policy-test.dll'
COMPILER = Path(os.environ.get('NC_LLVM_BIN', ROOT.parent/'.toolchain-cache/LLVM/bin'))/'clang.exe'
subprocess.run([str(COMPILER), '--target=x86_64-pc-windows-msvc', '-O2', '-shared', '-nostdlib', '-fuse-ld=lld',
                '-Xlinker', '/NOENTRY', '-Xlinker', '/EXPORT:NCHomeTextEvidence', '-Xlinker', '/EXPORT:NCHomeMusicResource',
                str(SOURCE), '-o', str(LIBRARY)], check=True)
LIB = ctypes.CDLL(str(LIBRARY))
LIB.NCHomeTextEvidence.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
LIB.NCHomeTextEvidence.restype = ctypes.c_uint
LIB.NCHomeMusicResource.argtypes = [ctypes.c_char_p]
LIB.NCHomeMusicResource.restype = ctypes.c_int

def classify(field, text):
    return LIB.NCHomeTextEvidence(field.encode(), text.encode())

class HomePolicyTests(unittest.TestCase):
    def test_reported_cash_card_and_promotion_labels(self):
        for text in ['云贝免费领现金红包 >', '云贝中心每日领现金红包', '云贝现金福利']:
            self.assertEqual(classify('title', text), 2)
        for field in ['adTag', 'tagText', 'label', 'text']:
            self.assertEqual(classify(field, '运营推广'), 1)
        self.assertEqual(classify('adTag', '广告'), 1)

    def test_normal_home_music_and_yunbei_entry_are_preserved(self):
        for text in ['每日推荐', '热歌榜', '榜单推荐', '推荐歌单', '云贝中心', '云贝签到', '免费领红包', '现金红包', '广告']:
            self.assertEqual(classify('title', text), 0, text)
        for kind in ['song','music','playList','playlist','album','artist','mv','djRadio','djProgram']:
            self.assertEqual(LIB.NCHomeMusicResource(kind.encode()), 1)
        self.assertEqual(LIB.NCHomeMusicResource(b'unknown'), 0)

    def test_urls_template_source_and_unknown_fields_are_not_evidence(self):
        for field in ['url','action','coverImg','css','json','databinding','unknown']:
            self.assertEqual(classify(field, '云贝免费领现金红包'), 0)
            self.assertEqual(classify(field, '运营推广'), 0)
        self.assertEqual(classify('title', '普通歌曲：运营推广的故事'), 0)
        self.assertEqual(classify('resourceType', 'playList'), 0)
        self.assertEqual(classify('resourceType', 'advertisement'), 4)

    def test_null_empty_and_long_metadata(self):
        self.assertEqual(LIB.NCHomeTextEvidence(None, b'title'), 0)
        self.assertEqual(LIB.NCHomeTextEvidence(b'title', None), 0)
        self.assertEqual(LIB.NCHomeMusicResource(None), 0)
        for value in ['', 'a'*512, '云贝'*200, '领现金'*100]:
            self.assertEqual(classify('title', value), 0)

    @unittest.skipUnless((ROOT/'evidence/app-9.6.09/rcmd_first_page_data.json').exists(), 'Original App defaults not distributed')
    def test_original_bundled_music_defaults_do_not_match(self):
        checked = 0
        def visit(value):
            nonlocal checked
            if isinstance(value, dict):
                for k,v in value.items():
                    if isinstance(v,str):
                        self.assertEqual(classify(k,v),0,(k,v[:80]));checked+=1
                    elif isinstance(v,(dict,list)):visit(v)
            elif isinstance(value,list):
                for v in value:visit(v)
        for name in ['rcmd_first_page_data.json','music_first_page_data.json']:
            visit(json.loads((ROOT/'evidence/app-9.6.09'/name).read_text(encoding='utf-8')))
        self.assertGreater(checked,100)
        self.__class__.default_fields_checked=checked

if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(HomePolicyTests))
    record=dict(passed=result.wasSuccessful(),tests=result.testsRun,skipped=len(result.skipped),
                bundled_default_string_fields=getattr(HomePolicyTests,'default_fields_checked',0),
                source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                scope='Exact C predicate and original bundled defaults; not UIKit, ObjC traversal, or live cache/network execution')
    (OUT/'home-policy-tests.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    raise SystemExit(0 if result.wasSuccessful() else 1)
