/* Included before every source of a benchmark (-include bench_main.h): the main of the
 * benchmark becomes bench_main, which the main of bench.c calls. Not in assembly: crt0.S
 * calls the main of bench.c.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#ifndef __ASSEMBLER__
#define main bench_main
#endif
