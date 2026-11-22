// SPDX-License-Identifier: GPL-2.0-only
/* Temporary isolation test: normal touch scan while panel remains blank. */
#include <linux/init.h>
#include <linux/module.h>
#include <drm/drm_notifier.h>
static int __init awake_init(void)
{
 enum drm_notifier_data blank = MI_DRM_BLANK_UNBLANK;
 mi_drm_notifier_call_chain(MI_DRM_EVENT_BLANK, &blank);
 pr_info("nabu-touch-awake-diag: queued touch-only resume\n");
 return 0;
}
static void __exit awake_exit(void)
{
 struct drm_touch_sleep sleep = { };
 mi_drm_notifier_call_chain(MI_DRM_EVENT_TOUCH_SLEEP, &sleep);
 pr_info("nabu-touch-awake-diag: restored touch sleep active=%u error=%d\n", sleep.gesture_active, sleep.error);
}
module_init(awake_init);
module_exit(awake_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Temporary nabu touch-only resume diagnostic");
