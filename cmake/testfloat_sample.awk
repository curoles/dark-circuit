# Sample testfloat_gen's cases (cmake/testfloat.cmake, dc_testfloat_cases): keep a case when
# a fixed pseudo-random generator picks it, one in k (k = 1: every case), or when n > 0 and n
# or more of its operands are special (zero, infinity, NaN). A case is a line in hex: the
# operands, the result, the flags (NF - 2 operands). The generator is a 16-bit linear
# congruential one, exact in any awk's arithmetic, so every machine writes the same files; a
# stride (every k-th line) aliases with testfloat_gen's regular order and misses whole kinds
# of operands. The pick uses the generator's high bits (r < 65536 / k): its low bits repeat
# with short periods (bit j every 2^(j+1) lines), and r % k with an even k aliased as a
# stride does (no finite x / 0 among f32_div's picks: kb rtl/lib/numeric/fp32/div_sqrt).
#
# @author    Igor Lesik
# @copyright 2026 Igor Lesik, MIT License

# x is a zero, an infinity or a NaN (an fp32 in hex: exponent field all ones, or all zero bits
# but the sign).
function special(x,    e) {
    e = substr(x, 1, 3)
    return x == "00000000" || x == "80000000" || e ~ /^(7F[89A-F]|FF[89A-F])$/
}

BEGIN { r = 1 }

{
    r = (r * 25173 + 13849) % 65536
    s = 0
    for (i = 1; i <= NF - 2; i++)
        s += special($i)
    if (r < 65536 / k || (n > 0 && s >= n))
        print
}
