#!/usr/bin/python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""Forward real Qualcomm SSC acceleration samples to the SensorFW evdev adaptor."""
import ctypes
import fcntl
import math
import os
from pathlib import Path
import select
import socket
import struct
import subprocess
import time

AF_QIPCRTR = 42
DISCOVERY_ID = 0xABABABABABABABAB


def varint(value):
    out = bytearray()
    while value > 127:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


def field(number, wire, value):
    head = varint(number * 8 + wire)
    if wire == 2:
        return head + varint(len(value)) + value
    return head + (varint(value) if wire == 0 else value)


def fields(data):
    pos = 0

    def read_varint():
        nonlocal pos
        value = shift = 0
        while pos < len(data) and shift <= 63:
            byte = data[pos]
            pos += 1
            value |= (byte & 127) << shift
            if byte < 128:
                return value
            shift += 7
        raise ValueError('Invalid protobuf varint')

    while pos < len(data):
        key = read_varint()
        number, wire = key >> 3, key & 7
        if number == 0:
            raise ValueError('Invalid protobuf field')
        if wire == 0:
            value = read_varint()
        else:
            if wire == 2:
                size = read_varint()
            elif wire in (1, 5):
                size = 8 if wire == 1 else 4
            else:
                raise ValueError('Unsupported protobuf wire type')
            if pos + size > len(data):
                raise ValueError('Truncated protobuf field')
            value = data[pos:pos + size]
            pos += size
        yield number, wire, value


class SSC:
    def __init__(self):
        table = subprocess.check_output(['qrtr-lookup'], text=True, timeout=10)
        service = next((line.split() for line in table.splitlines()
                        if line.split() and line.split()[0] == '400'), None)
        if service is None:
            raise RuntimeError('SSC QRTR service is unavailable')
        node, port = int(service[3]), int(service[4])
        self.libc = ctypes.CDLL(None, use_errno=True)
        self.fd = self.libc.socket(AF_QIPCRTR, socket.SOCK_DGRAM, 0)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), 'QRTR socket')
        self.address = struct.pack('<H2xII', AF_QIPCRTR, node, port)
        self.transaction = 0
        print('SSC connected on node %d port %d' % (node, port), flush=True)

    def close(self):
        self.libc.close(self.fd)

    def send(self, uid, message, payload):
        self.transaction = (self.transaction + 1) & 0xffff
        config = field(1, 0, 1) + field(2, 0, 0)  # APSS, wakeup reports
        body = field(2, 2, payload)
        proto = (field(1, 2, uid) + field(2, 5, struct.pack('<I', message))
                 + field(3, 2, config) + field(4, 2, body))
        tlvs = (struct.pack('<BH', 1, len(proto) + 2) + struct.pack('<H', len(proto))
                + proto + struct.pack('<BHB', 16, 1, 1))
        packet = struct.pack('<BHHH', 0, self.transaction, 0x20, len(tlvs)) + tlvs
        if self.libc.sendto(self.fd, packet, len(packet), 0,
                            self.address, len(self.address)) < 0:
            raise OSError(ctypes.get_errno(), 'SSC request')

    def reports(self):
        buf = ctypes.create_string_buffer(65536)
        size = self.libc.recv(self.fd, buf, len(buf), 0)
        if size < 7:
            raise RuntimeError('SSC transport disconnected')
        packet = buf.raw[:size]
        flags, transaction, message, length = struct.unpack_from('<BHHH', packet)
        if length != size - 7:
            raise ValueError('Invalid QMI packet size')
        pos, tlvs = 7, {}
        while pos + 3 <= size:
            tag, count = struct.unpack_from('<BH', packet, pos)
            pos += 3
            if pos + count > size:
                raise ValueError('Truncated QMI TLV')
            tlvs[tag] = packet[pos:pos + count]
            pos += count
        if flags == 2:
            result = tlvs.get(2)
            if result is None or len(result) != 4 or struct.unpack('<HH', result) != (0, 0):
                raise RuntimeError('SSC rejected request %d: %r' % (transaction, result))
            return []
        if flags != 4 or message not in (0x21, 0x22):
            return []
        data = tlvs.get(2, b'')
        if len(data) < 2:
            return []
        if struct.unpack_from('<H', data)[0] == len(data) - 2:
            prefix = 2
        elif len(data) >= 4 and struct.unpack_from('<I', data)[0] == len(data) - 4:
            prefix = 4
        else:
            raise ValueError('Invalid SSC payload size')
        envelope = list(fields(data[prefix:]))
        uid = next((value for number, wire, value in envelope if number == 1), None)
        reports = []
        for number, wire, body in envelope:
            if number == 2:
                event = dict((n, value) for n, w, value in fields(body))
                if 1 in event and len(event[1]) == 4:
                    reports.append((uid, struct.unpack('<I', event[1])[0], event.get(3, b'')))
        return reports


class AccelerometerInput:
    def __init__(self):
        self.fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
        try:
            fcntl.ioctl(self.fd, 0x40045564, 3)  # UI_SET_EVBIT EV_ABS
            for axis in range(3):
                fcntl.ioctl(self.fd, 0x40045567, axis)  # UI_SET_ABSBIT
            fcntl.ioctl(self.fd, 0x4004556e, 6)  # INPUT_PROP_ACCELEROMETER
            maximum, minimum = [0] * 64, [0] * 64
            maximum[:3], minimum[:3] = [16000] * 3, [-16000] * 3
            setup = struct.pack('80sHHHHI', b'nabu-accelerometer', 6, 0, 0, 1, 0)
            setup += struct.pack('256i', *(maximum + minimum + [0] * 128))
            os.write(self.fd, setup)
            fcntl.ioctl(self.fd, 0x5501)  # UI_DEV_CREATE
            name = bytearray(64)
            fcntl.ioctl(self.fd, 0x8040552c, name, True)  # UI_GET_SYSNAME
            self.sysname = bytes(name).split(b'\0')[0].decode()
        except BaseException:
            os.close(self.fd)
            raise

    def publish(self, xyz):
        # SSC reports m/s²; SensorFW's evdev adaptor expects milli-g.
        values = [round(value * 1000 / 9.80665) for value in xyz]
        stamp = time.time()
        seconds, micros = int(stamp), int(stamp % 1 * 1000000)
        events = b''.join(struct.pack('llHHi', seconds, micros, 3, axis,
                                     max(-16000, min(16000, value)))
                          for axis, value in enumerate(values))
        events += struct.pack('llHHi', seconds, micros, 0, 0, 0)
        os.write(self.fd, events)

    def close(self):
        fcntl.ioctl(self.fd, 0x5502)
        os.close(self.fd)


def notify_ready():
    address = os.environ.get('NOTIFY_SOCKET')
    if address:
        if address.startswith('@'):
            address = '\0' + address[1:]
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as connection:
            connection.sendto(b'READY=1', address)


def main():
    connection = SSC()
    input_device = None
    discovery = (field(1, 1, struct.pack('<Q', DISCOVERY_ID))
                 + field(2, 1, struct.pack('<Q', DISCOVERY_ID)))
    connection.send(discovery, 512,
                    field(1, 2, b'accel') + field(2, 0, 1) + field(3, 0, 1))
    sensor_uid = None
    last_sample = time.monotonic()
    ready = False
    try:
        while True:
            if time.monotonic() - last_sample > 30:
                raise RuntimeError('No SSC accelerometer data for 30 seconds')
            if not select.select([connection.fd], [], [], 1)[0]:
                continue
            for uid, message, payload in connection.reports():
                if uid == discovery and message == 768 and sensor_uid is None:
                    data = list(fields(payload))
                    if next((v for n, w, v in data if n == 1), None) != b'accel':
                        continue
                    sensor_uid = next((v for n, w, v in data if n == 2), None)
                    if sensor_uid:
                        connection.send(sensor_uid, 513, field(1, 5, struct.pack('<f', 10.0)))
                elif uid == sensor_uid and message == 1025:
                    xyz = []
                    for number, wire, value in fields(payload):
                        if number == 1 and wire in (2, 5) and len(value) % 4 == 0:
                            xyz.extend(struct.unpack('<' + 'f' * (len(value) // 4), value))
                    if len(xyz) != 3 or not all(math.isfinite(v) and abs(v) <= 160 for v in xyz):
                        continue
                    if input_device is None:
                        input_device = AccelerometerInput()
                    input_device.publish(xyz)
                    last_sample = time.monotonic()
                    if not ready and Path('/dev/input/nabu-accelerometer').exists():
                        print('Accelerometer ready: %s, xyz=%r' % (input_device.sysname, xyz), flush=True)
                        notify_ready()
                        ready = True
    finally:
        if input_device is not None:
            input_device.close()
        connection.close()


if __name__ == '__main__':
    main()
