# Native GPU rendering for nabu Wayland applications

The live-device fix was verified on 2026-11-22. Applications continue to use
Wayland and Lipstick continues to use EGLFS/KMS; both now render with the
Adreno 640 (`FD640`, freedreno). Hardware buffers are shared through `wl_drm`
version 2 and the Qt 5.6 EGL client-buffer integration.

## Cause

The Ubuntu Mesa 25.2.8 build did not enable its deprecated
`EGL_WL_bind_wayland_display` interface. Lipstick's Qt 5.6 compositor needs
that interface to register and import application GPU buffers. The compositor
advertised shared-memory buffers but no `wl_drm` GPU-buffer interface, and
Wayland EGL clients selected llvmpipe.

A second problem affected normal application launches: the early
`booster-silica-session` process is setgid and preloads GLES before application
environment variables are applied. It had loaded system Mesa 25.1.9 even though
the application environment named the private Mesa directory. Its children
inherited those mappings.

## Implementation

- `config/native-mesa-build.json` pins Mesa 25.2.8, source and SDK archive hashes,
  and the tested build options.
- `scripts/build-native-mesa.py` builds EGL, GBM and freedreno with
  `-Dlegacy-wayland=bind-wayland-display`. The build includes a softpipe fallback.
- `scripts/copy-native-mesa.py` installs those components over the existing
  private dependency bundle and generates graphics SONAME links.
- `/etc/ld.so.conf.d/00-000-nabu-native-graphics.conf` puts the graphics links
  first in `ld.so.cache`, so early setgid boosters resolve the same graphics
  libraries as Lipstick. Sailjail and the normal application boosters remain enabled.

The build is currently tested on an x86-64 Linux host with the aarch64 GCC 11
C compiler and the pinned GCC 12 C++ SDK. Run the component build with:

```bash
python3 scripts/build-native-mesa.py "$PWD" /path/to/sfos-work
```

The normal `./build.sh` native-rootfs path invokes it automatically. SDK downloads
and build output remain in `SFOS_WORK`; they are not committed to the repository.

## Live-device verification

At 1600×2560 with the display set to 60 Hz, the same Qt Quick scrolling scene
was measured before and after the change. Each run lasted 12 seconds and excluded
the first two seconds from frame statistics.

| Measurement | Before | After |
| --- | --- | --- |
| OpenGL renderer | llvmpipe, Mesa 25.1.9 | FD640 / freedreno, Mesa 25.2.8 |
| Presented FPS | 13.98 | 60.01 |
| Median frame interval | 64.99 ms | 16.65 ms |
| 95th-percentile frame interval | 90.28 ms | 18.80 ms |

The independent DRM/GBM probe successfully bound a Wayland display. The live
compositor advertised `wl_drm` v2, and a Wayland EGL probe selected FD640.
After refreshing the normal login session, the settings application loaded
EGL, GLES, GBM and Gallium exclusively from the corrected native bundle.
The user confirmed very smooth application scrolling.

The integrated source builder also completed a fresh cross-build. Fresh and
repeated rootfs library installs passed payload checksum, SONAME-link and RPATH
checks. An isolated runtime RPM build verified that the graphics bundle and
loader configuration are packaged. The resulting source-built EGL, GBM and
Gallium libraries were probed on the device without replacing its running
libraries: they selected FD640 and successfully bound a Wayland display.

To inspect the application rendering path, copy `gpu-probe.py` to the device and
run it as the graphical user:

```bash
XDG_RUNTIME_DIR=/run/user/100000 python3 gpu-probe.py wayland
```

The report should contain `wl_drm` version 2, `gl_renderer: FD640`, and the native
graphics library paths. `python3 gpu-probe.py gbm` also tests the compositor-side
Wayland binding; it requires access to `/dev/dri/renderD128`.

This verifies GPU rendering and this scrolling workload at 60 Hz. Application
logic, image processing and other CPU work can still limit frame rate. No
120 FPS claim or QEMU graphics result is made.

## Updating an existing session

Preloaded GLES mappings survive ordinary application or child-booster restarts.
After replacing libraries and running `ldconfig`, refresh the complete normal
login session with `systemctl restart autologin@100000.service`, then reopen
applications. This restarts the UI session and may require unlocking the screen.
Stopping the session-root booster directly also terminates its login session;
use the autologin service to manage that lifecycle.

The live-device backup is `/var/tmp/nabu-graphics-before-20261122-020353/native`;
the original mapped-library directory is retained at
`/usr/lib/sailfish-native.old-20261122-020353`. Diagnostic logs and rollback
scripts are preserved under `work/graphics-20261122T020353Z/` on the build host.

The existing `5.3.0.21-native-20261122` release ZIP predates this graphics fix.
A new image build and release are required to distribute the updated libraries.

Upstream option reference:
[Mesa 25.2.8 meson.options](https://gitlab.freedesktop.org/mesa/mesa/-/blob/mesa-25.2.8/meson.options).
