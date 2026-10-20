import json, os, plistlib, re, subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
version = re.search(r'#define NC_VERSION @"([^"]+)"', (root/'Sources/NCAdShield.h').read_text(encoding='utf-8')).group(1)
out = root/'build'/version/'analyzer'
out.mkdir(parents=True, exist_ok=True)
compiler = Path(os.environ.get('NC_LLVM_BIN', root.parent/'.toolchain-cache/LLVM/bin'))/'clang.exe'
sdk = Path(os.environ.get('NC_IOS_SDK', root.parent/'.toolchain-cache/SDK/iPhoneOS16.5.sdk'))
results = []
for source in sorted(p for p in (root/'Sources').iterdir() if p.suffix in ('.m', '.c')):
    report = out/(source.stem+'.plist')
    args = [str(compiler), '--analyze', '--target=arm64-apple-ios13.0', '-isysroot', str(sdk), '-fblocks', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter', '-Wno-deprecated-declarations']
    if source.suffix == '.m': args += ['-fobjc-arc']
    process = subprocess.run(args+[str(source), '-o', str(report)], capture_output=True, text=True, encoding='utf-8', errors='replace')
    diagnostics = plistlib.loads(report.read_bytes())['diagnostics'] if report.exists() else [dict(description='Report missing')]
    print(source.name, 'exit', process.returncode, 'diagnostics', len(diagnostics), flush=True)
    if process.stdout or process.stderr: print(process.stdout+process.stderr)
    results.append(dict(source=source.name, returncode=process.returncode, diagnostics=len(diagnostics)))
    assert process.returncode == 0 and not diagnostics, source
(out.parent/'analyzer-summary.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
