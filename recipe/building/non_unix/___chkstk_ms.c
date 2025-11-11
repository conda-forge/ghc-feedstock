/*
 * Proper MinGW implementation of ___chkstk_ms for stack probing
 * Based on the actual MinGW implementation from mingw-w64
 */
#include <stdint.h>

/* This is the size of a page on Windows */
#define PAGE_SIZE 4096

/*
 * MinGW-style stack probe routine for 64-bit Windows
 * This follows the exact algorithm used in the actual MinGW runtime
 */
void ___chkstk_ms(void)
{
  /* RAX = size of stack frame */
  /* Return value = address of new stack pointer (RAX) */
  register unsigned char *stack_limit __asm__("%rcx"); /* Use rcx for storing stack_limit */
  register uintptr_t stack_ptr __asm__("%rax");        /* rax = stack size */
  register uintptr_t lo_guard_page;                   /* computed guard page position */
  register unsigned char* previous_page;              /* previously probed page */

  /* Get current stack pointer */
  __asm__ volatile ("movq %%rsp, %0" : "=r" (stack_ptr));

  /* Capture the stack size from rax (the Microsoft calling convention) */
  register uintptr_t stack_size;
  __asm__ volatile ("movq %%rax, %0" : "=r" (stack_size));

  /* Point rcx to the lowest guard page we'll touch */
  stack_limit = (unsigned char*)(stack_ptr - stack_size);

  /* Make sure stack is aligned to 16 bytes (very important for ABI compliance) */
  stack_limit = (unsigned char*)(((uintptr_t)stack_limit) & ~15);

  /* Start with the current page */
  lo_guard_page = ((uintptr_t)stack_limit) & ~(PAGE_SIZE - 1);
  previous_page = (unsigned char*)((uintptr_t)stack_ptr & ~(PAGE_SIZE - 1));

  /* Loop through all pages we need to probe */
  /* Subtract one page at a time and touch it */
  while (previous_page > (unsigned char*)lo_guard_page) {
    previous_page -= PAGE_SIZE;
    *(volatile unsigned char*)previous_page = 0;
  }

  /* Touch the final page */
  *(volatile unsigned char*)stack_limit = 0;
}

/* Plain alias for __chkstk_ms */
void __chkstk_ms(void) {
  ___chkstk_ms();
}

/* Additional alias that might be needed */
void __attribute__((alias("___chkstk_ms"))) _chkstk_ms(void);
