module Enc5b6b (
    input  logic [4:0] A,        // 5-bit input data (H G F E D) -> din[4:0]
    input  logic       K,        // Control character flag
    input  logic       disp_in,  // Current disparity (0 = negative, 1 = positive)
    output logic [5:0] O,        // 6-bit output symbol (a b c d e i)
    output logic       disp_out  // Next disparity
);
    // Standard classifications based on input bit combinations
    logic L04, L13, L22, L31, L40;
    
    // Count the number of 1s in the 5-bit input to classify minterms
    assign L04 = (A == 5'b00000);
    assign L13 = ($countones(A) == 1);
    assign L22 = ($countones(A) == 2);
    assign L31 = ($countones(A) == 3);
    assign L40 = ($countones(A) == 4);

    // Complementary classification helper
    logic L13_or_L40_or_L04;
    assign L13_or_L40_or_L04 = L13 || L40 || L04;

    // Determine if the 6b block needs its disparity complemented/inverted
    logic compl;
    assign compl = (disp_in  && (L31 || (L22 && K))) || 
                   (!disp_in && (L13 || L04));

    // Base boolean equations for the 6-bit sub-block output (uncomplemented)
    logic a, b, c, d, e, i;
    assign a = A[0];
    assign b = (A[1] && !L04) || L13;
    assign c = A[2] || L04 || (L13 && A[0]);
    assign d = A[3] && !L40;
    assign e = A[4] || L13_or_L40_or_L04;
    assign i = (L22 && !A[4] && !A[3]) || (L13 && !A[0] && !A[1]) || (L04) || (K);

    // Apply disparity inversion to maintain DC balance
    assign O[0] = a ^ compl;
    assign O[1] = b ^ compl;
    assign O[2] = c ^ compl;
    assign O[3] = d ^ compl;
    assign O[4] = e ^ compl;
    assign O[5] = i ^ compl;

    // Track output disparity leaving this block
    assign disp_out = disp_in ^ (L31 || L40 || L04 || (L22 && K));

endmodule
