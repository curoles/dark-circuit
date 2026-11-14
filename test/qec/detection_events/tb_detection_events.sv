/* Test of DetectionEvents, behave or struct version.
 *
 * Two parts per configuration. A random stream: in_valid, first, first_known and syndrome
 * random every clock, a reset now and then, events against a model that keeps the last
 * round (3000 clocks on Verilator, 300 on Icarus). A QEC stream (N the Z-type stabilizers of
 * distance D, QecPkg): rounds of a memory experiment from |0...0>, the syndrome computed from
 * the X errors on the data qubits, with one fault in some rounds: a data error (it must give
 * events exactly at the Z-type stabilizers that touch the qubit, 1 or 2 of them) or a wrong
 * measurement of one stabilizer in one round (events at that stabilizer in that round and
 * the next, nowhere else). In the end every kind must have happened. Checks named with
 * DC_TEST_FAIL: model (events differ from the model), data (a data error's events), measure
 * (a wrong measurement's events), cover (a kind of case did not happen). Stops at the first
 * failure.
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
`include "dark_circuit_test.svh"

module TbDetectionEventsCheck #(
    parameter D = 3                     // distance: N = the Z-type stabilizers of D
)(
    input  wire  clk,
    output logic done
);
    import QecPkg::*;

`ifdef VERILATOR
    localparam N_RANDOM = 3000;
    localparam N_ROUNDS = 2000;
`else
    localparam N_RANDOM = 300;
    localparam N_ROUNDS = 200;
`endif
    localparam N  = stabs(D);
    localparam NQ = data_qubits(D);

    logic          rst_n;
    logic          in_valid;
    logic          first;
    logic [N-1:0]  first_known;
    logic [N-1:0]  syndrome;
    wire  [N-1:0]  events;
    logic [N-1:0]  last;                // the model's round before
    logic [NQ-1:0] x_errors;            // the X errors on the data qubits so far
    integer        seed;
    // Coverage.
    logic          seen_unknown;        // a first round with an unknown outcome set
    logic          seen_reset;
    logic          seen_weight_1;       // a data error at the edge (one stabilizer)
    logic          seen_weight_2;       // a data error inside (two stabilizers)
    logic          seen_measure;        // a wrong measurement and its two events

    DetectionEvents #(.N(N)) u_detection_events(
        .clk, .rst_n, .in_valid, .first, .first_known, .syndrome, .events);

    // support[k][q]: Z-type stabilizer k touches qubit q (unpacked: Icarus indexes only those
    // by variables).
    logic [NQ-1:0] support [N];
    logic [N-1:0]  ev;                  // events of the last step, before its rising edge

    // The Z-type outcomes of the X errors e: stabilizer k is their parity on its qubits.
    function automatic logic [N-1:0] z_syndrome(logic [NQ-1:0] e);
        logic [N-1:0] s;
        for (int k = 0; k < N; k++)
            s[k] = ^(e & support[k]);
        return s;
    endfunction

    // The inputs of one clock are set: check events against the model, take the rising edge,
    // and leave it by 1, so that the next inputs do not change at the edge.
    task automatic step;
        logic [N-1:0] exp;
        #1;
        exp = !in_valid ? '0 : first ? syndrome & first_known : syndrome ^ last;
        if (events !== exp)
            `DC_TEST_FAIL(model, $sformatf(
                "N=%0d: valid %b first %b known %b syndrome %b last %b: events %b, expected %b",
                N, in_valid, first, first_known, syndrome, last, events, exp))
        ev = events;
        @(posedge clk);
        if (!rst_n)
            last = '0;
        else if (in_valid)
            last = syndrome;
        #1;
    endtask

    // One round of the QEC stream.
    task automatic round(logic is_first, logic [N-1:0] s);
        rst_n       = 1'b1;
        in_valid    = 1'b1;
        first       = is_first;
        first_known = '1;
        syndrome    = s;
        step();
    endtask

    initial begin
        int q;
        int k;
        int touched;
        done          = 1'b0;
        seed          = D;
        seen_unknown  = 1'b0;
        seen_reset    = 1'b0;
        seen_weight_1 = 1'b0;
        seen_weight_2 = 1'b0;
        seen_measure  = 1'b0;
        last          = '0;
        rst_n         = 1'b0;
        in_valid      = 1'b0;
        first         = 1'b0;
        first_known   = '0;
        syndrome      = '0;
        step();
        for (int i = 0; i < N_RANDOM; i++) begin            // the random stream
            rst_n       = ($random(seed) % 50) != 0;
            in_valid    = 1'($random(seed));
            first       = ($random(seed) % 8) == 0;
            first_known = N'($random(seed));
            syndrome    = N'($random(seed));
            seen_reset   |= !rst_n;
            seen_unknown |= in_valid && first && !(&first_known);
            step();
        end
        for (int j = 0; j < N; j++) begin                   // the QEC stream
            logic [NQ-1:0] s;
            for (int qq = 0; qq < NQ; qq++)
                s[qq] = touches(D, STAB_Z, j, qq / D, qq % D);
            support[j] = s;
        end
        x_errors = '0;
        round(1'b1, '0);
        for (int i = 0; i < N_ROUNDS; i++) begin
            case ($unsigned($random(seed)) % 3)
            0: round(1'b0, z_syndrome(x_errors));           // no fault
            1: begin                                        // a data error before the round
                logic [N-1:0] exp;
                q = int'($unsigned($random(seed)) % NQ);
                x_errors[q] = !x_errors[q];
                round(1'b0, z_syndrome(x_errors));
                for (int j = 0; j < N; j++) begin
                    logic [NQ-1:0] s;
                    s      = support[j];
                    exp[j] = s[q];
                end
                if (ev !== exp)
                    `DC_TEST_FAIL(data, $sformatf(
                        "D=%0d: data error at %0d: events %b, expected %b", D, q, ev, exp))
                touched = 0;
                for (int j = 0; j < N; j++)
                    touched += int'(ev[j]);
                seen_weight_1 |= touched == 1;
                seen_weight_2 |= touched == 2;
            end
            default: begin                                  // a wrong measurement of k
                k = int'($unsigned($random(seed)) % N);
                round(1'b0, z_syndrome(x_errors) ^ (N'(1) << k));
                if (ev !== (N'(1) << k))
                    `DC_TEST_FAIL(measure, $sformatf(
                        "D=%0d: wrong measurement of %0d: events %b", D, k, ev))
                round(1'b0, z_syndrome(x_errors));
                if (ev !== (N'(1) << k))
                    `DC_TEST_FAIL(measure, $sformatf(
                        "D=%0d: the round after a wrong measurement of %0d: events %b", D, k,
                        ev))
                seen_measure = 1'b1;
            end
            endcase
        end
        if (!seen_unknown || !seen_reset || !seen_weight_1 || !seen_weight_2 || !seen_measure)
            `DC_TEST_FAIL(cover, $sformatf(
                "D=%0d: unknown %b reset %b weight 1 %b weight 2 %b measure %b", D,
                seen_unknown, seen_reset, seen_weight_1, seen_weight_2, seen_measure))
        done = 1'b1;
    end
endmodule

module TbDetectionEvents;
    `DC_TEST_MUTANT_HOOK(top)

    logic clk;
    wire  done_3, done_5;

    initial clk = 1'b0;
    always #5 clk = !clk;

    TbDetectionEventsCheck #(.D(3)) u_check_3(.clk, .done(done_3));
    TbDetectionEventsCheck #(.D(5)) u_check_5(.clk, .done(done_5));

    initial begin
        wait (done_3 && done_5);
        $display("PASS");
        $finish;
    end
endmodule
