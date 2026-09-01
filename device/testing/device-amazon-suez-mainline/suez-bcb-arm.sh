#!/bin/sh
# Arm the recovery fallback, as early in userspace as the initramfs allows.
#
# This board has no serial console and no button-free way back from a hang: if
# the kernel wedges, the watchdog resets it straight back into the same image
# and it loops. The one automatic escape is LK's bootloader control block --
# 13 bytes in the MISC partition that make the next boot land in recovery
# instead -- and it has to be written *before* whatever goes wrong.
#
# So this arms it on every boot and suez-bcb-disarm.service clears it once the
# boot has demonstrably succeeded. If a boot never gets that far, the next one
# goes to recovery, which self-clears the block and is reachable over adb.
#
# The failure mode if the disarm does not run is one wasted boot into recovery,
# not a stranded device.
#
# Only command[32] is written: 13 bytes of text plus 19 NULs. Nothing else in
# MISC is touched -- the neighbouring partitions are seccfg/nvram-class, and
# p16/p17 hold the amonet payload, so writing the wrong one would be serious.

MISC=""

# Prefer the by-name link when something has already populated it.
for candidate in /dev/block/platform/*/*/by-name/MISC \
		 /dev/block/platform/*/by-name/MISC; do
	if [ -e "$candidate" ]; then
		MISC="$candidate"
		break
	fi
done

# Otherwise fall back to the known layout, but only if the partition is the
# expected 512 KiB. That is a weak check on its own; it is here to catch a
# wholly different layout rather than to identify MISC positively.
if [ -z "$MISC" ] && [ "$(cat /sys/class/block/mmcblk0p9/size 2>/dev/null)" = "1024" ]; then
	MISC=/dev/mmcblk0p9
fi

if [ -z "$MISC" ]; then
	echo "suez-bcb: no MISC partition found, not arming the fallback"
	exit 0
fi

printf 'boot-recovery\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0' \
	| dd of="$MISC" bs=32 count=1 conv=notrunc 2>/dev/null
sync

# Read it back: an arm that silently failed is worse than none, because it is
# the thing being relied on.
if dd if="$MISC" bs=13 count=1 2>/dev/null | grep -q 'boot-recovery'; then
	echo "suez-bcb: fallback armed via $MISC"
else
	echo "suez-bcb: WARNING failed to arm the fallback via $MISC"
fi
