#!/usr/bin/env python3
"""Repack a backed-up nabu v0 boot image; never access a block device."""
import argparse
import gzip
import hashlib
from pathlib import Path
import struct


def align(value, size):
    return (value + size - 1) // size * size


def cpio_entries(data):
    offset = 0
    while True:
        if offset + 110 > len(data) or data[offset:offset+6] != b'070701':
            raise ValueError('Expected a complete newc initramfs')
        fields = [int(data[offset+6+i*8:offset+14+i*8], 16) for i in range(13)]
        name_start = offset + 110
        name_end = name_start + fields[11]
        if fields[11] < 1 or name_end > len(data) or data[name_end-1] != 0:
            raise ValueError('Invalid cpio name')
        name = data[name_start:name_end-1].decode()
        start = align(name_end, 4)
        end = start + fields[6]
        if end > len(data):
            raise ValueError('Truncated cpio data')
        yield name, fields, data[start:end]
        offset = align(end, 4)
        if name == 'TRAILER!!!':
            if any(data[offset:]):
                raise ValueError('Unexpected trailing initramfs data')
            return


def replace_touch_module(ramdisk, module):
    entries = list(cpio_entries(gzip.decompress(ramdisk)))
    matches = [name for name, _, _ in entries if name.endswith('/nt36523_ts.ko')]
    if len(matches) != 1:
        raise ValueError('Expected exactly one early touch module: '+repr(matches))
    result = bytearray()
    for name, fields, data in entries:
        if name == matches[0]:
            data = module
        fields[6] = len(data)
        encoded = name.encode() + b'\0'
        result.extend(b'070701' + b''.join(f'{value:08x}'.encode() for value in fields))
        result.extend(encoded)
        result.extend(bytes(-len(result) % 4))
        result.extend(data)
        result.extend(bytes(-len(result) % 4))
    packed = gzip.compress(result, compresslevel=9, mtime=0)
    checked = dict((name, data) for name, _, data in cpio_entries(gzip.decompress(packed)))
    assert checked[matches[0]] == module
    return packed, matches[0]


def repack(original, kernel, dtb, module):
    if original[:8] != b'ANDROID!':
        raise ValueError('Not an Android boot image')
    old_kernel, _, old_ramdisk, _, second_size, _, _, page, version, _ = struct.unpack_from('<10I', original, 8)
    if version != 0 or second_size or page < 2048 or page & (page-1):
        raise ValueError('Only a v0, zero-second-stage nabu image is supported')
    ramdisk_start = page + align(old_kernel, page)
    ramdisk_end = ramdisk_start + old_ramdisk
    if ramdisk_end > len(original):
        raise ValueError('Truncated original boot image')
    ramdisk, module_path = replace_touch_module(original[ramdisk_start:ramdisk_end], module)
    payload = kernel + dtb
    header = bytearray(original[:page])
    struct.pack_into('<I', header, 8, len(payload))
    struct.pack_into('<I', header, 16, len(ramdisk))
    digest = hashlib.sha1()
    for part in (payload, ramdisk, b''):
        digest.update(part)
        digest.update(struct.pack('<I', len(part)))
    header[576:608] = digest.digest() + bytes(12)
    image = header + payload + bytes(-len(payload) % page) + ramdisk + bytes(-len(ramdisk) % page)
    assert image[:8] == b'ANDROID!'
    assert image[64:576] == original[64:576]  # name / original command line untouched
    return image, module_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('original', type=Path)
    parser.add_argument('artifacts', type=Path)
    args = parser.parse_args()
    a = args.artifacts
    image, module_path = repack(args.original.read_bytes(), (a/'Image.gz').read_bytes(),
                               (a/'sm8150-xiaomi-nabu.dtb').read_bytes(), (a/'nt36523_ts.ko').read_bytes())
    target = a/'nabu-doubletap-test-boot.img'
    target.write_bytes(image)
    checksum = hashlib.sha256(image).hexdigest()
    (a/'nabu-doubletap-test-boot.img.sha256').write_text(f'{checksum}  {target.name}\n')
    print(f'{target}: {len(image)} bytes, SHA256 {checksum}')
    print('Early touch module replaced: '+module_path)

if __name__ == '__main__':
    main()
