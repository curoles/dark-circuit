/* Fast Incrementor C TB.
 * author: Igor Lesik 2019
 *
 */
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <limits>

#include "Vtb_top.h"
#include "eda/verilator_tick.h"


static void tik_tok(Vtb_top& top)
{
    sim_tick(top);
    sim_tick(top);
}

static inline void print_bin32(uint32_t n) {
    for (uint32_t i = 1 << 31; i > 0; i = i >> 1)
        (n & i)? printf("1"): printf("0");
}

static bool test_incr4_eq5(Vtb_top& top)
{
    printf("%lu: Testing 4+1==5...\n", sim_time());

    top.in = 4;

    tik_tok(top);

    if (top.out9 != 5 and top.cy9 == 0) return false;

    return true;
}

static bool test_incrAll1_eq0(Vtb_top& top)
{
    printf("%lu: Testing All1+1==0...\n", sim_time());

    top.in = 0b111'111'111;

    tik_tok(top);

    if (top.out9 != 0 and top.cy9 != 1) return false;

    return true;
}

static bool test_random(Vtb_top& top, uint32_t iter_id)
{
    if (0 == (iter_id % 10'000))
        printf("\rTesting random %u", iter_id);

    uint32_t a = std::rand();
    uint32_t a9 = a & 0x1FF;
    uint32_t a16 = a & 0xFFFF;

    top.in = a;

    tik_tok(top);

    bool match9 = (top.out9 == (a9 + 1) and top.cy9 == 0) or
                  (top.out9 == 0 and top.cy9);

    if (!match9) {
        printf("\nError: %u + 1 = %u, carry-out=%u\n", a9, top.out9, top.cy9);
        printf("0x%x + 1 = 0x%x\n", a9, top.out9);
        print_bin32(a9); printf(" <- a\n");
        print_bin32(top.out9); printf(" <- result of a + 1\n");
        return false;
    }

    bool match16 = (top.out16 == (a16 + 1) and top.cy16 == 0) or
                   (top.out16 == 0 and top.cy16);

    if (!match16) {
        printf("\nError: %u + 1 = %u, carry-out=%u\n", a16, top.out16, top.cy16);
        printf("0x%x + 1 = 0x%x\n", a16, top.out16);
        print_bin32(a16); printf(" <- a\n");
        print_bin32(top.out16); printf(" <- result of a + 1\n");
        return false;
    }

    return true;
}

int main(int argc, char* argv[])
{
    printf("\n\nTest Fast Incrementor\n");

    Verilated::commandArgs(argc, argv);

    // Top TB module instantiation
    Vtb_top top;

    using TestFunc = bool (*)(Vtb_top&);

    TestFunc tests[] = {
        test_incr4_eq5, test_incrAll1_eq0
    };

    for (auto test : tests)
    {
        if (!test(top)) {
            printf("FAIL\n");
            return 1;
        }

        if (Verilated::gotFinish()) {
            printf("SIM ERROR\n");
            return 1;
        }
    }

    static constexpr uint32_t MAX_RANDOM_TESTS = 10'000'001u;

    for (uint32_t i = 0; i < MAX_RANDOM_TESTS and !Verilated::gotFinish(); ++i)
    {
        if (!test_random(top, i)) {
            printf("\nFAIL\n");
            return 1;
        }

    }

    printf("\n\nDone\n");

    return 0;
}
