/* Set up stacks and jump to C code */

.global _start

.global dmb
.global dsb
.global flush_cache

_start:
    /* kernel.img is loaded at 0x8000
     *
     * 0x2c00 - 0x3c00  User/system stack
     * 0x2800 - 0x2c00  IRQ stack
     * 0x2400 - 0x2800  Abort stack
     * 0x2000 - 0x2400  Supervisor (SWI/SVC) stack
     *
     * All stacks grow down; decrement then store
     *
     * Stack addresses are stored in the stack pointers as
     * 0x80000000+address, as this means the stack pointer doesn't have
     * to change when the MMU is turned on (before the MMU is on, accesses
     * to 0x80000000 go to 0x00000000, and so on). Eventually, the stacks
     * will be given a proper home
     */

    mov     r4, #0x80000000

    /* SVC stack (for SWIs) at 0x2000 */
    /* The processor appears to start in this mode, but change to it
     * anyway
     */
    cps     #0x13       /* Change to supervisor (SVC) mode */
    add     sp, r4, #0x2400

    /* ABORT stack at 0x2400 */
    cps     #0x17       /* Change to Abort mode */
    add     sp, r4, #0x2800

    /* IRQ stack at 0x2800 */
    cps     #0x12       /* Change to IRQ mode */
    add     sp, r4, #0x2c00

    /* System stack at 0x2c00 */
    cps     #0x1f       /* Change to system mode */
    add     sp, r4, #0x3c00

    /* Stay in system mode from now on */

    /* Zero bss section */
    ldr     r0, =__bss_start__
    ldr     r1, =__bss_end__
    mov     r2, #0
bss_zero_loop:
    cmp     r0,r1
    it      lt
    strlt   r2,[r0], #4
    blt     bss_zero_loop

    /* Enable the FPU */
    mrc     p15, 0, r0, c1, c0, 2
    orr     r0, r0, #0x300000            /* single precision */
    orr     r0, r0, #0xC00000            /* double precision */
    mcr     p15, 0, r0, c1, c0, 2
    mov     r0, #0x40000000
    fmxr    fpexc, r0

    /* Turn on unaligned memory access */
    mrc     p15, #0, r4, c1, c0, #0
    orr     r4, #0x400000   /* 1<22 */
    mcr     p15, #0, r4, c1, c0, #0

    /* Start L1 Cache */
    mov     r4, #0
    mcr     p15, #0, r4, c7, c7, #0     /* Invalidate Caches */
    mcr     p15, #0, r4, c8, c7, #0     /* Invalidate TLB */
    mrc     p15, #0, r4, c1, c0, #0     /* Read Control Register Configuration Data */
    orr     r4, #0x1000                 /* Instruction */
    orr     r4, #0x0004                 /* Data */
    orr     r4, #0x0800                 /* Branch Prediction */
    mcr     p15, #0, r4, c1, c0, #0     /* Write Control Register Configuration Data */

    /* Enable interrupts */
    ldr     r4, =interrupt_vectors
    mcr     p15, #0, r4, c12, c0, #0
    cpsie   i

    /* Call constructors of all global objects */
    ldr     r0, =__init_array_start
    ldr     r1, =__init_array_end
globals_init_loop:
    cmp     r0, r1
    it      lt
    ldrlt   r2, [r0], #4
    blxlt   r2
    blt     globals_init_loop

    /* Jump to main */
    bl      main

    /* Hang if main function returns */
hang:
    b       hang


/*
 * Data memory barrier
 * No memory access after the DMB can run until all memory accesses before it
 * have completed
 */
dmb:
    mov     r0, #0
    mcr     p15, #0, r0, c7, c10, #5
    mov     pc, lr

/*
 * Data synchronisation barrier
 * No instruction after the DSB can run until all instructions before it have
 * completed
 */
dsb:
    mov     r0, #0
    mcr     p15, #0, r0, c7, c10, #4
    mov     pc, lr

/*
 * Clean and invalidate entire cache
 * Flush pending writes to main memory
 * Remove all data in data cache
 */
flush_cache:
    mov     r0, #0
    mcr     p15, #0, r0, c7, c10, #0
    mov     pc, lr

/*
 * Interrupt vectors table
 */
    .align  5
interrupt_vectors:
    b       bad_exception /* RESET */
    b       bad_exception /* UNDEF */
    b       interrupt_swi
    b       interrupt_prefetch_abort
    b       interrupt_data_abort
    b       bad_exception /* Unused vector */
    b       interrupt_irq
    b       bad_exception /* FIQ */