/*
 * Qt 5.6 and Lipstick both use WAYLAND_DISPLAY. Redirect only the Wayland
 * client connection so that Lipstick can publish its own server socket.
 * Build without libc startup files to preserve compatibility with Sailfish's
 * older glibc. The embedding process already supplies getenv and dlsym.
 */

struct wl_display;
extern char *getenv(const char *name);
extern void *dlsym(void *handle, const char *symbol);

typedef struct wl_display *(*connect_function)(const char *name);

struct wl_display *wl_display_connect(const char *name)
{
    connect_function connect = (connect_function)dlsym((void *)-1, "wl_display_connect");
    const char *parent = getenv("SFOS_PARENT_WAYLAND_DISPLAY");

    if (!connect) {
        return 0;
    }
    if (parent && *parent) {
        return connect(parent);
    }
    return connect(name);
}
