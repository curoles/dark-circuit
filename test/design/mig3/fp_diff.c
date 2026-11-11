/* Differential test of Mig3's FPU (Zfinx) on TbMig3, judged by the exit status: the same C
 * kernel compiled as Zfinx code (fp_diff_hw.c) and as soft-float code on SoftFloat
 * (fp_diff_sw.c, sw/riscv/softfloat/soft_float.c), run side by side on the same operands;
 * every result and the flags must agree, bit for bit.
 *
 * Operands from a xorshift: a fourth special values (zeros, infinities, NaNs quiet and
 * signalling, subnormals, the largest, 2^24, 2^31, ties), a fourth near 1.0 (exponents
 * 97..157: sums, products and quotients mostly in range), a fourth any bits, a fourth the
 * operand before with one of its low bits flipped (cancellation); the integer any bits or
 * a special one. CASES cases in each of the five rounding modes (frm and SoftFloat's
 * softfloat_roundingMode). Per case both kernels run, and the FP_DIFF_OUTS results with the
 * flags each one raised are compared. The first mismatches are printed (semihosting): the
 * mode, the case, the result or its flags, the operands. Exit 0 when nothing differs, else
 * 1. The compiled code puts the FPU's instructions in compiler order, register allocation
 * and dependences, which no hand-written test does.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#include <stdint.h>

#include "fp_diff_kernel.h"
#include "semihosting/semihosting.h"
#include "softfloat.h"

#define CASES        8      // per rounding mode
#define MODES        5
#define REPORTS      4      // mismatches printed at most

void fp_kernel_hw(uint32_t a, uint32_t b, uint32_t c, int32_t i, uint32_t *out,
                  uint32_t *flags);
void fp_kernel_sw(uint32_t a, uint32_t b, uint32_t c, int32_t i, uint32_t *out,
                  uint32_t *flags);

static const uint32_t special[] = {
    0x00000000, 0x80000000, 0x3f800000, 0xbf800000, 0x7f800000, 0xff800000,
    0x7fc00000, 0x7fa00000, 0xffc00001, 0x00000001, 0x007fffff, 0x00800000,
    0x7f7fffff, 0x4b800000, 0x4f000000, 0xcf000000, 0x4f800000, 0x3f000000,
    0x3fc00000, 0x40200000
};
#define SPECIALS (sizeof special / sizeof special[0])

static const int32_t special_int[] = {
    0, -1, 1, (int32_t)0x80000000, 0x7fffffff, 0x01000001, -0x01000001, 0x00ffffff
};
#define SPECIAL_INTS (sizeof special_int / sizeof special_int[0])

static uint32_t rnd = 0x2545f491;
static uint32_t prev = 0x3f800000;

static uint32_t next(void)
{
    rnd ^= rnd << 13;
    rnd ^= rnd >> 17;
    rnd ^= rnd << 5;
    return rnd;
}

static uint32_t operand(void)
{
    uint32_t r = next();
    uint32_t v;
    switch (r & 3) {
    case 0:  v = special[(r >> 2) % SPECIALS]; break;
    case 1:  v = (r & 0x807fffff) | ((97 + (r >> 2) % 61) << 23); break;
    case 2:  v = next(); break;
    default: v = prev ^ (1u << ((r >> 2) % 8)); break;
    }
    prev = v;
    return v;
}

static int32_t integer(void)
{
    uint32_t r = next();
    return (r & 3) == 0 ? special_int[(r >> 2) % SPECIAL_INTS] : (int32_t)next();
}

static void put(const char *s) { semihost_write0(s); }

static void put_hex(uint32_t v)
{
    char s[11];
    s[0] = ' ';
    for (int k = 0; k < 8; k++)
        s[1 + k] = "0123456789abcdef"[(v >> (28 - 4 * k)) & 0xf];
    s[9] = 0;
    put(s);
}

static void set_frm(uint32_t mode) { __asm__ volatile("csrw frm, %0" : : "r"(mode)); }

int main(void)
{
    // Results 0 .. FP_DIFF_OUTS-1, then the flags of each.
    uint32_t hw[2 * FP_DIFF_OUTS];
    uint32_t sw[2 * FP_DIFF_OUTS];
    unsigned bad = 0;
    for (uint32_t mode = 0; mode < MODES; mode++) {
        set_frm(mode);
        softfloat_roundingMode = (uint_fast8_t)mode;
        for (unsigned k = 0; k < CASES; k++) {
            uint32_t a = operand();
            uint32_t b = operand();
            uint32_t c = operand();
            int32_t  i = integer();
            fp_kernel_hw(a, b, c, i, hw, hw + FP_DIFF_OUTS);
            fp_kernel_sw(a, b, c, i, sw, sw + FP_DIFF_OUTS);
            for (int n = 0; n < 2 * FP_DIFF_OUTS; n++) {
                uint32_t h = hw[n];
                uint32_t s = sw[n];
                if (h == s)
                    continue;
                if (bad < REPORTS) {
                    put("fp_diff: mode");
                    put_hex(mode);
                    put(" case");
                    put_hex(k);
                    put(n < FP_DIFF_OUTS ? " out" : " flags of");
                    put_hex((uint32_t)(n % FP_DIFF_OUTS));
                    put(": hw");
                    put_hex(h);
                    put(" sw");
                    put_hex(s);
                    put(" a b c i");
                    put_hex(a);
                    put_hex(b);
                    put_hex(c);
                    put_hex((uint32_t)i);
                    put("\n");
                }
                bad++;
            }
        }
    }
    put(bad ? "fp_diff: mismatches\n" : "fp_diff: all agree\n");
    return bad != 0;
}
