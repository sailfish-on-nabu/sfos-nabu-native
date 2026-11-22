#!/bin/sh
set -u
uname -a
/usr/local/sbin/nabu-doubletap --status
/usr/sbin/mcetool | grep -i -E 'Display state:|Touchscreen/Keypad lock:|Double-tap|Autosuspend'
systemctl status nabu-doubletap.service --no-pager
journalctl -b -k --no-pager | grep -E 'NVT-ts-spi|gesture|wakeup' | tail -100
cat /proc/interrupts | grep -i -E 'nvt|spi0.0|touch'
