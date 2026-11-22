/* SPDX-License-Identifier: MIT */
#include "ladspa.h"
#include <math.h>
#include <stdlib.h>

typedef struct {
    LADSPA_Data *input, *output;
    double b0, b1, b2, a1, a2, z1, z2;
} Highpass;

static LADSPA_Handle instantiate(const LADSPA_Descriptor *descriptor,
                                 unsigned long rate)
{
    (void)descriptor;
    if (rate < 1000) return NULL;
    Highpass *h = calloc(1, sizeof(*h));
    if (!h) return NULL;
    /* Same two-pole, Q=1/sqrt(2), 200 Hz high-pass as the listening test. */
    double omega = 2.0 * 3.14159265358979323846 * 200.0 / rate;
    double c = cos(omega), alpha = sin(omega) / sqrt(2.0);
    double a0 = 1.0 + alpha;
    h->b0 = (1.0 + c) / (2.0 * a0);
    h->b1 = -(1.0 + c) / a0;
    h->b2 = h->b0;
    h->a1 = -2.0 * c / a0;
    h->a2 = (1.0 - alpha) / a0;
    return h;
}

static void connect_port(LADSPA_Handle handle, unsigned long port,
                         LADSPA_Data *data)
{
    Highpass *h = handle;
    if (port == 0) h->input = data;
    else if (port == 1) h->output = data;
}

static void activate(LADSPA_Handle handle)
{
    Highpass *h = handle;
    h->z1 = h->z2 = 0.0;
}

static void run(LADSPA_Handle handle, unsigned long count)
{
    Highpass *h = handle;
    for (unsigned long i = 0; i < count; ++i) {
        double x = h->input[i];
        double y = h->b0 * x + h->z1;
        h->z1 = h->b1 * x - h->a1 * y + h->z2;
        h->z2 = h->b2 * x - h->a2 * y;
        h->output[i] = (LADSPA_Data)y;
    }
    if (fabs(h->z1) < 1e-30) h->z1 = 0;
    if (fabs(h->z2) < 1e-30) h->z2 = 0;
}

static const LADSPA_PortDescriptor ports[] = {
    LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO,
    LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO,
};
static const char * const names[] = {"Input", "Output"};
static const LADSPA_PortRangeHint hints[2] = {{0,0,0}, {0,0,0}};
static const LADSPA_Descriptor descriptor = {
    .UniqueID = 41001,
    .Label = "nabu_speaker_highpass",
    .Properties = LADSPA_PROPERTY_HARD_RT_CAPABLE,
    .Name = "Nabu speaker 200 Hz high-pass",
    .Maker = "Sailfish nabu native adaptation",
    .Copyright = "MIT",
    .PortCount = 2,
    .PortDescriptors = ports,
    .PortNames = names,
    .PortRangeHints = hints,
    .instantiate = instantiate,
    .connect_port = connect_port,
    .activate = activate,
    .run = run,
    .cleanup = free,
};

const LADSPA_Descriptor *ladspa_descriptor(unsigned long index)
{
    return index == 0 ? &descriptor : NULL;
}
