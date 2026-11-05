OUTPUT_ARCH(m68k)
ENTRY(_start)

/* Program ROM space of the main 68000. The reset vector sits at 0 and the
 * code is placed by the .org directives inside the source. We link .text at 0
 * so those offsets are absolute addresses. */
SECTIONS
{
  . = 0;
  .text : {
    *(.text)
    *(.text.*)
    *(.rodata)
    *(.rodata.*)
  }
}
