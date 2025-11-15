/* Minimal implementation of ___chkstk_ms for MinGW
 * This function is called by the compiler to probe the stack
 * when allocating more than 4KB (one page) of stack space.
 *
 * The function subtracts the requested size from %rsp and touches
 * each page to ensure the stack guard pages work correctly.
 */

void ___chkstk_ms(void);

__asm__(
    ".globl ___chkstk_ms\n"
    "___chkstk_ms:\n"
    /* %rax contains the number of bytes to allocate */
    /* Subtract from stack pointer */
    "    subq    %rax, %rsp\n"
    /* Touch the first byte of each 4KB page */
    "    movq    %rax, %r10\n"
    "    shrq    $12, %r10\n"      /* Divide by 4096 to get page count */
    "    testq   %r10, %r10\n"
    "    je      2f\n"
    "1:\n"
    "    subq    $4096, %rsp\n"
    "    orq     $0, (%rsp)\n"     /* Touch the page */
    "    decq    %r10\n"
    "    jnz     1b\n"
    "2:\n"
    "    ret\n"
);
