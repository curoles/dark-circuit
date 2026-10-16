/**
 * @brief  Verilator time simulation helpers.
 * @author Igor Lesik 2020
 *
 */
#include "verilator_tick.h"

// Current simulation time.
//
// This is a 64-bit integer to reduce wrap over issues and allow modulus.
static vluint64_t main_time = 0;

// sc_time_stamp is called by $time in Verilog.
// Converts to double, to match what SystemC does.
double sc_time_stamp() {
    return main_time;
}

uint64_t sim_time() {
    return main_time;
}

void sim_change_clk(VTbTop& top)
{
    top.clk = main_time & 1;
    top.eval();

    main_time++;
}

