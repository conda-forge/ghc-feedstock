#ifdef _WIN64
__declspec(naked) void __chkstk_ms(void)
{
    __asm {
        push    rax
        push    rcx
        cmp     rax, 0x1000
        lea     rcx, [rsp+24]
        jb      skip
loop_start:
        sub     rcx, 0x1000
        test    [rcx], rcx
        sub     rax, 0x1000
        cmp     rax, 0x1000
        ja      loop_start
skip:
        sub     rcx, rax
        test    [rcx], rcx
        pop     rcx
        pop     rax
        ret
    }
}

__declspec(naked) void ___chkstk_ms(void)
{
    __asm {
        jmp __chkstk_ms
    }
}
#endif