// SPDX-License-Identifier: GPL-2.0-only
/* Temporary diagnostic: touch gesture scan with the display still powered. */
#include <linux/init.h>
#include <linux/module.h>
#include <drm/drm_notifier.h>

static int __init nabu_gesture_diag_init(void)
{
	struct drm_touch_sleep sleep = { };

	mi_drm_notifier_call_chain(MI_DRM_EVENT_TOUCH_SLEEP, &sleep);
	pr_info("nabu-gesture-diag: display-on gesture scan active=%u error=%d\n",
		sleep.gesture_active, sleep.error);
	return sleep.error ? sleep.error : sleep.gesture_active ? 0 : -ENODEV;
}

static void __exit nabu_gesture_diag_exit(void)
{
	enum drm_notifier_data blank = MI_DRM_BLANK_UNBLANK;

	/* The operator must power the display on before unloading. */
	mi_drm_notifier_call_chain(MI_DRM_EVENT_BLANK, &blank);
	pr_info("nabu-gesture-diag: normal touch resume queued\n");
}
module_init(nabu_gesture_diag_init);
module_exit(nabu_gesture_diag_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Temporary nabu display-on gesture diagnostic");
