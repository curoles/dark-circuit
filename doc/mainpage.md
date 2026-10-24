# dark-circuit

A library of SystemVerilog gates, parts and blocks, and RISC-V CPUs built from them.

| Group | Contents |
|---|---|
| @ref cell    | standard cells |
| @ref gate    | gates |
| @ref part    | parts made of gates |
| @ref block   | blocks made of parts and gates |
| @ref numeric | arithmetic units |
| @ref sim     | simulation models |
| @ref mig1    | Mig1, a RISC-V CPU |
| @ref mig2    | Mig2, where bigger changes of Mig1 go first |

A module often exists in several versions, one per directory; each version is in a
namespace named after its directory: Behave and Struct (blocks, arithmetic units), Generic
and Cell (gates), Builtin, Cmos, Generic and Tsmc (cells).

The pages come from the comments of the SystemVerilog files in rtl/; tools/sv2doxy.py turns
the files into input for Doxygen.
