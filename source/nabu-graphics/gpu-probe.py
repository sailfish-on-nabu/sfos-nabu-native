#!/usr/bin/env python3
import ctypes as C
import json
import os
import sys

P = C.c_void_p
I = C.c_int
U = C.c_uint
platform = sys.argv[1] if len(sys.argv) > 1 else 'wayland'
egl = C.CDLL('libEGL.so.1')
gles = C.CDLL('libGLESv2.so.2')
egl.eglGetProcAddress.argtypes = [C.c_char_p]
egl.eglGetProcAddress.restype = P
egl.eglInitialize.argtypes = [P, C.POINTER(I), C.POINTER(I)]
egl.eglInitialize.restype = U
egl.eglGetError.restype = I
egl.eglQueryString.argtypes = [P, I]
egl.eglQueryString.restype = C.c_char_p
egl.eglBindAPI.argtypes = [U]
egl.eglChooseConfig.argtypes = [P, C.POINTER(I), C.POINTER(P), I, C.POINTER(I)]
egl.eglChooseConfig.restype = U
egl.eglCreateContext.argtypes = [P, P, P, C.POINTER(I)]
egl.eglCreateContext.restype = P
egl.eglMakeCurrent.argtypes = [P, P, P, P]
egl.eglMakeCurrent.restype = U
egl.eglDestroyContext.argtypes = [P, P]
egl.eglTerminate.argtypes = [P]
gles.glGetString.argtypes = [U]
gles.glGetString.restype = C.c_char_p

report = {'platform': platform}
callbacks = []
wl = None
gbm = None
fd = None

if platform == 'wayland':
    wl = C.CDLL('libwayland-client.so.0')
    wl.wl_display_connect.argtypes = [C.c_char_p]
    wl.wl_display_connect.restype = P
    wl.wl_display_disconnect.argtypes = [P]
    wl.wl_display_roundtrip.argtypes = [P]
    native = wl.wl_display_connect(None)
    assert native, 'Could not connect to the application Wayland socket'
    class Interface(C.Structure):
        _fields_ = [('name', C.c_char_p), ('version', I), ('method_count', I), ('methods', P), ('event_count', I), ('events', P)]
    interface = Interface.in_dll(wl, 'wl_registry_interface')
    wl.wl_proxy_marshal_constructor_versioned.argtypes = [P, U, C.POINTER(Interface), U]
    wl.wl_proxy_marshal_constructor_versioned.restype = P
    registry = wl.wl_proxy_marshal_constructor_versioned(native, 1, C.byref(interface), 1, P())
    globals_ = []
    @C.CFUNCTYPE(None, P, P, U, C.c_char_p, U)
    def global_(data, registry_, name, kind, version):
        globals_.append({'name': kind.decode(), 'version': version})
    @C.CFUNCTYPE(None, P, P, U)
    def remove(data, registry_, name):
        pass
    listener = (P * 2)(C.cast(global_, P).value, C.cast(remove, P).value)
    callbacks.extend([global_, remove, listener])
    wl.wl_proxy_add_listener.argtypes = [P, C.POINTER(P), P]
    wl.wl_proxy_add_listener(registry, listener, None)
    wl.wl_display_roundtrip(native)
    report['wayland_globals'] = globals_
    getdisplay = C.CFUNCTYPE(P, U, P, C.POINTER(I))(egl.eglGetProcAddress(b'eglGetPlatformDisplayEXT'))
    display = getdisplay(0x31D8, native, None)
else:
    gbm = C.CDLL('libgbm.so.1')
    gbm.gbm_create_device.argtypes = [I]
    gbm.gbm_create_device.restype = P
    gbm.gbm_device_destroy.argtypes = [P]
    fd = os.open('/dev/dri/renderD128', os.O_RDWR | os.O_CLOEXEC)
    native = gbm.gbm_create_device(fd)
    assert native, 'Could not create a GBM device on the render node'
    getdisplay = C.CFUNCTYPE(P, U, P, C.POINTER(I))(egl.eglGetProcAddress(b'eglGetPlatformDisplayEXT'))
    display = getdisplay(0x31D7, native, None)

major, minor = I(), I()
assert egl.eglInitialize(display, C.byref(major), C.byref(minor)), f'eglInitialize failed: {egl.eglGetError():#x}'
extensions = egl.eglQueryString(display, 0x3055).decode()
report['egl_version'] = f'{major.value}.{minor.value}'
report['bind_wayland_display_extension'] = 'EGL_WL_bind_wayland_display' in extensions.split()
report['dma_buf_import_extension'] = 'EGL_EXT_image_dma_buf_import' in extensions.split()
attrs = (I * 13)(0x3024, 8, 0x3023, 8, 0x3022, 8, 0x3021, 8, 0x3033, 4, 0x3040, 4, 0x3038)
config, count = P(), I()
egl.eglBindAPI(0x30A0)
assert egl.eglChooseConfig(display, attrs, C.byref(config), 1, C.byref(count)) and count.value
context_attrs = (I * 3)(0x3098, 2, 0x3038)
context = egl.eglCreateContext(display, config, None, context_attrs)
assert context and egl.eglMakeCurrent(display, None, None, context), f'Context failed: {egl.eglGetError():#x}'
report['gl_renderer'] = gles.glGetString(0x1F01).decode()
report['gl_vendor'] = gles.glGetString(0x1F00).decode()
report['gl_version'] = gles.glGetString(0x1F02).decode()
if platform != 'wayland' and report['bind_wayland_display_extension']:
    server = C.CDLL('libwayland-server.so.0')
    server.wl_display_create.restype = P
    server.wl_display_destroy.argtypes = [P]
    server_display = server.wl_display_create()
    bind = C.CFUNCTYPE(U, P, P)(egl.eglGetProcAddress(b'eglBindWaylandDisplayWL'))
    unbind = C.CFUNCTYPE(U, P, P)(egl.eglGetProcAddress(b'eglUnbindWaylandDisplayWL'))
    report['bind_wayland_display_test'] = bool(bind(display, server_display))
    if report['bind_wayland_display_test']:
        unbind(display, server_display)
    server.wl_display_destroy(server_display)
report['graphics_libraries'] = sorted({line.split()[-1] for line in open('/proc/self/maps') if any(x in line for x in ['libEGL', 'libGLES', 'libgallium', 'libgbm', 'dri_gbm'])})
print(json.dumps(report, indent=2), flush=True)
egl.eglMakeCurrent(display, None, None, None)
egl.eglDestroyContext(display, context)
egl.eglTerminate(display)
if wl:
    wl.wl_display_disconnect(native)
if gbm:
    gbm.gbm_device_destroy(native)
    os.close(fd)
