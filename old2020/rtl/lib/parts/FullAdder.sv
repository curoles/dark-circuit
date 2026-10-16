/* Full Adder.
 *
 */
module FullAdder (
    input  wire in1,
    input  wire in2,
    input  wire ci,
    output wire sum,
    output wire co
);

assign sum = (in1 ^ in2) ^ ci;

assign co = (in1 & in2) | (in1 & ci) | (in2 & ci);

endmodule: FullAdder
