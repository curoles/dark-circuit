/* CoreMark (EEMBC) on the Mig CPUs: the port functions CoreMark calls (timing, seeds, start
 * and end), with core_portme.h. CoreMark's own files are compiled unchanged.
 *
 * The run is CoreMark's standard performance run: seeds 0, 0, 0x66 and 2000 bytes of data;
 * ITERATIONS (-DITERATIONS=<n>) iterations. Ticks are clock cycles (rdcycle), so CoreMark/MHz
 * is iterations * 10^6 / ticks, without a clock frequency. Simulated runs are far shorter
 * than the 10 s CoreMark asks of a valid score: the result is "simulated, n iterations".
 *
 * The exit status: CoreMark's main always returns 0, and its own error count also counts the
 * run shorter than 10 s. So portable_fini, which CoreMark calls at the end, checks the three
 * CRCs of the run itself against the known values of the performance run (they do not depend
 * on the iterations) and exits with 1 when one differs; else main returns 0. It also prints
 * one line with the iterations, the cycles and CoreMark/MHz (semihosting).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include "coremark.h"
#include "semihosting.h"

#ifndef ITERATIONS
#define ITERATIONS 1
#endif

// The seeds of the performance run, read at run time so that the compiler can not fold
// them; seed4 is the number of iterations.
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

ee_u32 default_num_contexts = 1;

// The CRCs of the performance run (seeds 0, 0, 0x66, 2000 bytes), as in core_main.c.
#define CRC_LIST   0xe714
#define CRC_MATRIX 0x1fd7
#define CRC_STATE  0x8e3a

static CORE_TICKS start_cycles, stop_cycles;

static CORE_TICKS cycles(void)
{
    CORE_TICKS c;
    __asm__ volatile("rdcycle %0" : "=r"(c));
    return c;
}

void start_time(void)
{
    start_cycles = cycles();
}

void stop_time(void)
{
    stop_cycles = cycles();
}

CORE_TICKS get_time(void)
{
    return stop_cycles - start_cycles;
}

// Seconds at a clock of 1 MHz: then CoreMark's iterations a second are CoreMark/MHz. Only
// CoreMark's report (not printed) uses them.
secs_ret time_in_secs(CORE_TICKS ticks)
{
    return ticks / 1000000u;
}

void portable_init(core_portable* p, int* argc, char* argv[])
{
    (void)argc;
    (void)argv;
    p->portable_id = 1;
}

// Append the decimal digits of n to s, return the end.
static char* put_uint(char* s, ee_u32 n)
{
    char digits[10];
    int  k = 0;
    do {
        digits[k++] = (char)('0' + n % 10);
        n /= 10;
    } while (n != 0);
    while (k > 0)
        *s++ = digits[--k];
    return s;
}

static char* put_str(char* s, const char* t)
{
    while (*t)
        *s++ = *t++;
    return s;
}

// "CoreMark: <n> iterations in <ticks> cycles: <x.xxx> CoreMark/MHz", by long division in
// 32 bits (no 64-bit division without a C library): n * 10^6 fits for n up to 4000.
static void print_result(ee_u32 n, CORE_TICKS ticks)
{
    char   line[96];
    char*  s = line;
    ee_u32 q = n * 1000000u;
    ee_u32 r = q % ticks;
    s = put_str(s, "CoreMark: ");
    s = put_uint(s, n);
    s = put_str(s, " iterations in ");
    s = put_uint(s, ticks);
    s = put_str(s, " cycles: ");
    s = put_uint(s, q / ticks);
    *s++ = '.';
    for (int k = 0; k < 3; k++) {
        r *= 10;
        *s++ = (char)('0' + r / ticks);
        r %= ticks;
    }
    s = put_str(s, " CoreMark/MHz\n");
    *s = 0;
    semihost_write0(line);
}

// The results of the run hold p (core_results.port): their CRCs decide the exit status.
void portable_fini(core_portable* p)
{
    const core_results* res = (const core_results*)((char*)p - offsetof(core_results, port));
    p->portable_id = 0;
    print_result(res->iterations, get_time());
    if (res->crclist != CRC_LIST || res->crcmatrix != CRC_MATRIX || res->crcstate != CRC_STATE)
        semihost_exit(1);
}
