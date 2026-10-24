/* Helpers shared by the testbench modules of Mig2 (TbMig2 and the modules it instantiates).
 *
 * @author    Igor Lesik
 * @copyright 2026 Igor Lesik, MIT License
 */
package TbMig2Pkg;

    // Name of a bubble reason for traces and logs: BUBBLE_LOAD_USE gives load_use.
    function automatic string bubble_name(input Mig2Pkg::bubble_e b);
        string s;
        s = b.name();
        s = s.substr(7, s.len() - 1);
        return s.tolower();
    endfunction

endpackage
