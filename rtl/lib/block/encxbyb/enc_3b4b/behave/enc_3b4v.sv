
module Enc3b4b (
    input  logic [2:0] B,        // 3-bit input data (H G F) -> din[7:5]
    input  logic       K,        // Control character flag
    input  logic       disp_in,  // Disparity output *from the 5b/6b block*
    output logic [3:0] O,        // 4-bit output symbol (f g h j)
    output logic       disp_out  // Final running disparity output
);

    // Rename inputs to standard notation for clarity
    logic F, G, H;
    assign F = B[0];
    assign G = B[1];
    assign H = B[2];

    // Classifications based on the number of 1s in the 3-bit input
    logic M03, M12, M21, M30;
    assign M03 = (B == 3'b000);             // Zero 1s (D.x.0)
    assign M12 = ($countones(B) == 1);       // One 1  (D.x.1, D.x.2, D.x.4)
    assign M21 = ($countones(B) == 2);       // Two 1s (D.x.3, D.x.5, D.x.6)
    assign M30 = (B == 3'b111);             // Three 1s (D.x.7)

    // S_code conditions 
    // Resolves special boundary cases (like K28.7 or specific D.x.7 combinations)
    logic S_code;
    assign S_code = (K || (M30 && disp_in));

    // Determine if the 4b block needs its disparity complemented/inverted
    logic compl;
    assign compl = (disp_in  && (M30 || (M21 && S_code))) || 
                   (!disp_in && (M03 || (M12 && S_code)));

    // Base boolean equations for the 4-bit sub-block output (uncomplemented)
    logic f, g, h, j;
    assign f = F && !M03;
    assign g = G || M03;
    assign h = H;
    assign j = (M21 && !S_code) || (M03) || (K);

    // Apply disparity inversion to ensure DC balance
    assign O[0] = f ^ compl; // f
    assign O[1] = g ^ compl; // g
    assign O[2] = h ^ compl; // h
    assign O[3] = j ^ compl; // j

    // Calculate final tracking disparity leaving this block
    assign disp_out = disp_in ^ (M30 || M03 || (M21 && S_code) || (M12 && S_code));

endmodule

