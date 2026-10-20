"""Exercise the exact C layout function used by the dylib, via a native test DLL."""
import ctypes
import os
import re
import subprocess
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Geometry(ctypes.Structure):
    _fields_ = [(name, ctypes.c_double) for name in ('rowY', 'shift', 'accountY', 'contentHeight')]


version = re.search(r'#define NC_VERSION @"([^"]+)"', (ROOT/'Sources/NCAdShield.h').read_text(encoding='utf-8')).group(1)
library_path = ROOT/'build'/version/'menu-geometry-test.dll'
source = ROOT/'Sources/NCMenuGeometry.c'
support = ROOT/'tools/windows_geometry_support.c'
if not library_path.exists() or max(source.stat().st_mtime, support.stat().st_mtime) > library_path.stat().st_mtime:
    library_path.parent.mkdir(parents=True, exist_ok=True)
    compiler = Path(os.environ.get('NC_LLVM_BIN', ROOT.parent/'.toolchain-cache/LLVM/bin'))/'clang.exe'
    subprocess.run([str(compiler), '--target=x86_64-pc-windows-msvc', '-O2', '-shared', '-nostdlib', '-fuse-ld=lld',
                    '-Xlinker', '/NOENTRY', '-Xlinker', '/EXPORT:NCMenuGeometryCompute',
                    str(source), str(support), '-o', str(library_path)], check=True)
library = ctypes.CDLL(str(library_path))
compute = library.NCMenuGeometryCompute
compute.argtypes = [ctypes.c_double] * 5 + [ctypes.POINTER(Geometry)]
compute.restype = ctypes.c_int


class MenuGeometryTests(unittest.TestCase):
    def place(self, y=16, previous=0, height=48, gap=16, content=700):
        result = Geometry()
        self.assertEqual(compute(y, previous, height, gap, content, ctypes.byref(result)), 1)
        self.assertAlmostEqual(result.rowY + height + gap, result.accountY)
        return result

    def test_first_row_is_above_account(self):
        g = self.place()
        self.assertEqual((g.rowY, g.shift, g.accountY, g.contentHeight), (16, 64, 80, 764))

    def test_repeated_layout_never_accumulates(self):
        g = self.place()
        for _ in range(1000):
            g = self.place(g.accountY, g.shift)
            self.assertEqual((g.rowY, g.shift, g.contentHeight), (16, 64, 764))

    def test_orientation_and_dynamic_row_height(self):
        g = self.place(y=80, previous=64, height=56, content=820)
        self.assertEqual((g.rowY, g.shift, g.accountY, g.contentHeight), (16, 72, 88, 892))

    def test_reentry_after_restoring_transform(self):
        g = self.place(previous=0)
        self.assertEqual((g.rowY, g.accountY), (16, 80))

    def test_rn_resets_position_without_duplicating_shift(self):
        g = self.place(y=24, previous=0)
        self.assertEqual((g.rowY, g.accountY, g.shift), (24, 88, 64))

    def test_invalid_or_nonfinite_input_is_rejected(self):
        for values in [(16, 0, 0, 16, 700), (16, 0, 150, 16, 700),
                       (16, 0, 48, -1, 700), (float('nan'), 0, 48, 16, 700),
                       (16, 0, 48, 16, float('inf'))]:
            self.assertEqual(compute(*values, ctypes.byref(Geometry())), 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
