#!/usr/bin/env python3
"""Install or restore one full a3core Boot image from ADB-connected TWRP."""

import argparse
import hashlib
import re
import subprocess
from pathlib import Path


BOOT = '/dev/block/by-name/boot'
SIZE = 67108864


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--adb', default='adb')
    ap.add_argument('--serial', required=True)
    ap.add_argument('--expect-current', required=True, help='SHA-256 of the complete current Boot partition')
    ap.add_argument('--target-sha256', required=True, help='trusted SHA-256 of the replacement image')
    ap.add_argument('image', type=Path)
    args = ap.parse_args()
    old, new = args.expect_current.lower(), args.target_sha256.lower()
    if not all(re.fullmatch(r'[0-9a-f]{64}', value) for value in (old, new)):
        ap.error('both hashes must be 64 hex digits')
    data = args.image.read_bytes()
    if len(data) != SIZE or data[:8] != b'ANDROID!' or hashlib.sha256(data).hexdigest() != new:
        ap.error('target is not the verified full-size Boot image')

    adb = [args.adb, '-s', args.serial]

    def shell(command):
        result = subprocess.run(adb + ['shell', command], check=True, capture_output=True, timeout=90)
        return result.stdout.decode('utf-8', 'replace').strip()

    if not shell('getprop ro.twrp.version') or shell('id -u') != '0':
        raise SystemExit('boot TWRP recovery first')
    if shell('getprop ro.product.device') != 'a3core' or shell('getprop ro.boot.em.model') != 'SM-A032F':
        raise SystemExit('recovery is not running on the expected SM-A032F')
    if shell(f'readlink -f {BOOT}') != '/dev/block/mmcblk0p40' or shell(f'blockdev --getsize64 {BOOT}') != str(SIZE):
        raise SystemExit('unexpected boot mapping or partition size')
    current = shell(f'sha256sum {BOOT}').split()[0]
    if current != old:
        raise SystemExit(f'current Boot SHA-256 {current} differs from expected {old}; nothing written')
    if current == new:
        print('Boot already matches the target')
        return
    remote = shell('mktemp /tmp/a3core-boot.XXXXXX')
    if not re.fullmatch(r'/tmp/a3core-boot\.[A-Za-z0-9]+', remote):
        raise SystemExit('could not allocate a temporary image in recovery RAM')
    try:
        subprocess.run(adb + ['push', str(args.image), remote], check=True, timeout=120)
        if shell(f'sha256sum {remote}').split()[0] != new:
            raise SystemExit('staged image hash differs; nothing written')
        shell(f'dd if={remote} of={BOOT} bs=1048576 && sync && blockdev --flushbufs {BOOT}')
        readback = shell(f'sha256sum {BOOT}').split()[0]
        if readback != new:
            raise SystemExit(f'Boot readback {readback} differs; stay in recovery and restore the saved Boot')
        print(f'Boot: {old} -> {readback}; full {SIZE}-byte readback matched. Device is still in recovery.')
    finally:
        shell(f'rm -f {remote}')


if __name__ == '__main__':
    main()
