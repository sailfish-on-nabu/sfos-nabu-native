# Nabu native double-tap wake

Implementation and test artifacts for the mainline Sailfish nabu port. This is not yet hardware-verified. No boot partition has been written.

## Protocol and implementation

The local stock kernel at /home/bird/data/hadk_18.1/kernel/xiaomi/sm8150 confirms NT36523 double-click gesture ID 15, extended packet ID 30 / function page 1, the reserved 0x13 gesture-mode host command, and panel reset/power retention when double-click is enabled. The stock SPI command itself was commented because the stock display stack supplied it; the native port now sends it synchronously before DCS sleep. Acceptance by the running firmware and its timing still need a real device test.

Kernel files:

- nt36523/nt36xxx_gesture.h: narrow decoder accepting only direct/extended double taps.
- nt36523/nt36xxx.c: gesture reporting as EV_MSC / MSC_GESTURE value 4; sysfs double_tap_wake and gesture_active; synchronized touch/panel transitions; display-off GPIO/PDC IRQ wake armed once and kept across unrelated system resumes; touch and pen restored through existing firmware reload.
- panel-novatek-nt36523.c: board-specific synchronous sleep/reset handshakes. Retain the existing regulator vote and avoid asserting TDDI reset only when the touch driver confirms gesture entry. Quiesce the touch IRQ before normal reset on resume. Do not accumulate regulator votes across retained cycles.
- drm_notifier.h: sleep/reset handshake definitions.
- sm8150-xiaomi-nabu.dts: wakeup-source on the existing touchscreen.

kernel-doubletap.patch contains only this feature relative to the captured pre-task sources, not unrelated earlier nabu modifications. The full source files in source/linux are authoritative. The panel driver is built in: replacing only the touch module on the old kernel does not implement retention.

Runtime integration:

    /usr/local/sbin/nabu-doubletap --status
    /usr/local/sbin/nabu-doubletap --enable
    /usr/local/sbin/nabu-doubletap --disable

The service enables the feature at boot on a matching kernel and sets MCE to show the locked screen, not unlock it. The double_tap_wake attribute accepts 0, 1 or MCE-style 4. Enabling/disabling the controller mode takes effect on the next display cycle; MCE policy is changed immediately by the control script. Existing disabled-autosuspend policy is not changed. Deep-suspend wake and power consumption are separate unverified tests.

## Checks completed

- Decoder tests under AddressSanitizer and UBSan cover both valid encodings, all other direct IDs, all function pages, all extended IDs and short input.
- Touch and panel translation units and DTB compile.
- Complete ARM64 Image/Image.gz and the matching touch module build successfully. An existing unrelated dsi_host.c always-true-address warning remains in the full build log.
- DTB wakeup-source property verified; DTB includes symbols as in the existing build.
- Boot repacker tested on the real backed-up initramfs. New ramdisk differs only in nt36523_ts.ko; original boot arguments, addresses, v0 layout and other initramfs files are preserved, and boot ID/checksums verified.
- Real-device synthetic MSC_GESTURE=4 test changed display off -> on while tklock remained locked. This validates the MCE input path only, not touch firmware or IRQ wake.
- Runtime helper/service installed and enabled. The new test kernel has been temporarily booted, and normal touch is user-confirmed. On the original kernel the service condition still skips safely.

## Artifacts and safe first boot

Build output and logs are in work/logs/doubletap-20261121/. Artifacts are isolated from the published dist images. The original 128 MiB boot_a backup is before/boot_a.img; another copy remains at /home/defaultuser/nabu-before-doubletap-boot.img on the tablet. SHA256 is 61a40c52abcb10a462825e92fd66748c0120c5857f4e8d4045cf497fc4dad34d.

The test image is artifacts/nabu-doubletap-test-boot.img with a checksum file. First test should use USB passthrough to the Linux VM and fastboot boot, without flashing. The old boot partition is unchanged, so a normal restart returns to the old kernel. USB passthrough and fastboot temporary boot have now succeeded. The current live touch module is revision v4. The user still reported no visible wake in initial physical tests; one native gesture was captured and MCE went ON briefly. A complete user-visible wake is not yet verified.

After a temporary boot: verify the new sysfs attributes and service, normal touch/pen input and the power key. Blank the screen; gesture_active should be 1. A single tap should leave the screen off; a double tap should emit the native gesture and show a locked screen. Repeat several cycles, then disable the feature, cycle the display and verify the old sleep behavior. Do not claim deep-suspend support until it is tested separately with a working recovery connection.

Build in the existing user/mount namespace setup:

    bash scripts/namespace.sh bash source/nabu-doubletap/build-test-kernel.sh
    python3 source/nabu-doubletap/make-test-boot.py work/logs/doubletap-20261121/before/boot_a.img work/logs/doubletap-20261121/artifacts

Run collect-device.sh as root after boot to capture device evidence. Disable the installed service with systemctl disable --now nabu-doubletap.service. On the original kernel the service is skipped automatically.

## MCE integration corrected from the ginkgo reference

The user-provided commit 95f4c7d9bce534d39351095f84ac5eff0aa69550 in sailfish-on-ginkgo/droid-config-ginkgo revealed a missing connection in the initial implementation: generic MCE [DoubleTap] ControlPath configuration. Merely setting the MCE policy and manually writing the driver attribute was incomplete.

The native overlay now includes 95-nabu-doubletap.ini with ControlPath=/run/touchscreen_double_tap_wake, EnableValue=1 and DisableValue=0; a .conf default for /system/osso/dsm/doubletap/mode=1; and a udev add/bind/change rule matching DRIVER=NVT-ts-spi. The runtime helper also creates the symlink as a fallback. NVTCapacitiveTouchScreen is explicitly TOUCH. The ginkgo KEY_WAKEUP to KEY_POWER mapping is not copied because this driver already emits native MSC_GESTURE=4.

The config was installed and MCE restarted. A real MCE policy toggle was verified: never writes driver attribute 0; always writes 1. The post-ControlPath physical wake test is awaiting user feedback. No stock firmware was installed; stock CSOT/BOE blobs were decoded only for offline comparison. The working firmware remains version 0x35.

The first touch module failed on redundant enables (-EEXIST from device_wakeup_enable). The idempotent sysfs control fix and runtime helper guard are included in v4, along with read-only gesture_status diagnostics. The test boot image was repacked with v4; the initially booted v1 image/module are archived under artifacts/v1. The running session uses the same built-in panel kernel with v4 hot-loaded, without replacing the on-disk original touch module or boot partition.

## Current hardware test checkpoint

The user still reported no visible wake after MCE ControlPath was installed and verified. GPIO interrupt delivery is not consistently observed after screen-off. A one-cycle firmware comparison has now loaded stock CSOT fw01 version 0x12 into the controller SRAM using the same v4 driver. The filesystem firmware was restored immediately after probe to the original version 0x35, SHA256 8b845514621ebfd95759a0919f3aa3d825314abb478a7cad1c3fb4c6872b70b5. This is not a persistent firmware downgrade or flash. On the next display resume the existing firmware reload path returns to 0x35. The user test of this single off-screen cycle is pending; do not mark hardware wake as working. Evidence is stock-csot-ram-test.log. The diagnostic lockscreen timeout has been restored to its original 10 seconds.


## November 22 hardware isolation update

Hardware double tap remains unverified and user-confirmed failing. The 60 Hz comparison failed; 120 Hz was restored and sync-pen returned 0. The default-off panel parameter gesture_display_off_only was temporarily enabled on the new fastboot-booted image: DCS display-off was sent without sleep-in. The physical test still produced no new IRQ (25 before and after). The parameter was then set back to N and a normal display cycle completed. No boot partition was written.

A separate diagnostic queued a touch-only resume with the LCD asleep. Firmware download failed with FE responses. That diagnostic was removed; unblank reloaded original firmware 0x35 successfully. Reloading normal firmware in LCD sleep is not a supported operating mode, so this failure is a clue, not proof of the wake failure's cause. No persistent firmware change was made.

The stock panel initialization was compared command by command against native: 188 versus 189 commands; differences are the optional zero payload on DCS sleep-out/display-on and the existing native 53 2c brightness-control write. No additional stock gesture command was found. Both drivers use rising-edge IRQ and host command 0x13.

Temporary nabu-touch-pin-diag observes GPIO39 through the existing descriptor without requesting it or changing mux, direction, bias, or IRQ settings. It samples at nominal 100 us and records high/low samples and transitions independently of IRQ delivery. Pulses shorter than the sample interval can be missed. First validate with lit-screen touch, then compare screen-off double taps. Sampling self-stops after fifteen minutes; a separate cleanup timer unloads it and clears the temporary never-blank override. This module is diagnostic only and must not be added to the production image. Current physical-test state is recorded in status.json, not implied by these instructions.


GPIO39 observation result: lit-screen positive control registered 47 rising/falling transitions and an IRQ increase from 9959 to 10148. After blanking, the user double-tapped several groups; both transition counts stayed at 47, sampled high count stayed 47, and IRQ count stayed 10148. No read errors. This favors failure to generate the gesture signal over an MCE event-handling problem, but the 100 us polling interval cannot exclude shorter pulses. The sampler was unloaded, its cleanup timer stopped, never-blank disabled, and panel diagnostic parameter remained N. Evidence: pin-positive-control.log, pin-screen-off-baseline.log, pin-screen-off-result.log. Hardware wake is still not working.
