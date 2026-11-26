#!/usr/bin/env python3
"""Verify the linked Image, embedded config, integrated source and GPU ABI from the V18 CI run."""

import argparse
import gzip
import hashlib
import json
import re
import subprocess
import sys
import tarfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_CONFIG = 'ef0f1dac51319a6a0dcb8cb203c38ffe86168074f5711837a32aa88fdbfefc9f'
V17 = '4.14.199-a3core-vendorabi-v17-sukisu-susfs'
V18 = V17.replace('v17', 'v18')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('artifacts', type=Path, help='directory populated by gh run download')
    ap.add_argument('v17_config', type=Path, help='original V17 IKCONFIG or release CI kernel.config')
    ap.add_argument('report', type=Path)
    args = ap.parse_args()
    abi, = args.artifacts.glob('pvrsrvkm-ABI-*')
    path, = args.artifacts.glob('Image-*/Image')
    image = path.read_bytes()
    require(image[56:60] == b'ARM\x64', 'not an uncompressed arm64 Image')
    require(('Linux version ' + V18 + ' ').encode() in image, 'wrong kernel release')
    require(b'r383902) clang version 11.0.1' in image, 'unexpected compiler')
    require(b'ord 8:%d, 4:%d, 0:%d' not in image, 'old ION per-buffer report is present')
    start = image.index(b'IKCFG_ST') + 8
    config = gzip.decompress(image[start:image.index(b'IKCFG_ED', start)])
    require(config == (abi / 'kernel.config').read_bytes(), 'linked IKCONFIG differs from CI config')
    old = args.v17_config.read_bytes()
    require(hashlib.sha256(old).hexdigest() == EXPECTED_CONFIG, 'unexpected V17 config')
    old_line = ('CONFIG_LOCALVERSION="-' + V17.split('-', 1)[1] + '"').encode()
    new_line = old_line.replace(b'v17', b'v18')
    require(old.count(old_line) == 1 and old.replace(old_line, new_line) == config,
            'unexpected config delta; inspect before installing')

    source = abi / 'v18-source.tar.gz'
    targets = {}
    for patch in sorted((ROOT / 'patches/v18').glob('*.patch')):
        text = patch.read_text(encoding='utf-8')
        name = re.search(r'^\+\+\+ b/(.+)$', text, re.M).group(1)
        targets[name] = re.search(r'^index [0-9a-f]+\.\.([0-9a-f]+)', text, re.M).group(1)
    require(len(targets) == 3, 'V18 patch set missing')
    required = {'fs/susfs.c', 'include/linux/susfs.h', 'KernelSU/kernel/Kconfig',
                'arch/arm64/configs/a3core_eur_open_defconfig'}
    verified = {}
    # Stream the archive once; Linux symlinks/case-collisions need no extraction on Windows.
    with tarfile.open(source, 'r|gz') as archive:
        for entry in archive:
            name = entry.name.removeprefix('./')
            required.discard(name)
            if name in targets:
                data = archive.extractfile(entry).read()
                blob = hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()
                require(blob.startswith(targets[name]), f'integrated source differs: {name}')
                verified[name] = blob
    require(verified.keys() == targets.keys() and not required, f'incomplete source archive: {required}')

    manifest = ROOT / 'config/pvrsrvkm-a032f-stock-crcs.json'
    report = args.report.with_suffix('.gpu-crcs.tsv')
    require((abi / 'pvrsrvkm-expected-crcs.json').read_bytes() == manifest.read_bytes(), 'wrong GPU manifest')
    subprocess.run([sys.executable, str(ROOT / 'scripts/verify-pvrsrvkm-abi.py'), '--expected', str(manifest),
                    '--symvers', str(abi / 'Module.symvers'), '--report', str(report)], check=True)
    require(report.read_bytes() == (abi / 'pvrsrvkm-crc-comparison.tsv').read_bytes(),
            'offline and CI GPU CRC reports differ')
    info = {'release': V18, 'image_bytes': len(image), 'image_sha256': hashlib.sha256(image).hexdigest(),
            'config_sha256': hashlib.sha256(config).hexdigest(), 'config_diff': [old_line.decode(), new_line.decode()],
            'compiler': 'Android Clang 11.0.1 r383902', 'pvrsrvkm_crc_matches': 267, 'source_blobs': verified}
    args.report.write_text(json.dumps(info, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(info, indent=2))


if __name__ == '__main__':
    main()
