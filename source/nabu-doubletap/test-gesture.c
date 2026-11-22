/* SPDX-License-Identifier: GPL-2.0-only */
#include <stdbool.h>
#include <assert.h>
#include <stdio.h>
#include "../linux/drivers/input/touchscreen/nt36523/nt36xxx_gesture.h"
int main(void)
{
    unsigned char direct[] = {0, 15 << 3, 0, 0};
    unsigned char extended[] = {0, 30 << 3, 1, 15};
    assert(nvt_is_doubletap(direct, sizeof(direct)));
    assert(nvt_is_doubletap(extended, sizeof(extended)));
    for (unsigned int len = 0; len < 4; ++len) {
        assert(!nvt_is_doubletap(direct, len));
        assert(!nvt_is_doubletap(extended, len));
    }
    for (unsigned int id = 0; id < 32; ++id) {
        direct[1] = id << 3;
        assert(nvt_is_doubletap(direct, sizeof(direct)) == (id == 15));
    }
    for (unsigned int page = 0; page < 256; ++page) {
        extended[2] = page;
        assert(nvt_is_doubletap(extended, sizeof(extended)) == (page == 1));
    }
    extended[2] = 1;
    for (unsigned int id = 0; id < 256; ++id) {
        extended[3] = id;
        assert(nvt_is_doubletap(extended, sizeof(extended)) == (id == 15));
    }
    puts("PASS: direct, extended, short, non-doubletap and wrong-page packets");
    return 0;
}
