/* Freestanding stand-in for XZ Embedded's xz_config.h (see xzboot.c) */
#include <stddef.h>
void *malloc(size_t size);
void free(void *ptr);
