/*
 *
 * Takes in two bits of the multiplicand at a time and generates the partial product
 * using other inputs that come in from the booth encoder cell BENCD. 
 *
 */
module BMLD0
(
    input  wire   X2,
    input  wire   A,
    input  wire   S,
    input  wire   M0,
    input  wire   M1,
    output wire   PP
);

    wire m1_sel_n;
    wire m0_sel_n;
    
    wire X2_n;
    wire A_n;
    wire S_n;
    wire M0_n;
    wire M1_n;

    assign X2_n = ~X2;
    assign A_n  = ~A ;
    assign S_n  = ~S ;
    assign M0_n = ~M0;
    assign M1_n = ~M1;    
    
    AOI22D0 aoi22d0_0 (.A1(A_n), .A2(M1), .B1(S_n), .B2(M1_n), .ZN(m1_sel_n));
    
    AOI22D0 aoi22d0_1 (.A1(A_n), .A2(M0), .B1(S_n), .B2(M0_n), .ZN(m0_sel_n));
    
    AOI22D0 aoi22d0_2 (.A1(X2_n), .A2(m1_sel_n), .B1(X2), .B2(m0_sel_n), .ZN(PP));	

endmodule
