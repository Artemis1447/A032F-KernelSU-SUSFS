#!/usr/bin/env python3
"""Replace only the kernel in an unlocked a3core's full V17 boot partition backup.

Keep the vendor ramdisk, DTB, Samsung trailer and the existing embedded vbmeta.
The OEM hash descriptor is not re-signed. This is for the tested unlocked setup.
"""

import argparse
import hashlib
import struct
from pathlib import Path


PARTITION = 64 * 1024 * 1024
PAGE = 2048
V17_IMAGE = '9b2f68f6b37a0031ffc7cec89c5239342328991e93c2d522019c9db498af98fe'
TRAILER = b'SEANDROIDENFORCE'


def align(size, block):
    return (size + block - 1) // block * block


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sections(boot):
    require(len(boot) == PARTITION and boot[:8] == b'ANDROID!', 'not a complete a3core boot partition')

    def word(off):
        return struct.unpack_from('<I', boot, off)[0]

    require((word(36), word(40), word(1644)) == (PAGE, 2, 1660), 'unsupported boot header')
    require(word(24) == 0 and word(1632) == 0 and boot[1636:1644] == bytes(8),
            'unexpected second stage or recovery overlay')
    require(word(16) > 0 and word(1648) > 0, 'missing ramdisk or DTB')
    pos = PAGE
    parts = []
    for field in (8, 16, 24, 1632, 1648):
        size = word(field)
        require(pos + align(size, PAGE) <= PARTITION - 64, 'section outside partition')
        parts.append(boot[pos:pos + size])
        pos += align(size, PAGE)
    require(boot[pos:pos + len(TRAILER)] == TRAILER, 'Samsung trailer missing')
    return parts, pos


def boot_id(parts):
    digest = hashlib.sha1()  # legacy Android boot header ID
    for part in parts:
        digest.update(part)
        digest.update(struct.pack('<I', len(part)))
    return digest.digest() + bytes(12)


def repack(original, kernel):
    parts, old_end = sections(original)
    require(hashlib.sha256(parts[0]).hexdigest() == V17_IMAGE, 'not the released V17 Image')
    require(original[576:608] == boot_id(parts), 'V17 boot header ID mismatch')
    require(kernel[56:60] == b'ARM\x64' and b'Linux version 4.14.199-a3core-vendorabi-v18-sukisu-susfs ' in kernel,
            'not the V18 arm64 Image')
    footer = bytearray(original[-64:])
    magic, major, minor, image_size, vbmeta_offset, vbmeta_size = struct.unpack_from('>4sIIQQQ', footer)
    require((magic, major, minor) == (b'AVBf', 1, 0) and image_size == old_end + len(TRAILER),
            'unexpected AVB footer layout')
    require(vbmeta_offset == align(image_size, 4096) and 256 <= vbmeta_size <= PARTITION - 64 - vbmeta_offset,
            'invalid embedded vbmeta extent')
    require(original[vbmeta_offset:vbmeta_offset + 4] == b'AVB0' and
            not any(original[image_size:vbmeta_offset]) and not any(original[vbmeta_offset + vbmeta_size:-64]),
            'unexpected vendor data outside the boot or vbmeta payload')

    old_ramdisk_start = PAGE + align(len(parts[0]), PAGE)
    new_ramdisk_start = PAGE + align(len(kernel), PAGE)
    shift = new_ramdisk_start - old_ramdisk_start
    new_size = image_size + shift
    new_meta = align(new_size, 4096)
    require(new_meta + vbmeta_size <= PARTITION - len(footer), 'new kernel does not fit')
    packed = bytearray(PARTITION)
    packed[:PAGE] = original[:PAGE]
    parts[0] = kernel
    struct.pack_into('<I', packed, 8, len(kernel))
    packed[576:608] = boot_id(parts)
    packed[PAGE:PAGE + len(kernel)] = kernel
    packed[new_ramdisk_start:new_size] = original[old_ramdisk_start:image_size]
    packed[new_meta:new_meta + vbmeta_size] = original[vbmeta_offset:vbmeta_offset + vbmeta_size]
    struct.pack_into('>QQ', footer, 12, new_size, new_meta)
    packed[-64:] = footer
    verified, end = sections(packed)
    require(verified == parts and end + len(TRAILER) == new_size and boot_id(verified) == packed[576:608],
            'reparsed boot components or header ID differ')
    return packed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('v17_backup', type=Path)
    parser.add_argument('kernel', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    image = repack(args.v17_backup.read_bytes(), args.kernel.read_bytes())
    with args.output.open('xb') as out:
        try:
            out.write(image)
        except OSError:
            out.close()
            args.output.unlink()
            raise
    print(f'{hashlib.sha256(image).hexdigest()}  {args.output}')


if __name__ == '__main__':
    main()
