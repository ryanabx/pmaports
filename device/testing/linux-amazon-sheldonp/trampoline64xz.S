/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Trampoline for sheldon(p) that boots an XZ-compressed arm64 Image, so a
 * mainline kernel fits the 16 MiB boot partition. LK (or kexec-tools) loads
 * it like a zImage at 0x40008000 and passes the DTB in r2; see
 * trampoline64.S for the ATF call and the watchdog and UART handling, which
 * this repeats.
 *
 * The decompressed Image goes to IMAGE_BASE, where this file is loaded, so it
 * first copies itself to LINK_BASE and runs from there. Decompression runs
 * with a flat 1 MiB-section MMU map and the caches on (it takes minutes
 * uncached); the D-cache is cleaned by set/way and the MMU turned off again
 * before the jump.
 *
 *   clang --target=armv7a-none-eabi -marm -DPAYLOAD='"Image.xz"' ...
 *   (scripts/build-mainline.sh links it with trampoline64xz.lds and xzboot.c)
 *
 * Before decompressing, dtbfix.c appends /chosen "sheldon,bootargs-append"
 * to LK's bootargs (LK keeps only ~150 characters of the boot image's own).
 *
 * Record at 0x4447f800, as trampoline64.S, with more statuses: 6 XZ failed
 * (+0x14: the xzboot.c error), 7 running from LINK_BASE, 8 MMU on, 9 XZ
 * returned (+0x1c: its result), 10 MMU off again.
 */

#define RECORD		0x4447f800
#define TOPRGU		0x10007000
#define WDT_MODE	0x00
#define WDT_LENGTH	0x04
#define WDT_RST		0x08
#define WDT_LENGTH_30S	0xf008
#define WDT_RST_RELOAD	0x1971
#define WDT_MODE_RESET	0x22000015

#define TOPCKGEN	0x10000000
#define CLK_CFG_UART	0x060
#define UART_SEL_PDN	(1 << 23)
#define PERICFG		0x10003000
#define PERI_PDN0_CLR	0x010
#define PERI_UART_GATES	(7 << 20)

#define IMAGE_BASE	0x40200000
#define ATF_BASE	0x43000000
#define ARM64_MAGIC	0x644d5241
#define MTK_SIP_KERNEL_BOOT	0x82000200
#define KERNEL_64BIT	1

/* Scratch below LINK_BASE (0x48000000, see the linker script) */
#define HEAP_BASE	0x47e00000	/* xzboot.c's bump heap, 1 MiB */
#define STACK_TOP	0x47fe0000
#define TTB_ADDR	0x47ff0000	/* 16 KiB first-level table */
#define DTB_SAFE	0x47c00000	/* the DTB, if it sits where the Image goes */
#define DTB_MAX		0x00100000
#define DTB_FIX		0x47a00000	/* dtbfix.c's output, 1 MiB */
#define DTB_FIX_SIZE	0x00100000

/* Cacheable sections: DRAM from 0x40000000 up to the TEE at 0x79bc0000 */
#define DRAM_FIRST_MB	0x400
#define DRAM_END_MB	0x79b
#define RECORD_MB	0x444		/* kept uncached, so the record lands */
#define SECT_NORMAL	0x1c0e		/* WB-WA, AP=RW, domain 0 */
#define SECT_DEVICE	0x0c12		/* strongly ordered, XN */

	.arm
	.arch_extension sec
	.section .text.entry, "ax"
	.global _start
_start:
	b	entry
	.rept	8
	nop
	.endr
	.word	0x016f2818		@ +0x24: zImage magic
	.word	0			@ +0x28: start
	.word	_image_size		@ +0x2c: end (from the linker script)

entry:
	mov	r6, r2			@ DTB, kept for the SMC
	ldr	r4, =RECORD
	ldr	r5, =TOPRGU

	ldr	r3, =0x3436584b		@ "KX64"
	str	r3, [r4, #0x00]
	ldr	r3, [r5, #WDT_MODE]
	str	r3, [r4, #0x04]
	str	r6, [r4, #0x08]
	adr	r3, _start
	str	r3, [r4, #0x0c]
	mov	r3, #0
	str	r3, [r4, #0x10]
	str	r3, [r4, #0x14]
	mrs	r3, cpsr
	str	r3, [r4, #0x18]

	ldr	r3, =WDT_LENGTH_30S
	str	r3, [r5, #WDT_LENGTH]
	ldr	r3, =WDT_RST_RELOAD
	str	r3, [r5, #WDT_RST]
	ldr	r3, =WDT_MODE_RESET
	str	r3, [r5, #WDT_MODE]
	dsb	sy

	/* Copy everything up to _end to LINK_BASE (above us), then jump there */
	adr	r0, _start
	ldr	r1, =_start
	cmp	r0, r1
	beq	relocated
	ldr	r2, =_image_size
	add	r2, r0, r2
1:	ldmia	r0!, {r7-r10}
	stmia	r1!, {r7-r10}
	cmp	r0, r2
	blo	1b
	mov	r0, #0
	mcr	p15, 0, r0, c7, c5, 0	@ ICIALLU
	mcr	p15, 0, r0, c7, c5, 6	@ BPIALL
	dsb	sy
	isb
	ldr	pc, =relocated

relocated:
	ldr	sp, =STACK_TOP
	ldr	r0, =__bss_start
	ldr	r1, =__bss_end
	mov	r2, #0
2:	cmp	r0, r1
	strlo	r2, [r0], #4
	blo	2b
	mov	r0, #7
	str	r0, [r4, #0x10]

	/*
	 * kexec-tools may put the DTB right after this file, inside the
	 * Image's future footprint: move it out of the way first.
	 */
	ldr	r0, =IMAGE_BASE
	cmp	r6, r0
	blo	13f
	ldr	r0, =ATF_BASE
	cmp	r6, r0
	bhs	13f
	ldr	r1, [r6, #4]
	rev	r1, r1			@ totalsize
	ldr	r0, =DTB_MAX
	cmp	r1, r0
	movhi	r0, #3
	bhi	fail
	ldr	r0, =DTB_SAFE
	mov	r2, r6
	mov	r6, r0
	add	r1, r2, r1
14:	ldr	r3, [r2], #4
	str	r3, [r0], #4
	cmp	r2, r1
	blo	14b
	str	r6, [r4, #0x08]
13:
	bl	mmu_on
	mov	r0, #8
	str	r0, [r4, #0x10]

	/* Append the DTB's own arguments to LK's bootargs (dtbfix.c) */
	mov	r0, r6
	ldr	r1, =DTB_FIX
	ldr	r2, =DTB_FIX_SIZE
	bl	dtb_fixup
	mov	r6, r0
	ldr	r4, =RECORD
	str	r6, [r4, #0x08]

	ldr	r0, =payload
	ldr	r1, =_end
	sub	r1, r1, r0
	ldr	r2, =IMAGE_BASE
	ldr	r3, =ATF_BASE - IMAGE_BASE
	bl	xz_unpack
	mov	r8, r0
	ldr	r4, =RECORD
	mov	r0, #9
	str	r0, [r4, #0x10]
	str	r8, [r4, #0x1c]
	bl	mmu_off
	ldr	r4, =RECORD
	mov	r0, #10
	str	r0, [r4, #0x10]
	cmp	r8, #0
	strlt	r8, [r4, #0x14]
	movlt	r0, #6
	blt	fail

	/* Image header checks, as trampoline64.S */
	ldr	r7, =IMAGE_BASE
	ldr	r3, [r7, #0x38]
	ldr	r8, =ARM64_MAGIC
	cmp	r3, r8
	movne	r0, #1
	bne	fail
	ldr	r3, [r7, #0x14]
	cmp	r3, #0
	movne	r0, #2
	bne	fail
	ldr	r9, [r7, #0x10]
	mov	r10, r7
	add	r11, r10, r9
	ldr	r3, =ATF_BASE
	cmp	r11, r3
	movhi	r0, #2
	bhi	fail
	ldr	r3, [r6, #4]
	rev	r3, r3
	add	r3, r6, r3
	cmp	r6, r11
	bhs	3f
	cmp	r3, r10
	movhi	r0, #3
	bhi	fail
3:
	ldr	r3, =TOPCKGEN
	ldr	r0, [r3, #CLK_CFG_UART]
	bic	r0, r0, #UART_SEL_PDN
	str	r0, [r3, #CLK_CFG_UART]
	ldr	r3, =PERICFG
	mov	r0, #PERI_UART_GATES
	str	r0, [r3, #PERI_PDN0_CLR]

	mov	r0, #4
	str	r0, [r4, #0x10]
	dsb	sy

	ldr	r0, =MTK_SIP_KERNEL_BOOT
	mov	r1, r10
	mov	r2, r6
	mov	r3, #0
	mov	r4, #KERNEL_64BIT
	smc	#0

	ldr	r4, =RECORD
	str	r0, [r4, #0x14]
	mov	r0, #5
fail:
	ldr	r4, =RECORD
	str	r0, [r4, #0x10]
	dsb	sy
4:	wfi
	b	4b

/*
 * Clean (r0 = 1) or only invalidate (r0 = 0) the data caches to the point of
 * coherency by set/way, as arch/arm/mm/cache-v7.S v7_flush_dcache_all.
 * Clobbers r0-r5 and r7-r12. No stack: with the D-cache off, a push would go
 * to memory and the clean would then overwrite it with older dirty lines.
 */
dcache_setway:
	mov	r12, lr
	mov	r8, r0
	dmb
	mrc	p15, 1, r0, c0, c0, 1	@ CLIDR
	ands	r3, r0, #0x7000000
	mov	r3, r3, lsr #23		@ LoC * 2
	beq	9f
	mov	r10, #0
5:	add	r2, r10, r10, lsr #1	@ level * 3
	mov	r1, r0, lsr r2
	and	r1, r1, #7
	cmp	r1, #2
	blt	8f			@ no data cache at this level
	mcr	p15, 2, r10, c0, c0, 0	@ CSSELR
	isb
	mrc	p15, 1, r1, c0, c0, 0	@ CCSIDR
	and	r2, r1, #7
	add	r2, r2, #4		@ log2(line size)
	movw	r4, #0x3ff
	ands	r4, r4, r1, lsr #3	@ max way
	clz	r5, r4			@ way shift
	movw	r7, #0x7fff
	ands	r7, r7, r1, lsr #13	@ max set
6:	mov	r9, r4
7:	orr	r11, r10, r9, lsl r5
	orr	r11, r11, r7, lsl r2
	cmp	r8, #0
	mcreq	p15, 0, r11, c7, c6, 2	@ DCISW
	mcrne	p15, 0, r11, c7, c14, 2	@ DCCISW
	subs	r9, r9, #1
	bge	7b
	subs	r7, r7, #1
	bge	6b
8:	add	r10, r10, #2
	cmp	r3, r10
	bgt	5b
9:	mov	r10, #0
	mcr	p15, 2, r10, c0, c0, 0
	dsb	sy
	isb
	bx	r12

mmu_on:
	push	{r4-r11, lr}
	mov	r0, #0
	bl	dcache_setway
	ldr	r0, =TTB_ADDR
	mov	r1, #0
10:	cmp	r1, #DRAM_FIRST_MB
	blo	11f
	ldr	r3, =RECORD_MB
	cmp	r1, r3
	beq	11f
	ldr	r3, =DRAM_END_MB
	cmp	r1, r3
	bhs	11f
	ldr	r2, =SECT_NORMAL
	b	12f
11:	ldr	r2, =SECT_DEVICE
12:	orr	r2, r2, r1, lsl #20
	str	r2, [r0, r1, lsl #2]
	add	r1, r1, #1
	cmp	r1, #4096
	blo	10b
	dsb	sy
	mov	r1, #0
	mcr	p15, 0, r1, c8, c7, 0	@ TLBIALL
	mcr	p15, 0, r1, c7, c5, 0	@ ICIALLU
	mcr	p15, 0, r1, c7, c5, 6	@ BPIALL
	mcr	p15, 0, r1, c2, c0, 2	@ TTBCR: short descriptors, TTBR0 only
	mcr	p15, 0, r0, c2, c0, 0	@ TTBR0
	mov	r1, #1
	mcr	p15, 0, r1, c3, c0, 0	@ DACR: domain 0 client
	dsb	sy
	isb
	mrc	p15, 0, r1, c1, c0, 0	@ SCTLR
	bic	r1, r1, #(1 << 1)	@ no alignment faults
	bic	r1, r1, #(3 << 28)	@ no TEX remap, no access flag
	orr	r1, r1, #(1 << 0)	@ MMU
	orr	r1, r1, #(1 << 2)	@ D-cache
	orr	r1, r1, #(1 << 11)	@ branch prediction
	orr	r1, r1, #(1 << 12)	@ I-cache
	mcr	p15, 0, r1, c1, c0, 0
	isb
	pop	{r4-r11, pc}

mmu_off:
	push	{r4-r11, lr}
	mrc	p15, 0, r1, c1, c0, 0
	bic	r1, r1, #(1 << 2)	@ stop allocating, then clean
	mcr	p15, 0, r1, c1, c0, 0
	isb
	mov	r0, #1
	bl	dcache_setway
	mrc	p15, 0, r1, c1, c0, 0
	bic	r1, r1, #(1 << 0)
	bic	r1, r1, #(1 << 11)
	bic	r1, r1, #(1 << 12)
	mcr	p15, 0, r1, c1, c0, 0
	isb
	mov	r1, #0
	mcr	p15, 0, r1, c7, c5, 0	@ ICIALLU
	mcr	p15, 0, r1, c7, c5, 6	@ BPIALL
	mcr	p15, 0, r1, c8, c7, 0	@ TLBIALL
	dsb	sy
	isb
	pop	{r4-r11, pc}

	.ltorg

	.section .payload, "a"
	.balign	4096
payload:
	.incbin	PAYLOAD
	.balign	16
