/* Packed SIMD: the lanes of a word, for the blocks of rtl/lib/numeric/packed.
 *
 * A word of 32 or 64 bits is split into lanes of 8, 16 or 32 bits (RISC-V P's .b, .h, .w)
 * that compute alone. The blocks give flags per byte (at the top bit of every byte); a
 * lane's flags are those of its top byte, and lane_broadcast spreads them over the lane's
 * bytes for the selects that act on the whole lane (saturation, minimum, maximum);
 * lane_tops marks every lane's top byte, the one with its sign. Words up to 64 bits (8
 * bytes): a 32-bit user takes the low half of the results.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package PackedPkg;

    // Lane width.
    typedef enum logic [1:0] {
        LANE_8,         // bytes
        LANE_16,        // halfwords
        LANE_32         // words
    } lane_e;

    // A packed multiply's operation (PackedMul), in every 16-bit lane {ah, al} * {bh, bl},
    // or the dot product of every 32-bit group (two lanes).
    typedef enum logic [2:0] {
        MUL_16,         // the 16 x 16 product
        MUL_B00,        // al*bl: the even bytes (RISC-V P pmul.h.b00)
        MUL_B11,        // ah*bh: the odd bytes (pmul.h.b11)
        MUL_B01,        // al*bh: a's even byte, b's odd one (pmul.h.b01)
        MUL_DOT_B,      // the four byte products summed (pm4add.b)
        MUL_DOT_H       // the two 16 x 16 products summed (pm2add.h)
    } mul_e;

    // The bits that start a lane, of a 64-bit word (bit 0 starts one always, not marked):
    // the cut of a SegmentedKoggeStoneAdder.
    function automatic logic [63:0] lane_cuts(lane_e lane);
        logic [63:0] c;
        c = '0;
        c[32] = 1'b1;                       // every lane width starts a lane at bit 32
        if (lane != LANE_32) begin          // 8 and 16: also at 16 and 48
            c[16] = 1'b1;
            c[48] = 1'b1;
        end
        if (lane == LANE_8) begin           // 8: at every byte
            c[8]  = 1'b1;
            c[24] = 1'b1;
            c[40] = 1'b1;
            c[56] = 1'b1;
        end
        return c;
    endfunction

    // Flags at the top byte of each lane, spread over the lane's bytes: byte k of the result
    // is the flag of byte k's lane (flags at the other bytes are not used).
    function automatic logic [7:0] lane_broadcast(logic [7:0] flags, lane_e lane);
        case (lane)
            LANE_8:  return flags;
            LANE_16: return {{2{flags[7]}}, {2{flags[5]}}, {2{flags[3]}}, {2{flags[1]}}};
            default: return {{4{flags[7]}}, {4{flags[3]}}};
        endcase
    endfunction

    // The top byte of every lane (with the lane's sign bit), of a 64-bit word: byte k is 1
    // when it is its lane's top byte.
    function automatic logic [7:0] lane_tops(lane_e lane);
        case (lane)
            LANE_8:  return 8'b1111_1111;
            LANE_16: return 8'b1010_1010;
            default: return 8'b1000_1000;
        endcase
    endfunction

endpackage
