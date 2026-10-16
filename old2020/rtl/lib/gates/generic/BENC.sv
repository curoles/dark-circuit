/* Booth Encoding cell.
 *
 * The M2, M1, and M1 inputs are the three bits from the multiplier
 * that are used to derive the Partial Product.
 */
module BENC #(parameter WIDTH=1)
(
    input  wire [WIDTH-1:0]  M0,
	input  wire [WIDTH-1:0]  M1,
	input  wire [WIDTH-1:0]  M2,
	output wire [WIDTH-1:0]  S,
	output wire [WIDTH-1:0]  A,
	output wire [WIDTH-1:0]  X2
);
    
    assign S  = ~(M2 & (~(M1 & M0)));
    
	assign A  = ~(~M2 & (M1 | M0));
	
	assign X2 = ~(M1 ^ M0);
	
endmodule
