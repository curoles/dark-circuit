/* ALU1 C TB.
 *
 * Author: Igor Lesik 2020
 *
 */
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <limits>
#include <random>

#include "VTbTop.h"
#include "VTbTop_TbTop.h"
#include "eda/verilator/verilator_tick.h"

static void set_inputs(VTbTop& top)
{
    static std::default_random_engine rand_engine;
    static std::uniform_int_distribution<uint64_t> random64bits;
    static std::uniform_int_distribution<uint8_t> randomCmd(0, VTbTop_TbTop::NR_COMMANDS-1);

    top.cmd = randomCmd(rand_engine);
    top.in1 = random64bits(rand_engine);
    top.in2 = random64bits(rand_engine);
}

static bool check_outputs(const VTbTop& top)
{
    uint64_t correct_val{0};

    switch (top.cmd)
    {
        case 0: correct_val = top.in1; break;
        case 1: correct_val = top.in1 + 1; break;
        case 2: correct_val = top.in1 + top.in2; break;
        case 3: correct_val = top.in1 + top.in2 + 1; break;
        case 4: correct_val = top.in1 - top.in2 - 1; break;
        case 5: correct_val = top.in1 - top.in2; break;
        case 6: correct_val = top.in1 - 1; break;
        case 7: correct_val = top.in1; break;
    }

    if (top.out != correct_val) {
        printf("HW %lx vs correct %lx, cmd=%u\n", top.out, correct_val, top.cmd);
        return false;
    }

    return true;
}

int main(int argc, char* argv[])
{
    printf("\n\nTest ALU1\n");

    Verilated::commandArgs(argc, argv);

    // Top TB module instantiation
    VTbTop top;

    Tick tick(top);

    for (unsigned int i = 0; i < 1000; ++i)
    {
        set_inputs(top);
        tick();
        if (!check_outputs(top)) {
            printf("\n\nFAIL i:%u\n", i);
            return 1;
        }
        //printf("%u cmd=%u\n", i, top.cmd);
    }

    printf("\n\nSUCCESS\n");

    return 0;
}
