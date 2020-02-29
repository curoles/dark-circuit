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


int main(int argc, char* argv[])
{
    printf("\n\nTest Shift Register\n");

    Verilated::commandArgs(argc, argv);

    // Top TB module instantiation
    Vtb_top top;


    printf("\n\nDone\n");

    return 0;
}
