"""Exercise the exact C SemVer function compiled into the iOS plugin."""
import ctypes,hashlib,json,os,random,re,subprocess,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
version=re.search(r'#define NC_VERSION @"([^"]+)"',(ROOT/'Sources/NCAdShield.h').read_text(encoding='utf-8')).group(1)
library=ROOT/'build'/version/'version-compare-test.dll'
source=ROOT/'Sources/NCVersionCompare.c'
if not library.exists() or source.stat().st_mtime>library.stat().st_mtime:
    library.parent.mkdir(parents=True,exist_ok=True)
    compiler=Path(os.environ.get('NC_LLVM_BIN',ROOT.parent/'.toolchain-cache/LLVM/bin'))/'clang.exe'
    subprocess.run([str(compiler),'--target=x86_64-pc-windows-msvc','-O2','-shared','-nostdlib','-fuse-ld=lld','-Xlinker','/NOENTRY','-Xlinker','/EXPORT:NCCompareVersions',str(source),'-o',str(library)],check=True)
dll=ctypes.CDLL(str(library))
compare=dll.NCCompareVersions
compare.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.POINTER(ctypes.c_int)]
compare.restype=ctypes.c_int
checks=0
def actual(a,b):
    global checks
    out=ctypes.c_int(99)
    assert compare(a.encode(),b.encode(),ctypes.byref(out))==1,(a,b)
    checks+=1
    return out.value
def reference(a,b):
    def parse(v):
        v=v.lstrip('vV').split('+',1)[0]
        core,sep,pre=v.partition('-')
        return tuple(map(int,core.split('.'))),pre.split('.') if sep else []
    aa,ap=parse(a);bb,bp=parse(b)
    if aa!=bb:return (aa>bb)-(aa<bb)
    if not ap or not bp:return (not ap)-(not bp)
    for a,b in zip(ap,bp):
        if a==b:continue
        an,bn=a.isdigit(),b.isdigit()
        if an and bn:return (int(a)>int(b))-(int(a)<int(b))
        if an!=bn:return -1 if an else 1
        return (a>b)-(a<b)
    return (len(ap)>len(bp))-(len(ap)<len(bp))
class VersionTests(unittest.TestCase):
    def test_spec_precedence_and_test_numbers(self):
        ordered=['1.0.0-alpha','1.0.0-alpha.1','1.0.0-alpha.beta','1.0.0-beta','1.0.0-beta.2','1.0.0-beta.11','1.0.0-rc.1','1.0.0',
                 '2.0.0-test.4','2.0.0-test.5','2.0.0-test.9','2.0.0-test.10','2.0.0','2.0.1']
        for i,a in enumerate(ordered):
            for j,b in enumerate(ordered):self.assertEqual(actual(a,b),(i>j)-(i<j),(a,b))
    def test_equal_prefix_build_and_large_numbers(self):
        for a,b in [('v2.0.0','2.0.0'),('V2.0.0-test.5','2.0.0-test.5'),('1.0.0+build.001','1.0.0+build.002'),
                    ('1.0.0-1+one','1.0.0-1+two')]:
            self.assertEqual(actual(a,b),0)
        self.assertEqual(actual('999999999999999999999999.0.0','999999999999999999999998.9.9'),1)
    def test_invalid_tags_and_nulls(self):
        values=['','1','1.0','1.0.0.1','01.0.0','1.01.0','1.0.01','1.0.0-','1.0.0+','1.0.0-alpha..1',
                '1.0.0-01','1.0.0-rc.01','1.0.0+abc..def','v','vv1.0.0','release-1.0.0','1.0.0_1',
                ' 1.0.0','1.0.0 ','1.0.0-中文','1.0.0+'+'x'*129]
        for value in values:
            for a,b in [(value,'1.0.0'),('1.0.0',value)]:
                out=ctypes.c_int(99)
                self.assertEqual(compare(a.encode(),b.encode(),ctypes.byref(out)),0,(a,b))
                self.assertEqual(out.value,99)
        out=ctypes.c_int()
        self.assertEqual(compare(None,b'1.0.0',ctypes.byref(out)),0)
        self.assertEqual(compare(b'1.0.0',None,ctypes.byref(out)),0)
        self.assertEqual(compare(b'1.0.0',b'1.0.0',None),0)
    def test_differential_random_versions(self):
        random.seed(163)
        def generate():
            v='.'.join(str(random.randrange(0,200)) for _ in range(3))
            if random.randrange(3):
                segments=[random.choice([str(random.randrange(0,200)),random.choice(['test','alpha','beta','rc','a-b'])]) for _ in range(random.randrange(1,5))]
                v+='-' + '.'.join(segments)
            if random.randrange(2):v+='+build.'+str(random.randrange(200))
            return random.choice(['','v'])+v
        for _ in range(4000):
            a,b=generate(),generate()
            self.assertEqual(actual(a,b),reference(a,b),(a,b))
            self.assertEqual(actual(b,a),-reference(a,b),(a,b))
if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(VersionTests))
    record=dict(passed=result.wasSuccessful(),tests=result.testsRun,valid_comparisons=checks,invalid_cases=45,
                source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),test_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),
                scope='Exact C version comparison; not an iOS UI or network integration test')
    (ROOT/'build'/version/'version-tests.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    raise SystemExit(0 if result.wasSuccessful() else 1)
