/* Adder-Comparator Verilator C TB.
 * author: Igor Lesik 2019
 *
 */
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <limits>

#include "Vtb_top.h"
#include "verilated.h"

// Current simulation time.
//
// This is a 64-bit integer to reduce wrap over issues and allow modulus.
static vluint64_t main_time = 0;

// sc_time_stamp is called by $time in Verilog.
// Converts to double, to match what SystemC does.
double sc_time_stamp () {
    return main_time;
}

static void change_clk(Vtb_top& top)
{
    top.clk = main_time % 2;
    top.eval();

    main_time++;
}

static void tick(Vtb_top& top)
{
    change_clk(top);
    change_clk(top);
}

static void tik_tok(Vtb_top& top)
{
    tick(top);
    tick(top);
}

static bool test_2plus3_eq5(Vtb_top& top)
{
    printf("%lu: Testing 2+3==5...\n", main_time);

    top.a = 2;
    top.b = 3;
    top.c = 5;

    tik_tok(top);

    if (top.eq != 0b1) return false;

    return true;
}

#if 0
static inline void print_bin32(uint32_t n) {
    printf("10987654321098765432109876543210\n");
    printf(" |         |         |          \n");
    for (uint32_t i = 1 << 31; i > 0; i = i >> 1)
        (n & i)? printf("1"): printf("0");
    printf("\n");
    printf(" ----====                       \n");
}

#define STR(x) #x

#define ASSERT(x, fmt, ...) if (!(x)) { \
  printf("\nAssertion '%s' failed\n",STR(x)); \
  printf("iteration: %u, opcode:0x%8x\n",iter_id,rand_opcode); \
  print_bin32(rand_opcode); \
  printf(fmt "\n", ##__VA_ARGS__); \
  fflush(NULL); \
  return false; }
#endif

static bool test_random(Vtb_top& top, uint32_t iter_id)
{
    if (0 == (iter_id % 10'000))
        printf("\rTesting random %u", iter_id);

    uint32_t a = std::rand();
    uint32_t b = std::rand();
    uint32_t c = a + b;

    top.a = a;
    top.b = b;
    top.c = c;

    tik_tok(top);

    return top.eq;
}

int main(int argc, char* argv[])
{
    printf("\n\nTest Carry-Save Addition Adder-Comparator\n");

    Verilated::commandArgs(argc, argv);

    // Top TB module instantiation
    Vtb_top top;

    using TestFunc = bool (*)(Vtb_top&);

    TestFunc tests[] = {
        test_2plus3_eq5
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
