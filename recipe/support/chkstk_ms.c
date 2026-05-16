/* Minimal implementation of ___chkstk_ms for MinGW
 * This function is called by the compiler to probe the stack
 * when allocating more than 4KB (one page) of stack space.
 *
 * According to the Microsoft x64 ABI:
 * - Input: RAX contains the number of bytes to allocate
 * - The caller will subtract RAX from RSP after this returns
 * - Our job: Touch each page to ensure stack guard pages work
 * - Must preserve all registers except RAX, R10, R11
 */

void ___chkstk_ms(void);

__asm__(
    ".globl ___chkstk_ms\n"
    "___chkstk_ms:\n"
    /* RAX contains the number of bytes to allocate */
    /* Probe each 4KB page by touching it */
    "    pushq   %rcx\n"           /* Save RCX */
    "    pushq   %rax\n"           /* Save allocation size */
    "    cmpq    $0x1000, %rax\n"  /* Compare with 4096 */
    "    leaq    16(%rsp), %rcx\n" /* RCX = current stack pointer (skip saved regs) */
    "    jb      2f\n"             /* If less than one page, skip probing */
    "1:\n"
    "    subq    $0x1000, %rcx\n"  /* Move down one page */
    "    orq     $0, (%rcx)\n"     /* Touch the page */
    "    subq    $0x1000, %rax\n"  /* Decrease remaining size */
    "    cmpq    $0x1000, %rax\n"  /* More than one page left? */
    "    ja      1b\n"             /* Continue if yes */
    "2:\n"
    "    subq    %rax, %rcx\n"     /* Touch final partial page */
    "    orq     $0, (%rcx)\n"
    "    popq    %rax\n"           /* Restore allocation size */
    "    popq    %rcx\n"           /* Restore RCX */
    "    ret\n"
);
