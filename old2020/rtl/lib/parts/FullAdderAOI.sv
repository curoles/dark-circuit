/* Full Adder using And-Or-Invert (AOI) logic.
 *
 * Author: Igor Lesik 2020.
 *
 * AOI logic is a technique of using equivalent Boolean logic expressions
 * to reduce the number of gates required for a particular expression.
 * This, in turn, reduces capacitance and consequently propagation times.
 *
 * For this design, AOI logic has been applied to the calculation of the *Sum* bit:
 *
 * Sumₖ = Aₖ ⊕ Bₖ ⊕ Cₖ = (Aₖ + Bₖ + Cₖ)~Cₖ₊₁ + AₖBₖCₖ
 *
 * where Cₖ₊₁ = AₖBₖ + Cₖ(Aₖ + Bₖ)
 *
 * Instead of using two XOR gates to implement the Sum bit,
 * the circuit takes advantage of the fact that ~Cₖ₊₁ already computed
 * and uses fewer gates to calculate the rest of the expression.
 *
 * <script type="WaveDrom">
 * { assign:[
 *   ["co_n",
 *     ["~|", ["&",["|","in1","in2"],"ci"], ["&","in1","in2"]]
 *   ],
 *   ["co",
 *     ["~", "co_n"]
 *   ],
 *   ["sum_n",
 *     ["~|", ["&",["|","in1","in2","ci"],"co_n"], ["&","in1","in2","ci"]]
 *   ],
 *   ["sum",
 *     ["~", "sum_n"]
 *   ]
 * ]}
 * </script>
 */
module FullAdderAOI (
    input  wire in1,
    input  wire in2,
    input  wire ci,  // carry in
    output wire sum,
    output wire co   // carry out
);

     wire co_n, sum_n;

     assign co = ~co_n;
     assign sum = ~sum_n;

     AOI22 aoi_co_(.out(co_n), .in1(in1|in2), .in2(ci), .in3(in1), .in4(in2));

     AOI22 aoi_sum_(.out(sum_n), .in1(co_n), .in2(in1|in2|ci), .in3(in1), .in4(in2 & ci));

endmodule: FullAdderAOI
