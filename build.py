"""Build with standard Clang/LLD; never patch or re-sign linked bytes."""
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
WORKSPACE = ROOT.parent
LLVM = Path(os.environ.get('NC_LLVM_BIN', WORKSPACE / '.toolchain-cache/LLVM/bin'))
SDK = Path(os.environ.get('NC_IOS_SDK', WORKSPACE / '.toolchain-cache/SDK/iPhoneOS16.5.sdk'))
VERSION = re.search(r'#define NC_VERSION @"([0-9A-Za-z.-]+)"', (ROOT / 'Sources/NCAdShield.h').read_text(encoding='utf-8')).group(1)
OUT = ROOT / 'build' / VERSION
OBJECTS = OUT / 'objects'
OBJECTS.mkdir(parents=True, exist_ok=True)
ARTIFACT = OUT / f'music163_cads-{VERSION}.dylib'
LOG = OUT / 'build.log'
LOG.write_text('Fresh source, standard LLVM, no binary postprocessing\n', encoding='utf-8')


def run(args):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, encoding='utf-8', errors='replace')
    with LOG.open('a', encoding='utf-8') as stream:
        stream.write(json.dumps([str(a) for a in args], ensure_ascii=False) + '\n')
        stream.write(result.stdout + result.stderr)
    if result.returncode:
        print(result.stdout + result.stderr)
        raise SystemExit(result.returncode)
    return result.stdout


objects = []
for source in sorted(p for p in (ROOT / 'Sources').iterdir() if p.suffix in ('.m', '.c')):
    print('Compile', source.name, flush=True)
    obj = OBJECTS / (source.stem + '.o')
    run([LLVM / 'clang.exe', '--target=arm64-apple-ios13.0', '-isysroot', SDK,
         *(['-fobjc-arc'] if source.suffix == '.m' else []), '-fblocks', '-fvisibility=hidden', '-O2', '-g0',
         '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
         '-Wno-deprecated-declarations', '-c', source, '-o', obj])
    objects.append(obj)

run([LLVM / 'ld64.lld.exe', '-arch', 'arm64', '-dylib', '-platform_version', 'ios', '13.0', '16.5',
     '-syslibroot', SDK, '-install_name', '@rpath/music163_cads.dylib', '-current_version', '2.0.0',
     '-compatibility_version', '2.0.0', '-adhoc_codesign', '-dead_strip', '-o', ARTIFACT,
     *objects, '-lSystem', '-lobjc', '-framework', 'Foundation', '-framework', 'UIKit',
     '-framework', 'UserNotifications', '-framework', 'QuartzCore', '-framework', 'CoreGraphics'])

run([sys.executable, '-X', 'utf8', ROOT / 'tools/audit_macho.py', ARTIFACT, '--json-out', OUT / 'macho-audit.json'])
for options, output in [(['--private-headers'], 'headers.txt'),
                        (['--bind', '--weak-bind', '--lazy-bind', '--rebase', '--exports-trie'], 'dyld-tables.txt'),
                        (['--syms'], 'symbols.txt')]:
    (OUT / output).write_text(run([LLVM / 'llvm-objdump.exe', '--macho', *options, ARTIFACT]), encoding='utf-8')

data = ARTIFACT.read_bytes()
info = dict(artifact=ARTIFACT.name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
            target='arm64-apple-ios13.0', intended_app='9.6.09 (7516)',
            version=VERSION, compiler=run([LLVM / 'clang.exe', '--version']).splitlines()[0],
            linker=run([LLVM / 'ld64.lld.exe', '--version']).strip(),
            sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in sorted((ROOT / 'Sources').glob('*')) if p.is_file()},
            device_tested=False)
(OUT / 'build-info.json').write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(info, ensure_ascii=False, indent=2))
