# Nabu speaker low-frequency workaround

A listening comparison of seconds 15–35 of jolla-ringtone.ogg found substantially less noise after a two-pole 200 Hz high-pass. This is a speaker-only workaround and intentionally reduces bass. It does not establish whether the root cause is amplifier configuration, transducer limits, or DSP processing.

highpass.c implements the same Butterworth response as the ffmpeg highpass=f=200:p=2 comparison. PulseAudio module-ladspa-sink creates one independent mono instance per channel. No global or static filter state is shared between channels. The filter processes floating-point samples before the physical PCM conversion.

The nabu-speaker-filter user service loads the filter after PulseAudio and volume initialization. It recognizes both HiFi and playback-only Speaker physical sink names, preserves a lower volume and limits startup to 10400 (approximately 16%) during debugging, and directs built-in-speaker playback through nabu_speaker. It preserves an existing non-speaker default output. Bluetooth outputs are not filtered. Existing per-app explicit output choices may still bypass the default sink.

To disable on the device:

    systemctl --user mask nabu-speaker-filter.service
    systemctl --user restart pulseaudio ngfd

To re-enable:

    systemctl --user unmask nabu-speaker-filter.service
    systemctl --user restart pulseaudio ngfd

Host response check:

    gcc -O2 -Wall -Wextra -Werror test-highpass.c -lm -o /tmp/nabu-highpass-test
    /tmp/nabu-highpass-test

Tests cover 44.1 and 48 kHz: approximately -24 dB at 50 Hz, -3 dB at 200 Hz and 0 dB at 1 kHz. Native aarch64 library built with warnings as errors. Device checks confirmed service restart, filter routing and shared master/filter volume at 10400. Full ringtone listening remains necessary.

ladspa.h was extracted from Ubuntu ladspa-sdk 1.17-1; its original LGPL notice is retained and LICENSE.ladspa contains LGPL 2.1. Filter implementation is MIT licensed.
