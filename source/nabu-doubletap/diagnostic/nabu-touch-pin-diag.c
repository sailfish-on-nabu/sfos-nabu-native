// SPDX-License-Identifier: GPL-2.0-only
/* Temporary read-only observation of the existing touch IRQ GPIO.
 * No GPIO request, mux, direction, pull, or IRQ configuration changes.
 * Sampling cannot rule out pulses shorter than the sampling interval.
 */
#include <linux/module.h>
#include <linux/hrtimer.h>
#include <linux/gpio/consumer.h>
#include <linux/gpio/driver.h>
#include <linux/err.h>
static struct gpio_device *gdev;
static struct gpio_desc *pin;
static struct hrtimer poll_timer;
static unsigned long long samples, highs, lows, rises, falls, errors;
static int level;
static ktime_t deadline;
module_param(samples, ullong, 0444);
module_param(highs, ullong, 0444);
module_param(lows, ullong, 0444);
module_param(rises, ullong, 0444);
module_param(falls, ullong, 0444);
module_param(errors, ullong, 0444);
module_param(level, int, 0444);
static enum hrtimer_restart sample_pin(struct hrtimer *timer)
{
 int v = gpiod_get_raw_value(pin);
 samples++;
 if (v < 0) errors++;
 else {
  if (v) highs++; else lows++;
  if (v != level) { if (v) rises++; else falls++; level = v; }
 }
 /* Self-stop after at most fifteen minutes, independent of user response. */
 if (ktime_compare(ktime_get(), deadline) >= 0) return HRTIMER_NORESTART;
 hrtimer_forward_now(timer, ns_to_ktime(100000));
 return HRTIMER_RESTART;
}
static int __init pin_init(void)
{
 int ret;
 gdev = gpio_device_find_by_label("3100000.pinctrl");
 if (IS_ERR_OR_NULL(gdev)) return gdev ? PTR_ERR(gdev) : -ENODEV;
 pin = gpio_device_get_desc(gdev, 39);
 if (IS_ERR(pin)) { ret = PTR_ERR(pin); goto err; }
 if (gpiod_cansleep(pin)) { ret = -EINVAL; goto err; }
 ret = gpiod_get_raw_value(pin);
 if (ret < 0) goto err;
 level = ret;
 deadline = ktime_add_ms(ktime_get(), 900000);
 hrtimer_setup(&poll_timer, sample_pin, CLOCK_MONOTONIC, HRTIMER_MODE_REL);
 hrtimer_start(&poll_timer, ns_to_ktime(100000), HRTIMER_MODE_REL);
 pr_info("nabu-touch-pin-diag: read-only GPIO39 sampling, initial=%d\n", level);
 return 0;
err:
 gpio_device_put(gdev);
 return ret;
}
static void __exit pin_exit(void)
{
 hrtimer_cancel(&poll_timer);
 pr_info("nabu-touch-pin-diag: samples=%llu rise=%llu fall=%llu high=%llu low=%llu errors=%llu\n", samples, rises, falls, highs, lows, errors);
 gpio_device_put(gdev);
}
module_init(pin_init);
module_exit(pin_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Temporary read-only touch IRQ pin observation");
