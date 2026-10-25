// SPDX-License-Identifier: GPL-2.0
/*
 * XZ decompression for trampoline64xz.S, with XZ Embedded (tools/kexec-probe/xz,
 * 0BSD-style licence) built freestanding. Single-call mode: the output buffer
 * doubles as the dictionary, so the decoder only needs its own state from
 * the small bump heap below.
 */
#include <stddef.h>
#include <stdint.h>

#include "xz.h"

#define HEAP_BASE	0x47e00000UL	/* see trampoline64xz.S */
#define HEAP_SIZE	0x00100000UL

static size_t heap_used;

void *malloc(size_t size)
{
	void *p = (void *)(HEAP_BASE + heap_used);

	size = (size + 15) & ~(size_t)15;
	if (size > HEAP_SIZE - heap_used)
		return NULL;
	heap_used += size;
	return p;
}

void free(void *ptr)
{
}

void *memcpy(void *dst, const void *src, size_t n)
{
	uint8_t *d = dst;
	const uint8_t *s = src;

	while (n--)
		*d++ = *s++;
	return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
	uint8_t *d = dst;
	const uint8_t *s = src;

	if (d < s)
		return memcpy(dst, src, n);
	while (n--)
		d[n] = s[n];
	return dst;
}

void *memset(void *dst, int c, size_t n)
{
	uint8_t *d = dst;

	while (n--)
		*d++ = (uint8_t)c;
	return dst;
}

int memcmp(const void *a, const void *b, size_t n)
{
	const uint8_t *x = a, *y = b;

	for (; n; n--, x++, y++)
		if (*x != *y)
			return *x - *y;
	return 0;
}

/* Returns the decompressed size, or a negative xz_ret - 100 */
long xz_unpack(const uint8_t *in, size_t in_len, uint8_t *out, size_t out_max)
{
	struct xz_buf b = {
		.in = in, .in_pos = 0, .in_size = in_len,
		.out = out, .out_pos = 0, .out_size = out_max,
	};
	struct xz_dec *s;
	enum xz_ret ret;

	xz_crc32_init();
	s = xz_dec_init(XZ_SINGLE, 0);
	if (!s)
		return -100 - XZ_MEM_ERROR;
	ret = xz_dec_run(s, &b);
	if (ret != XZ_STREAM_END)
		return -100 - (long)ret;
	return (long)b.out_pos;
}

size_t strnlen(const char *s, size_t max)
{
	size_t n = 0;

	while (n < max && s[n])
		n++;
	return n;
}

size_t strlen(const char *s)
{
	return strnlen(s, (size_t)-1);
}

void *memchr(const void *s, int c, size_t n)
{
	const uint8_t *p = s;

	for (; n; n--, p++)
		if (*p == (uint8_t)c)
			return (void *)p;
	return NULL;
}

char *strrchr(const char *s, int c)
{
	const char *last = NULL;

	do {
		if (*s == (char)c)
			last = s;
	} while (*s++);
	return (char *)last;
}
