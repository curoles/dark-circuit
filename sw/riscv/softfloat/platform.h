/* SoftFloat's platform header for bare-metal RISC-V RV32 (SoftFloat's build directories have
 * one per host; this one is for programs of the cores, sw/riscv/softfloat/soft_float.c).
 *
 * Little endian; small functions inline; 64-bit integers are fast enough on RV32IM (the
 * compiler makes them from 32-bit instructions), but no 64-by-32 division, which would call
 * libgcc's __udivdi3 (programs link without a library): SOFTFLOAT_FAST_DIV64TO32 stays off,
 * so f32_div takes its reciprocal path. No __builtin_clz (a library call without Zbb): the
 * leading zeros come from SoftFloat's table.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
#define LITTLEENDIAN 1
#define INLINE_LEVEL 5
#define SOFTFLOAT_FAST_INT64
#define INLINE static inline
