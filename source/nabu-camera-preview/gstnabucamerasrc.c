// SPDX-License-Identifier: LGPL-2.1-or-later
// Experimental native preview; a calibrated ISP is still required.
#include <gst/gst.h>
#include <gst/base/gstpushsrc.h>
#include <linux/videodev2.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <string.h>
#include <math.h>

#define BLACK_LEVEL 64
#define TONE_EXPOSURE 1.15
GST_DEBUG_CATEGORY_STATIC(nabu_debug);
#define GST_CAT_DEFAULT nabu_debug
typedef struct {
    GstPushSrc parent;
    gchar *device;
    int fd, sensor_fd, wake[2];
    gboolean streaming, front;
    unsigned width, height, stride, count, frames;
    void *mem[4];
    size_t len[4];
    int gain, saved_gain, gain_min, gain_max, gain_step;
    double red_balance, blue_balance;
    unsigned saturation_q8;
    unsigned char lut[3][1024];
    gint photo_pending;
    int saved_vblank;
    gboolean have_vblank;
    int lens_fd, saved_focus, focus_min, focus_max, focus_position;
    int focus_best, focus_wait, focus_end, focus_step;
    gboolean focus_scanning, focus_refining, ready_notified;
    double focus_best_score, focus_reference;
    unsigned focus_done_frame;
    gint64 focus_deadline;
} NabuCamera;
typedef struct { GstPushSrcClass parent; } NabuCameraClass;
G_DEFINE_TYPE(NabuCamera, nabu_camera, GST_TYPE_PUSH_SRC)
enum { PROP_0, PROP_DEVICE };

static GstStaticPadTemplate pad_template = GST_STATIC_PAD_TEMPLATE(
    "src", GST_PAD_SRC, GST_PAD_ALWAYS,
    GST_STATIC_CAPS("video/x-raw,format=RGB,width=[1,4096],height=[1,4096],"
                   "framerate=30/1,pixel-aspect-ratio=1/1"));

static gboolean is_front(NabuCamera *s)
{
    return s->device && (strstr(s->device, "front") ||
           strstr(s->device, "secondary") || !strcmp(s->device, "/dev/video6"));
}

static GstCaps *caps_for(NabuCamera *s)
{
    gboolean front = is_front(s);
    return gst_caps_new_simple(
        "video/x-raw", "format", G_TYPE_STRING, "RGB",
        "width", G_TYPE_INT, front ? 820 : 1052,
        "height", G_TYPE_INT, front ? 616 : 780,
        "framerate", GST_TYPE_FRACTION, 30, 1,
        "pixel-aspect-ratio", GST_TYPE_FRACTION, 1, 1,
        "interlace-mode", G_TYPE_STRING, "progressive",
        "colorimetry", G_TYPE_STRING, "sRGB", NULL);
}

static GstCaps *get_caps(GstBaseSrc *base, GstCaps *filter)
{
    GstCaps *caps = caps_for((NabuCamera *)base);
    if (filter) {
        GstCaps *n = gst_caps_intersect_full(filter, caps, GST_CAPS_INTERSECT_FIRST);
        gst_caps_unref(caps);
        caps = n;
    }
    return caps;
}

static void set_prop(GObject *o, guint p, const GValue *v, GParamSpec *ps)
{
    NabuCamera *s = (NabuCamera *)o;
    if (p == PROP_DEVICE) {
        if (s->streaming) {
            GST_WARNING_OBJECT(s, "Stop capture before changing the camera");
            return;
        }
        g_free(s->device);
        s->device = g_value_dup_string(v);
    } else {
        G_OBJECT_WARN_INVALID_PROPERTY_ID(o, p, ps);
    }
}

static void get_prop(GObject *o, guint p, GValue *v, GParamSpec *ps)
{
    if (p == PROP_DEVICE)
        g_value_set_string(v, ((NabuCamera *)o)->device);
    else
        G_OBJECT_WARN_INVALID_PROPERTY_ID(o, p, ps);
}

static int open_subdevice(const char *wanted)
{
    GDir *dir = g_dir_open("/sys/class/video4linux", 0, NULL);
    if (!dir)
        return -1;
    const char *entry;
    int fd = -1;
    while ((entry = g_dir_read_name(dir))) {
        if (!g_str_has_prefix(entry, "v4l-subdev"))
            continue;
        gchar *path = g_build_filename("/sys/class/video4linux", entry, "name", NULL);
        gchar *name = NULL;
        g_file_get_contents(path, &name, NULL, NULL);
        g_free(path);
        if (name && g_str_has_prefix(name, wanted)) {
            path = g_build_filename("/dev", entry, NULL);
            fd = open(path, O_RDWR | O_CLOEXEC);
            g_free(path);
        }
        g_free(name);
        if (fd >= 0)
            break;
    }
    g_dir_close(dir);
    return fd;
}

static gchar *capture_device(gboolean front)
{
    GDir *dir = g_dir_open("/sys/class/video4linux", 0, NULL);
    if (!dir)
        return NULL;
    const char *entry, *wanted = front ? "msm_vfe1_video0" : "msm_vfe0_video0";
    gchar *device = NULL;
    while ((entry = g_dir_read_name(dir))) {
        if (!g_str_has_prefix(entry, "video"))
            continue;
        gchar *path = g_build_filename("/sys/class/video4linux", entry, "name", NULL);
        gchar *name = NULL;
        g_file_get_contents(path, &name, NULL, NULL);
        g_free(path);
        if (name && !strcmp(g_strstrip(name), wanted))
            device = g_build_filename("/dev", entry, NULL);
        g_free(name);
        if (device)
            break;
    }
    g_dir_close(dir);
    return device;
}

static gboolean set_gain(NabuCamera *s, int value)
{
    if (s->sensor_fd < 0 || s->gain_min <= 0)
        return FALSE;
    value = CLAMP(value, s->gain_min, s->gain_max);
    value = s->gain_min + ((value - s->gain_min) / s->gain_step) * s->gain_step;
    struct v4l2_control ctrl = { .id = V4L2_CID_ANALOGUE_GAIN, .value = value };
    if (ioctl(s->sensor_fd, VIDIOC_S_CTRL, &ctrl) < 0) {
        GST_WARNING_OBJECT(s, "Setting analogue gain failed: %s", g_strerror(errno));
        return FALSE;
    }
    s->gain = value;
    return TRUE;
}

static void setup_gain(NabuCamera *s)
{
    s->gain_min = s->saved_gain = 0;
    s->have_vblank = FALSE;
    s->sensor_fd = open_subdevice(s->front ? "ov8856 " : "ov13b10 ");
    if (s->sensor_fd < 0)
        return;
    struct v4l2_queryctrl query = { .id = V4L2_CID_ANALOGUE_GAIN };
    struct v4l2_control ctrl = { .id = V4L2_CID_ANALOGUE_GAIN };
    if (ioctl(s->sensor_fd, VIDIOC_QUERYCTRL, &query) < 0 ||
        ioctl(s->sensor_fd, VIDIOC_G_CTRL, &ctrl) < 0 || query.minimum <= 0)
        return;
    s->gain_min = query.minimum;
    s->gain_max = MIN(query.maximum, query.minimum * 8);
    s->gain_step = MAX(query.step, 1);
    s->saved_gain = ctrl.value;
    s->gain = ctrl.value;
    set_gain(s, s->gain_min * 2);
    if (!s->front) {
        query.id = ctrl.id = V4L2_CID_VBLANK;
        if (ioctl(s->sensor_fd, VIDIOC_QUERYCTRL, &query) == 0 &&
            ioctl(s->sensor_fd, VIDIOC_G_CTRL, &ctrl) == 0) {
            s->saved_vblank = ctrl.value;
            // The full-field 2104x1560 binning mode defaults to 60 fps.
            // Double its frame period to match the 30 fps RGB output.
            ctrl.value = CLAMP((int)s->height + 2 * query.minimum, query.minimum, query.maximum);
            s->have_vblank = ioctl(s->sensor_fd, VIDIOC_S_CTRL, &ctrl) == 0;
        }
    }
}

static gboolean set_focus(NabuCamera *s, int position)
{
    struct v4l2_control ctrl = { .id = V4L2_CID_FOCUS_ABSOLUTE,
                                .value = CLAMP(position, s->focus_min, s->focus_max) };
    if (ioctl(s->lens_fd, VIDIOC_S_CTRL, &ctrl) < 0) {
        GST_WARNING_OBJECT(s, "Lens movement failed: %s", g_strerror(errno));
        return FALSE;
    }
    s->focus_position = ctrl.value;
    return TRUE;
}

static void setup_lens(NabuCamera *s)
{
    s->lens_fd = -1;
    s->focus_scanning = s->focus_refining = s->ready_notified = FALSE;
    s->focus_done_frame = 0;
    if (s->front)
        return;
    s->lens_fd = open_subdevice("cn3927");
    if (s->lens_fd < 0) {
        GST_WARNING_OBJECT(s, "Rear focus actuator is unavailable");
        return;
    }
    struct v4l2_queryctrl query = { .id = V4L2_CID_FOCUS_ABSOLUTE };
    struct v4l2_control ctrl = { .id = V4L2_CID_FOCUS_ABSOLUTE };
    if (ioctl(s->lens_fd, VIDIOC_QUERYCTRL, &query) < 0 ||
        ioctl(s->lens_fd, VIDIOC_G_CTRL, &ctrl) < 0) {
        close(s->lens_fd);
        s->lens_fd = -1;
        return;
    }
    s->saved_focus = s->focus_position = ctrl.value;
    s->focus_min = query.minimum;
    s->focus_max = query.maximum;
}

static void build_luts(NabuCamera *s)
{
    double balance[3] = { s->red_balance, 1.0, s->blue_balance };
    for (int channel = 0; channel < 3; channel++) {
        for (int value = 0; value < 1024; value++) {
            // The initial black estimate comes from the dark frames on this device.
            double linear = CLAMP((value - BLACK_LEVEL) * balance[channel] * TONE_EXPOSURE /
                                  (1023.0 - BLACK_LEVEL), 0.0, 1.0);
            double srgb = linear <= 0.0031308 ? 12.92 * linear :
                          1.055 * pow(linear, 1.0 / 2.4) - 0.055;
            s->lut[channel][value] = (unsigned char)CLAMP((int)(srgb * 255 + 0.5), 0, 255);
        }
    }
}

static gboolean stop(GstBaseSrc *base)
{
    NabuCamera *s = (NabuCamera *)base;
    if (s->fd >= 0) {
        if (s->streaming) {
            enum v4l2_buf_type t = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
            ioctl(s->fd, VIDIOC_STREAMOFF, &t);
        }
        for (unsigned i = 0; i < s->count; i++) {
            if (s->mem[i] && s->mem[i] != MAP_FAILED)
                munmap(s->mem[i], s->len[i]);
            s->mem[i] = NULL;
        }
        close(s->fd);
        s->fd = -1;
    }
    if (s->sensor_fd >= 0) {
        if (s->gain_min > 0)
            set_gain(s, s->saved_gain);
        if (s->have_vblank) {
            struct v4l2_control ctrl = { .id = V4L2_CID_VBLANK, .value = s->saved_vblank };
            ioctl(s->sensor_fd, VIDIOC_S_CTRL, &ctrl);
        }
        close(s->sensor_fd);
        s->sensor_fd = -1;
    }
    if (s->lens_fd >= 0) {
        set_focus(s, s->saved_focus);
        close(s->lens_fd);
        s->lens_fd = -1;
    }
    s->count = 0;
    s->streaming = FALSE;
    return TRUE;
}

#define REQUIRE(x) do { if ((x) < 0) goto error; } while (0)
static gboolean start_once(GstBaseSrc *base)
{
    NabuCamera *s = (NabuCamera *)base;
    s->front = is_front(s);
    s->frames = 0;
    // Start from the neutral indoor reference captured on this front sensor.
    s->red_balance = 1.40;
    s->blue_balance = s->front ? 1.67 : 1.64;
    build_luts(s);
    if (s->wake[0] < 0) { errno = EMFILE; goto error; }
    s->width = s->front ? 1640 : 2104;
    s->height = s->front ? 1232 : 1560;
    gchar *capture = capture_device(s->front);
    if (!capture) { errno = ENODEV; goto error; }
    s->fd = open(capture, O_RDWR | O_NONBLOCK | O_CLOEXEC);
    g_free(capture);
    REQUIRE(s->fd);
    struct v4l2_format fmt = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE };
    fmt.fmt.pix_mp.width = s->width;
    fmt.fmt.pix_mp.height = s->height;
    fmt.fmt.pix_mp.field = V4L2_FIELD_NONE;
    fmt.fmt.pix_mp.pixelformat = s->front ? V4L2_PIX_FMT_SBGGR10P : V4L2_PIX_FMT_SGRBG10P;
    REQUIRE(ioctl(s->fd, VIDIOC_S_FMT, &fmt));
    if (fmt.fmt.pix_mp.width != s->width || fmt.fmt.pix_mp.height != s->height ||
        fmt.fmt.pix_mp.num_planes != 1) { errno = EINVAL; goto error; }
    s->stride = fmt.fmt.pix_mp.plane_fmt[0].bytesperline;
    setup_gain(s);
    setup_lens(s);
    struct v4l2_requestbuffers req = {
        .count = 4, .type = fmt.type, .memory = V4L2_MEMORY_MMAP
    };
    REQUIRE(ioctl(s->fd, VIDIOC_REQBUFS, &req));
    s->count = MIN(req.count, 4u);
    if (!s->count) { errno = ENOMEM; goto error; }
    for (unsigned i = 0; i < s->count; i++) {
        struct v4l2_plane p[VIDEO_MAX_PLANES] = {0};
        struct v4l2_buffer b = {
            .type = fmt.type, .memory = req.memory, .index = i,
            .length = VIDEO_MAX_PLANES, .m.planes = p
        };
        REQUIRE(ioctl(s->fd, VIDIOC_QUERYBUF, &b));
        s->len[i] = p[0].length;
        s->mem[i] = mmap(NULL, s->len[i], PROT_READ | PROT_WRITE,
                         MAP_SHARED, s->fd, p[0].m.mem_offset);
        if (s->mem[i] == MAP_FAILED) goto error;
        REQUIRE(ioctl(s->fd, VIDIOC_QBUF, &b));
    }
    enum v4l2_buf_type type = fmt.type;
    REQUIRE(ioctl(s->fd, VIDIOC_STREAMON, &type));
    s->streaming = TRUE;
    // BaseSrc negotiates caps after start() returns. Sending them from here
    // can call the Qt video surface while its main thread waits for state change.
    return TRUE;
error: {
    int saved_errno = errno;
    stop(base);
    errno = saved_errno;
    return FALSE;
}
}

static gboolean start(GstBaseSrc *base)
{
    NabuCamera *s = (NabuCamera *)base;
    g_atomic_int_set(&s->photo_pending, 0);
    for (unsigned attempt = 0; attempt < 2; attempt++) {
        if (start_once(base))
            return TRUE;
        int error = errno;
        if (attempt == 0 && (error == EIO || error == ETIMEDOUT)) {
            GST_WARNING_OBJECT(s, "Camera I/O start error; retrying once after cleanup");
            g_usleep(250000);
            continue;
        }
        GST_ELEMENT_ERROR(s, RESOURCE, OPEN_READ,
                          ("Cannot start nabu camera: %s", g_strerror(error)),
                          ("device=%s", s->device ? s->device : "default"));
        return FALSE;
    }
    return FALSE;
}

static unsigned pixel(const unsigned char *row, unsigned x)
{
    const unsigned char *p = row + (x / 4) * 5;
    return ((unsigned)p[x % 4] << 2) | ((p[4] >> (2 * (x % 4))) & 3);
}

static void bayer_cell(NabuCamera *s, const unsigned char *a, const unsigned char *b,
                       unsigned x, unsigned *red, unsigned *green, unsigned *blue)
{
    unsigned p0 = pixel(a, x), p1 = pixel(a, x + 1);
    unsigned p2 = pixel(b, x), p3 = pixel(b, x + 1);
    *red = s->front ? p3 : p1;
    *green = s->front ? (p1 + p2) / 2 : (p0 + p3) / 2;
    *blue = s->front ? p0 : p2;
}

static double focus_score(NabuCamera *s, const unsigned char *raw)
{
    double edges = 0, brightness = 0;
    for (unsigned y = (s->height / 3) & ~1u; y < s->height * 2 / 3; y += 8) {
        for (unsigned x = (s->width / 3) & ~1u; x < s->width * 2 / 3; x += 8) {
            const unsigned char *row = raw + y * s->stride;
            double centre = (pixel(row, x) + pixel(row + s->stride, x + 1)) / 2.0;
            double left = (pixel(row, x - 4) + pixel(row + s->stride, x - 3)) / 2.0;
            double right = (pixel(row, x + 4) + pixel(row + s->stride, x + 5)) / 2.0;
            double up = (pixel(row - 4 * s->stride, x) + pixel(row - 3 * s->stride, x + 1)) / 2.0;
            double down = (pixel(row + 4 * s->stride, x) + pixel(row + 5 * s->stride, x + 1)) / 2.0;
            if (centre <= BLACK_LEVEL + 24 || centre >= 950)
                continue;
            brightness += centre - BLACK_LEVEL;
            edges += MAX(fabs(left - right) + fabs(up - down) - 8.0, 0.0);
        }
    }
    return brightness > 0 ? edges / brightness : 0;
}

static void begin_focus_scan(NabuCamera *s)
{
    s->focus_scanning = TRUE;
    s->focus_refining = FALSE;
    s->focus_best_score = -1;
    s->focus_best = s->focus_position;
    s->focus_end = s->focus_max;
    s->focus_step = 128;
    s->focus_wait = 2;
    s->focus_deadline = g_get_monotonic_time() + 6000000;
    if (!set_focus(s, s->focus_min)) {
        s->focus_scanning = FALSE;
        s->focus_done_frame = s->frames;
        s->focus_reference = 0;
    }
}

static void finish_focus_scan(NabuCamera *s)
{
    gboolean moved = set_focus(s, s->focus_best);
    s->focus_scanning = FALSE;
    s->focus_done_frame = s->frames;
    s->focus_reference = moved ? MAX(s->focus_best_score, 0.0) : 0;
    GST_INFO_OBJECT(s, "Autofocus completed: position=%d contrast=%.4f",
                    s->focus_position, s->focus_reference);
}

static void update_focus(NabuCamera *s, const unsigned char *raw)
{
    if (s->lens_fd < 0 || g_atomic_int_get(&s->photo_pending))
        return;
    if (!s->focus_scanning) {
        if (!s->focus_done_frame && s->frames >= 32) {
            begin_focus_scan(s);
        } else if (s->focus_done_frame && s->frames - s->focus_done_frame >= 90 &&
                   s->frames % 30 == 0) {
            double score = focus_score(s, raw);
            if ((s->focus_reference > 0.04 && score < s->focus_reference * 0.85) ||
                (s->focus_reference <= 0.04 && score > 0.04))
                begin_focus_scan(s);
        }
        return;
    }
    if (g_get_monotonic_time() > s->focus_deadline) {
        GST_WARNING_OBJECT(s, "Autofocus search deadline reached; keeping the best position");
        finish_focus_scan(s);
        return;
    }
    if (s->focus_wait-- > 0)
        return;
    double score = focus_score(s, raw);
    if (score > s->focus_best_score) {
        s->focus_best_score = score;
        s->focus_best = s->focus_position;
    }
    if (s->focus_position >= s->focus_end) {
        if (!s->focus_refining) {
            s->focus_refining = TRUE;
            s->focus_step = 32;
            s->focus_end = MIN(s->focus_best + 128, s->focus_max);
            if (!set_focus(s, MAX(s->focus_best - 128, s->focus_min)))
                finish_focus_scan(s);
        } else {
            finish_focus_scan(s);
        }
    } else {
        if (!set_focus(s, MIN(s->focus_position + s->focus_step, s->focus_end)))
            finish_focus_scan(s);
    }
    s->focus_wait = 2;
}

static void update_processing(NabuCamera *s, const unsigned char *raw)
{
    double exposure_sum = 0, neutral_sums[3] = {0};
    unsigned exposure_samples = 0, neutral_samples = 0;
    // Meter exposure independently of the white-balance candidate selection.
    for (unsigned y = (s->height / 5) & ~1u; y < s->height * 4 / 5; y += 16) {
        const unsigned char *a = raw + y * s->stride, *b = a + s->stride;
        for (unsigned x = (s->width / 5) & ~1u; x < s->width * 4 / 5; x += 16) {
            unsigned r, g, bl;
            bayer_cell(s, a, b, x, &r, &g, &bl);
            if (MAX(r, MAX(g, bl)) >= 1000 || g <= BLACK_LEVEL + 4)
                continue;
            double red = MAX((int)r - BLACK_LEVEL, 0);
            double green = g - BLACK_LEVEL;
            double blue = MAX((int)bl - BLACK_LEVEL, 0);
            exposure_sum += green;
            exposure_samples++;
            double corrected[3] = {
                red * s->red_balance, green, blue * s->blue_balance
            };
            double maximum = MAX(corrected[0], MAX(corrected[1], corrected[2]));
            double minimum = MIN(corrected[0], MIN(corrected[1], corrected[2]));
            // Colored subjects must not be used as the illuminant reference.
            if (minimum < 96 || maximum >= 900 || maximum - minimum > maximum * 0.10)
                continue;
            neutral_sums[0] += red;
            neutral_sums[1] += green;
            neutral_sums[2] += blue;
            neutral_samples++;
        }
    }
    double green = exposure_samples ? exposure_sum / exposure_samples : 4.0;
    if (neutral_samples > 20 && neutral_sums[0] > 0 && neutral_sums[2] > 0) {
        double red = CLAMP(neutral_sums[1] / neutral_sums[0], 0.5, 3.0);
        double blue = CLAMP(neutral_sums[1] / neutral_sums[2], 0.5, 3.0);
        s->red_balance = 0.92 * s->red_balance + 0.08 * red;
        s->blue_balance = 0.92 * s->blue_balance + 0.08 * blue;
        build_luts(s);
    }
    if (!s->focus_scanning && s->sensor_fd >= 0 && s->gain_min > 0 && (green < 255 || green > 345)) {
        double factor = CLAMP(sqrt(300.0 / MAX(green, 1.0)), 0.75, 1.5);
        int value = (int)(s->gain * factor + 0.5);
        if (value != s->gain)
            set_gain(s, value);
    }
}

static void output_color(NabuCamera *s, unsigned char *dst,
                         unsigned red, unsigned green, unsigned blue)
{
    int r = s->lut[0][red], g = s->lut[1][green], b = s->lut[2][blue];
    int luma = (54 * r + 183 * g + 19 * b + 128) >> 8;
    int chroma = MAX(r, MAX(g, b)) - MIN(r, MIN(g, b));
    // Favor faded colors, with a taper for near-neutral noise and saturated colors.
    int extra = (int)s->saturation_q8 - 256;
    if (extra > 0) {
        extra = extra * (255 - chroma) / 255;
        extra = extra * MIN(chroma, 12) / 12;
    }
    int factor = 256 + extra;
    dst[0] = CLAMP(luma + (r - luma) * factor / 256, 0, 255);
    dst[1] = CLAMP(luma + (g - luma) * factor / 256, 0, 255);
    dst[2] = CLAMP(luma + (b - luma) * factor / 256, 0, 255);
}

static void wrapper_ready_changed(GObject *wrapper, GParamSpec *property, gpointer data)
{
    (void)property;
    gboolean ready = TRUE;
    gint mode = 0;
    g_object_get(wrapper, "ready-for-capture", &ready, "mode", &mode, NULL);
    if (!ready && mode == 1)
        g_atomic_int_set(&((NabuCamera *)data)->photo_pending, 1);
}

static GstFlowReturn create(GstPushSrc *src, GstBuffer **out)
{
    NabuCamera *s = (NabuCamera *)src;
    struct v4l2_plane planes[VIDEO_MAX_PLANES] = {0};
    struct v4l2_buffer b = {
        .type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE, .memory = V4L2_MEMORY_MMAP,
        .length = VIDEO_MAX_PLANES, .m.planes = planes
    };
    gint64 deadline = g_get_monotonic_time() + 5000000;
    for (;;) {
        struct pollfd pfd[2] = {
            { .fd = s->fd, .events = POLLIN },
            { .fd = s->wake[0], .events = POLLIN }
        };
        int timeout = (int)MAX((deadline - g_get_monotonic_time()) / 1000, 0);
        int result = poll(pfd, 2, timeout);
        if (result < 0 && errno == EINTR) continue;
        if (result <= 0) {
            GST_ELEMENT_ERROR(s, RESOURCE, READ, ("Camera frame timeout"), (NULL));
            return GST_FLOW_ERROR;
        }
        if (pfd[1].revents) return GST_FLOW_FLUSHING;
        if (ioctl(s->fd, VIDIOC_DQBUF, &b) < 0) {
            if (errno == EAGAIN || errno == EINTR) continue;
            GST_ELEMENT_ERROR(s, RESOURCE, READ, ("Dequeue failed: %s", g_strerror(errno)), (NULL));
            return GST_FLOW_ERROR;
        }
        break;
    }
    // Consume the newest completed frame when processing fell behind.
    // Returning older frames builds visible latency even after CPU load drops.
    for (;;) {
        struct v4l2_plane next_planes[VIDEO_MAX_PLANES] = {0};
        struct v4l2_buffer next = {
            .type = b.type, .memory = b.memory, .length = VIDEO_MAX_PLANES,
            .m.planes = next_planes
        };
        if (ioctl(s->fd, VIDIOC_DQBUF, &next) < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN) break;
            GST_ELEMENT_ERROR(s, RESOURCE, READ, ("Dequeue failed: %s", g_strerror(errno)), (NULL));
            return GST_FLOW_ERROR;
        }
        if (ioctl(s->fd, VIDIOC_QBUF, &b) < 0) {
            GST_ELEMENT_ERROR(s, RESOURCE, READ, ("Queue failed: %s", g_strerror(errno)), (NULL));
            return GST_FLOW_ERROR;
        }
        b = next;
        memcpy(planes, next_planes, sizeof planes);
        b.m.planes = planes;
    }
    if (b.index >= s->count || planes[0].bytesused < s->stride * s->height) {
        GST_ELEMENT_ERROR(s, RESOURCE, READ, ("Incomplete camera frame"), (NULL));
        if (b.index < s->count) ioctl(s->fd, VIDIOC_QBUF, &b);
        return GST_FLOW_ERROR;
    }
    const unsigned char *raw = s->mem[b.index];
    update_focus(s, raw);
    if (s->frames % 8 == 0)
        update_processing(s, raw);
    unsigned ow = s->width / 2, oh = s->height / 2, stride = GST_ROUND_UP_4(ow * 3);
    GstBuffer *buffer = gst_buffer_new_allocate(NULL, stride * oh, NULL);
    GstMapInfo map;
    if (!buffer || !gst_buffer_map(buffer, &map, GST_MAP_WRITE)) {
        if (buffer) gst_buffer_unref(buffer);
        ioctl(s->fd, VIDIOC_QBUF, &b);
        return GST_FLOW_ERROR;
    }
    memset(map.data, 0, map.size);
    for (unsigned y = 0; y < oh; y++) {
        const unsigned char *a = raw + (y * 2) * s->stride, *c = a + s->stride;
        unsigned char *dst = map.data + y * stride;
        for (unsigned x = 0; x < ow; x++) {
            unsigned r, g, bl;
            bayer_cell(s, a, c, x * 2, &r, &g, &bl);
            output_color(s, dst + x * 3, r, g, bl);
        }
    }
    gst_buffer_unmap(buffer, &map);
    GST_BUFFER_DURATION(buffer) = GST_SECOND / 30;
    GST_BUFFER_OFFSET(buffer) = b.sequence;
    GST_BUFFER_OFFSET_END(buffer) = b.sequence + 1;
    s->frames++;
    if (ioctl(s->fd, VIDIOC_QBUF, &b) < 0) {
        GST_ELEMENT_ERROR(s, RESOURCE, READ, ("Queue failed: %s", g_strerror(errno)), (NULL));
        gst_buffer_unref(buffer);
        return GST_FLOW_ERROR;
    }
    *out = buffer;
    if (g_atomic_int_compare_and_exchange(&s->photo_pending, 1, 0)) {
        // Qt's Sailfish camerabin backend expects this exposure event for
        // shutter audio and the capture animation. Emit it for the real frame.
        gst_element_post_message(GST_ELEMENT(s), gst_message_new_element(GST_OBJECT(s),
            gst_structure_new_empty("photo-capture-start")));
    }
    if (s->frames == 1) {
        // wrappercamerabinsrc starts ready; Qt 5.6 listens only for changes.
        // Publish its actual state once the sensor has delivered a frame.
        GstObject *parent = gst_object_get_parent(GST_OBJECT(s));
        while (parent) {
            if (g_object_class_find_property(G_OBJECT_GET_CLASS(parent), "ready-for-capture")) {
                g_signal_handlers_disconnect_by_func(parent, wrapper_ready_changed, s);
                g_signal_connect_object(parent, "notify::ready-for-capture",
                                        G_CALLBACK(wrapper_ready_changed), s, 0);
                if (s->lens_fd < 0) {
                    g_object_notify(G_OBJECT(parent), "ready-for-capture");
                    s->ready_notified = TRUE;
                }
                gst_object_unref(parent);
                break;
            }
            GstObject *next = gst_object_get_parent(parent);
            gst_object_unref(parent);
            parent = next;
        }
    }
    if (!s->ready_notified && s->focus_done_frame && !s->focus_scanning) {
        GstObject *parent = gst_object_get_parent(GST_OBJECT(s));
        while (parent) {
            if (g_object_class_find_property(G_OBJECT_GET_CLASS(parent), "ready-for-capture")) {
                g_object_notify(G_OBJECT(parent), "ready-for-capture");
                s->ready_notified = TRUE;
                gst_object_unref(parent);
                break;
            }
            GstObject *next = gst_object_get_parent(parent);
            gst_object_unref(parent);
            parent = next;
        }
    }
    return GST_FLOW_OK;
}

static gboolean unlock(GstBaseSrc *base)
{
    NabuCamera *s = (NabuCamera *)base;
    char byte = 1;
    return write(s->wake[1], &byte, 1) >= 0 || errno == EAGAIN;
}

static gboolean unlock_stop(GstBaseSrc *base)
{
    NabuCamera *s = (NabuCamera *)base;
    char bytes[16];
    while (read(s->wake[0], bytes, sizeof bytes) > 0) {}
    return TRUE;
}

static void finalize(GObject *o)
{
    NabuCamera *s = (NabuCamera *)o;
    stop((GstBaseSrc *)s);
    g_free(s->device);
    close(s->wake[0]);
    close(s->wake[1]);
    G_OBJECT_CLASS(nabu_camera_parent_class)->finalize(o);
}

static void nabu_camera_class_init(NabuCameraClass *c)
{
    GObjectClass *g = G_OBJECT_CLASS(c);
    GstElementClass *e = GST_ELEMENT_CLASS(c);
    GstBaseSrcClass *b = GST_BASE_SRC_CLASS(c);
    GstPushSrcClass *p = GST_PUSH_SRC_CLASS(c);
    g->set_property = set_prop;
    g->get_property = get_prop;
    g->finalize = finalize;
    g_object_class_install_property(g, PROP_DEVICE,
        g_param_spec_string("device", "Device", "Camera device; /dev/video6 selects front",
                            "front", G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
    gst_element_class_add_static_pad_template(e, &pad_template);
    gst_element_class_set_static_metadata(e, "Nabu native camera preview", "Source/Video",
                                          "Packed RAW10 capture and basic ISP", "nabu native adaptation");
    b->start = start; b->stop = stop; b->get_caps = get_caps;
    b->unlock = unlock; b->unlock_stop = unlock_stop; p->create = create;
}

static void nabu_camera_init(NabuCamera *s)
{
    s->fd = s->sensor_fd = s->lens_fd = -1;
    GKeyFile *config = g_key_file_new();
    g_key_file_load_from_file(config, "/etc/nabu-camera.conf", G_KEY_FILE_NONE, NULL);
    gchar *configured_position = g_key_file_get_string(config, "Camera", "Position", NULL);
    const char *position = g_getenv("NABU_CAMERA_POSITION");
    if (!position)
        position = configured_position;
    s->device = g_strdup(position && !strcmp(position, "rear") ? "rear" : "front");
    const char *saturation = g_getenv("NABU_CAMERA_SATURATION");
    double amount = 3.3;
    if (g_key_file_has_key(config, "Camera", "Saturation", NULL))
        amount = g_key_file_get_double(config, "Camera", "Saturation", NULL);
    if (saturation)
        amount = g_ascii_strtod(saturation, NULL);
    if (!isfinite(amount)) amount = 3.3;
    g_free(configured_position);
    g_key_file_unref(config);
    s->saturation_q8 = (unsigned)(CLAMP(amount, 0.5, 4.0) * 256 + 0.5);
    s->wake[0] = s->wake[1] = -1;
    if (pipe2(s->wake, O_NONBLOCK | O_CLOEXEC) < 0)
        GST_WARNING_OBJECT(s, "Cannot create wake pipe");
    gst_base_src_set_live((GstBaseSrc *)s, TRUE);
    gst_base_src_set_format((GstBaseSrc *)s, GST_FORMAT_TIME);
    gst_base_src_set_do_timestamp((GstBaseSrc *)s, TRUE);
}

static gboolean plugin_init(GstPlugin *p)
{
    GST_DEBUG_CATEGORY_INIT(nabu_debug, "nabucamera", 0, "Nabu native camera");
    return gst_element_register(p, "nabucamerasrc", GST_RANK_PRIMARY + 100, nabu_camera_get_type());
}
GST_PLUGIN_DEFINE(GST_VERSION_MAJOR, GST_VERSION_MINOR, nabucamera,
                  "Nabu native camera prototype", plugin_init, "0.11", "LGPL",
                  "nabu-native", "https://github.com/Kumar-Jy/linux")
