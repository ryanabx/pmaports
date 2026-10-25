// SPDX-License-Identifier: GPL-2.0
/*
 * Append /chosen "sheldon,bootargs-append" to /chosen bootargs, for
 * trampoline64xz.S. LK builds bootargs itself: its own Android arguments
 * (root=/dev/dm-0, init=/init, ro, rootwait), then only the first ~150
 * characters of the boot image's command line, then more of its own. The
 * arguments that must win go in the DTB instead (scripts/mk-mainline-bootimg.sh)
 * and are appended here, so that they come last. Without the property the
 * DTB is left alone, as under kexec.
 */
#include <stddef.h>
#include <stdint.h>

#include "libfdt.h"

#define BOOTARGS_MAX	2048	/* arm64 COMMAND_LINE_SIZE */

static char bootargs[BOOTARGS_MAX];

/* Returns the DTB to boot with: out, or dtb when there is nothing to do */
void *dtb_fixup(void *dtb, void *out, size_t out_size)
{
	const char *cur, *add;
	int chosen, cur_len, add_len;
	size_t n = 0;

	if (fdt_check_header(dtb))
		return dtb;
	chosen = fdt_path_offset(dtb, "/chosen");
	if (chosen < 0)
		return dtb;
	add = fdt_getprop(dtb, chosen, "sheldon,bootargs-append", &add_len);
	if (!add || add_len < 2)
		return dtb;
	cur = fdt_getprop(dtb, chosen, "bootargs", &cur_len);
	if (!cur)
		cur_len = 0;
	if ((size_t)cur_len + (size_t)add_len + 1 > BOOTARGS_MAX)
		return dtb;

	if (cur_len > 1) {
		memcpy(bootargs, cur, cur_len - 1);
		n = cur_len - 1;
		bootargs[n++] = ' ';
	}
	memcpy(bootargs + n, add, add_len);

	if (fdt_open_into(dtb, out, out_size))
		return dtb;
	chosen = fdt_path_offset(out, "/chosen");
	if (chosen < 0 || fdt_setprop_string(out, chosen, "bootargs", bootargs))
		return dtb;
	return out;
}
