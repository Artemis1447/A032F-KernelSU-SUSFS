#!/usr/bin/env python3
"""Gate and package only the combined SM-A032F V19 build on the CI runner."""
import csv
import difflib
import gzip
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def require(test, detail):
    if not test:
        raise SystemExit(detail)


root = Path(__file__).resolve().parents[1]
work = Path(os.environ['WORKSPACE'])
kernel = work / 'android-kernel'
out = kernel / 'out'
diag = work / 'abi-diagnostics'
image = out / 'arch/arm64/boot/Image'
base = root / 'config/v19/v17.config'
config = (diag / 'kernel.config').read_bytes()
old = base.read_bytes()
name = os.environ['KERNEL_NAME']
require(name == 'a3core-v19-extreme-sukisu-susfs', 'wrong V19 profile')
require(sha(base) == 'ef0f1dac51319a6a0dcb8cb203c38ffe86168074f5711837a32aa88fdbfefc9f', 'wrong V17 config')
require(config == old.replace(b'-a3core-vendorabi-v17-sukisu-susfs', ('-' + name).encode()), 'unexpected config delta')
(diag / 'config.diff').write_text(''.join(difflib.unified_diff(old.decode().splitlines(True), config.decode().splitlines(True), 'V17', 'V19')))
require(sha(diag / 'Module.symvers') == 'd035818a6ee36082afdd1ec0693fe2b9aec2681e8ab8950807a74826acb45994', 'Module.symvers differs from verified V17')
with (diag / 'pvrsrvkm-crc-comparison.tsv').open() as f:
    crcs = list(csv.DictReader(f, delimiter='\t'))
require(len(crcs) == 267 and all(r['status'] == 'MATCH' for r in crcs), 'vendor GPU ABI mismatch')
raw = image.read_bytes()
require(raw[56:60] == b'ARM\x64' and ('Linux version 4.14.199-' + name + ' ').encode() in raw, 'wrong Image')
start = raw.index(b'IKCFG_ST') + 8
require(gzip.decompress(raw[start:raw.index(b'IKCFG_ED', start)]) == config, 'linked IKCONFIG mismatch')
compiler = subprocess.check_output([Path(os.environ['CLANG_PATH']) / 'clang', '--version'], text=True)
require('6443078 based on r383902' in compiler and b'r383902) clang version 11.0.1' in raw, 'wrong compiler')
(diag / 'compiler.txt').write_text(compiler)
for line in (root / 'config/v19-reference-sources.sha256').read_text().splitlines():
    expected, file = line.split('  ', 1)
    require(sha(kernel / file) == expected, 'V17 integration drift: ' + file)
require(not list(kernel.rglob('*.rej')), 'patch rejects in integrated tree')
series = sorted((root / 'patches/v19').glob('*.patch'))
expected_blobs = {}
for patch in series:
    m = re.search(r'^index [0-9a-f]+\.\.([0-9a-f]{40}).*?^\+\+\+ b/([^\n]+)$', patch.read_text().split('@@')[0], re.M | re.S)
    require(m, 'missing full patch index: ' + patch.name)
    expected_blobs[m[2].strip()] = m[1]
for path, blob in expected_blobs.items():
    require(subprocess.check_output(['git','hash-object',kernel / path], text=True).strip() == blob, 'source differs: ' + path)
stamp = os.environ['BUILD_TIME']
ak = diag / ('AnyKernel3-V19-' + stamp + '.zip')
subprocess.run(['zip','-qr','-y',ak,'.'], cwd=work / 'AnyKernel3', check=True)
source = diag / 'v19-source.tar.gz'
subprocess.run(['tar','--exclude=.git','--exclude=./out','-czf',source,'-C',kernel,'.'], check=True)
manifest = {'version':name, 'build':stamp, 'recipe_commit':os.environ['GITHUB_SHA'], 'run_id':os.environ['GITHUB_RUN_ID'],
            'kernel_base':os.environ['KERNEL_SOURCE_COMMIT'], 'ksu':os.environ['KSU_REF'], 'susfs':os.environ['SUSFS_COMMIT'],
            'compiler':compiler.splitlines()[0], 'gpu_crc_matches':267, 'symvers_matches_v17':True, 'config_delta':'LOCALVERSION only',
            'source_blobs':expected_blobs, 'patches':{p.name:sha(p) for p in series}, 'v19_hardware_tested':False}
(diag / 'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
files = [image] + sorted(p for p in diag.iterdir() if p.is_file() and p.name != 'SHA256SUMS.txt')
(diag / 'SHA256SUMS.txt').write_text(''.join(f'{sha(f)}  {f.name}\n' for f in files))
