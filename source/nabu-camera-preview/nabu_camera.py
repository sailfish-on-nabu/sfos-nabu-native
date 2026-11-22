"""Native CAMSS media graph setup for nabu (Linux media-controller ABI)."""
import ctypes
import errno
import fcntl
import glob
import os
import struct

def ioctl_rw(fd, kind, number, data):
    return fcntl.ioctl(fd, (3 << 30) | (len(data) << 16) |
                       (ord(kind) << 8) | number, data, True)

class MediaGraph:
    def __init__(self):
        self.fd = None
        for path in sorted(glob.glob('/dev/media*')):
            fd = os.open(path, os.O_RDWR)
            info = bytearray(256)
            try:
                ioctl_rw(fd, '|', 0, info)
                driver = bytes(info[:16]).split(b'\0')[0]
                if driver == b'qcom-camss':
                    self.fd, self.path = fd, path
                    break
            except OSError:
                pass
            os.close(fd)
        if self.fd is None:
            raise FileNotFoundError('CAMSS media device is not registered')
        try:
            self._read()
        except Exception:
            self.close()
            raise

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def _read(self):
        nodes = {}
        for path in glob.glob('/dev/video*') + glob.glob('/dev/v4l-subdev*'):
            try:
                st = os.stat(path)
                nodes[(os.major(st.st_rdev), os.minor(st.st_rdev))] = path
            except OSError:
                continue
        self.entities, self.links = {}, {}
        index = 0
        while True:
            raw = bytearray(256)
            struct.pack_into('I', raw, 0, index | 0x80000000)
            try:
                ioctl_rw(self.fd, '|', 1, raw)
            except OSError as exc:
                if exc.errno == errno.EINVAL:
                    break
                raise
            index = struct.unpack_from('I', raw, 0)[0]
            pads, links = struct.unpack_from('HH', raw, 52)
            major, minor = struct.unpack_from('II', raw, 72)
            self.entities[index] = {
                'id': index, 'name': bytes(raw[4:36]).split(b'\0')[0].decode(),
                'pads': pads, 'links': links, 'node': nodes.get((major, minor))
            }
        for entity in self.entities.values():
            pads = ctypes.create_string_buffer(entity['pads'] * 20)
            links = ctypes.create_string_buffer(entity['links'] * 52)
            raw = bytearray(struct.pack('I4xQQ4I', entity['id'],
                            ctypes.addressof(pads), ctypes.addressof(links), 0, 0, 0, 0))
            ioctl_rw(self.fd, '|', 2, raw)
            for i in range(entity['links']):
                source, source_pad = struct.unpack_from('IH', links.raw, i * 52)
                sink, sink_pad = struct.unpack_from('IH', links.raw, i * 52 + 20)
                flags = struct.unpack_from('I', links.raw, i * 52 + 40)[0]
                self.links[(source, source_pad, sink, sink_pad)] = {
                    'source': self.entities[source]['name'], 'source_id': source,
                    'source_pad': source_pad, 'sink': self.entities[sink]['name'],
                    'sink_id': sink, 'sink_pad': sink_pad, 'flags': flags
                }

    def configure(self, position):
        rear = position == 'rear'
        pipe = 0 if rear else 1
        sensor = next(e for e in self.entities.values()
                      if e['name'].startswith('ov13b10 ' if rear else 'ov8856 '))
        names = [sensor['name'], 'msm_csiphy0' if rear else 'msm_csiphy1',
                 f'msm_csid{pipe}', f'msm_vfe{pipe}_rdi0', f'msm_vfe{pipe}_video0']
        chosen = {(names[1], 1, names[2], 0), (names[2], 1, names[3], 0)}
        for link in sorted(self.links.values(), key=lambda l:
                           (l['source'], l['source_pad'], l['sink'], l['sink_pad']) in chosen):
            if link['flags'] & 2:
                continue
            if not (link['source'] == names[1] or link['sink'] == names[2] or
                    link['source'] == names[2] or link['sink'] == names[3]):
                continue
            flags = int((link['source'], link['source_pad'],
                         link['sink'], link['sink_pad']) in chosen)
            if flags == (link['flags'] & 1):
                continue
            raw = bytearray(52)
            struct.pack_into('IH2xI2I', raw, 0, link['source_id'], link['source_pad'], 2, 0, 0)
            struct.pack_into('IH2xI2I', raw, 20, link['sink_id'], link['sink_pad'], 1, 0, 0)
            struct.pack_into('I', raw, 40, flags)
            ioctl_rw(self.fd, '|', 3, raw)
            link['flags'] = flags
        width, height, code = (2104, 1560, 0x300a) if rear else (1640, 1232, 0x3007)
        for name in names[:-1]:
            entity = next(e for e in self.entities.values() if e['name'] == name)
            fd = os.open(entity['node'], os.O_RDWR)
            try:
                for pad in ([0] if entity is sensor else [0, 1]):
                    raw = bytearray(88)
                    struct.pack_into('6I', raw, 0, 1, pad, width, height, code, 1)
                    ioctl_rw(fd, 'V', 5, raw)
                    if struct.unpack_from('3I', raw, 8) != (width, height, code):
                        raise RuntimeError(f'Unexpected camera format on {name}:{pad}')
            finally:
                os.close(fd)
        capture = next(e for e in self.entities.values() if e['name'] == names[-1])
        print(f'{position}: {sensor["name"]} -> {capture["node"]}, {width}x{height}', flush=True)
