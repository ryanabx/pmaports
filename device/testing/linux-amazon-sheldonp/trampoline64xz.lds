/* trampoline64xz.S runs from LINK_BASE after copying itself there */
ENTRY(_start)
SECTIONS
{
	. = 0x48000000;
	.text : { *(.text.entry) *(.text*) }
	.rodata : { *(.rodata*) }
	.data : { *(.data*) }
	. = ALIGN(4096);
	.payload : { *(.payload) }
	_end = .;
	_image_size = _end - 0x48000000;
	.bss (NOLOAD) : { __bss_start = .; *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; }
	/DISCARD/ : { *(.ARM.exidx*) *(.comment) }
}
