/* Freestanding stand-in for XZ Embedded's xz_config.h (see xzboot.c) */
#include <stddef.h>
void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
void *memset(void *dst, int c, size_t n);
int memcmp(const void *a, const void *b, size_t n);
size_t strlen(const char *s);
size_t strnlen(const char *s, size_t max);
void *memchr(const void *s, int c, size_t n);
char *strrchr(const char *s, int c);
