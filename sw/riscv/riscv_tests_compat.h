/* riscv-tests with either toolchain: included first into every riscv-tests program
 * (-include, the RISCV_TESTS_FLAGS of the design tests; cmake/riscv.cmake).
 *
 * The rv32mi tests define mtvec_handler with .global after env/p/riscv_test.h declared it
 * .weak (riscv-test-env, still so upstream in 2026). GNU as lets the binding change; clang's
 * assembler rejects it. Under clang .global becomes .weak: the handler is still defined,
 * and in a program of one object a weak definition links the same.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#ifdef __clang__
#define global weak
#endif
