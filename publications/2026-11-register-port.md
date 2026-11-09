# The register port: a device is its registers, one clock per access

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

Every device a program talks to (an interrupt controller, a timer, a UART) has registers. The
program reads and writes them with ordinary loads and stores to the device's addresses, and
the device has to take each request, find the register it names and, for a read, answer with
its value. Such registers are often called control and status registers (in RISC-V that
name belongs to the core's own registers, read with `csrr`), and the address range where
they live is referred to as a memory-mapped I/O (MMIO) region.

Once a memory access reaches a device, over any kind of memory bus, the handshake is the
same in every device, and it is easy to get slightly wrong in each one. In my library it is
written once: a fixed set of signals, the *register port*, and a block of about twenty
lines, `RegPortTarget`, that turns the port's handshake into accesses of exactly one clock.
Behind it, a device is only its registers, a decoder of the address and a multiplexer for
reads. For example, devices that use it: a PLIC (the RISC-V platform interrupt controller),
a timer and a UART with SiFive's register map. This note explains the port, the three rules
that make it work and what it leaves out on purpose.

The CPU behind the requests is a custom 5-stage in-order RISC-V core; its data port goes to
memory or, by address, to the PLIC, the timer or the UART.

## 1. The port

The library does not (and should not) assume a bus. The same device must work behind AXI,
APB, TileLink or a core's own data port, so the port is plain signals with two parameters,
the address and data widths:

```systemverilog
input  req_valid,   // a request
output req_ready,   // taken when valid and ready
input  req_we,      // 1 write, 0 read
input  req_addr,    // byte address in the device
input  req_wdata,
input  req_wstrb,   // bytes written
output rsp_valid,   // the answer to a read
output rsp_rdata
```

These are the same signals the library's caches have on their CPU side, so a core's data
port reaches a device through an address decoder and a demultiplexer, with no conversion.
The rules:

- **A request is taken when `req_valid` and `req_ready` are both 1.** An offer not taken
  stays the same until it is (the library's valid/ready rules).
- **A read's answer comes in the clock right after the read is taken,** never in the same
  clock and never later: `rsp_valid` is 1 for that one clock, with `rsp_rdata`. The
  requester knows when to look, so the answer has no ready signal of its own: the requester
  must take it then.
- **A write gets no answer.**
- **There are no errors, on purpose.** An address outside every device never gets here: the
  interconnect's address decoder sees that miss, and the bus error belongs there (AXI's
  DECERR). A hole inside a device's window reads 0 and ignores writes, as the specs of these
  devices ask. If a device ever has to refuse an access (a register that cannot be written
  in some state), an error bit next to `rsp_valid` is the way to add it.

A bus connects through an adapter of its own. Write responses, error responses and other
widths are the adapter's business, not the device's.

## 2. RegPortTarget

The device side of the port is one block, with two sides of its own:

```
 requester        RegPortTarget    device
 req_valid --->  +--------------+  --> acc_rd, acc_wr
 req_ready <---  |ready = !hold |  --> acc_addr,
 req_we ------>  |taken = v & r |      acc_wdata,
 req_addr ---->  |answer: a flop|      acc_wstrb
 req_wdata --->  |              |  <-- rd_data
 req_wstrb --->  |              |  <-- hold
 rsp_valid <---  |              |
 rsp_rdata <---  +--------------+
```

On the left is the port as any requester sees it. On the right is what the device sees:
accesses of one clock, no handshake. Its whole logic:

```systemverilog
assign req_ready = !hold;
assign taken     = req_valid && req_ready;
assign acc_rd    = taken && !req_we;
assign acc_wr    = taken && req_we;
assign acc_addr  = req_addr;   // and wdata, wstrb

always_ff @(posedge clk)
    if (!rst_n) rsp_valid <= 1'b0;
    else        rsp_valid <= acc_rd;

always_ff @(posedge clk)
    if (acc_rd)
        rsp_rdata <= rd_data;
```

The device sees `acc_rd` or `acc_wr` for one clock with the address and the data, and gives
the value of the addressed register on `rd_data` in that same clock. RegPortTarget keeps it
for the answer. In clocks:

```
clock    1       2       3       4       5
request  rd A    rd B    wr C    rd D    rd D
hold     0       0       0       1       0
taken    rd A    rd B    wr C    -       rd D
rsp      -       A       B       -       -
```

D's answer comes in clock 6. Reads can follow each other in every clock, and a read right
after a write of the same register sees the new value, because the write is done at the
clock edge that takes it.

Small as it is, three decisions are packed into those lines.

## 3. Rule 1: an access is one clock

Some reads change things. Reading the UART's `rxdata` register takes the oldest byte out of
the receive FIFO. Reading the PLIC's claim register claims the interrupt it names, so no
other hart gets it. Such a read must act once per read.

Look at the request side: a request that is not taken stays offered, clock after clock, until
it is. A device that acted on "`req_valid` is 1 and the address is `rxdata`" would pop a byte
in every one of those clocks. A device that acts on `acc_rd` pops once, because `acc_rd` is 1
in the one clock the request is taken, and never again for that request. In the UART:

```systemverilog
And2 #(1) u_and2_rx_pop(
    .in1(acc_rd), .in2(sel[RXDATA / 4]),
    .out(rx_pop));
```

That is the whole pop. The FIFO is the library's ordinary one: it shows its oldest entry
before it is read and ignores a read when empty, so the device reads the byte and removes it
in the same clock. A write of `txdata` pushes a byte the same way, with `acc_wr`. The device
has no handshake and no state for it; "once per read" holds by construction, not by care.

## 4. Rule 2: the answer is a flop

The device computes `rd_data` from the address in the clock of the access: a decoder, a
multiplexer of all its registers. If that value went straight back to the requester, the
longest path would run from the requester's address flops, through the bus, the decoder and
the multiplexer, back through the bus into the requester. Two blocks' worth of logic in one
clock, and whoever builds the bus inherits it.

RegPortTarget registers the answer, so the device's read path ends inside the device. The
price is one clock on every read. The fixed latency pays for itself in another way: since
every answer comes exactly one clock after its request, the answer needs no ready signal.
The requester knows when it comes and must be able to take it; my caches and core's
load/store unit always can.

## 5. Rule 3: hold comes from flops

`hold` is the device's only way to say "wait". While it is 1, `req_ready` is 0, and any
request, read or write, stays offered until it drops. RegPortTarget does not care why; the
device decides when. Most devices never need it: the timer and the UART tie it to 0. The
PLIC needs it for one clock after every claim. Its claim register shows the ID of the
interrupt to claim from a flop, so in the clock right after a claim it still shows the ID
just claimed. A second claim in that clock
would get the same interrupt again. So the PLIC holds for that one clock:

```systemverilog
DelayLine #(.DEPTH(1), .RESET(1))
    u_delay_line_hold(
        .clk, .rst_n,
        .in(claimed), .out(hold));
```

The rule is that `hold` must come from the device's flops. Then `req_ready` never depends on
`req_valid` through logic. When two blocks with valid/ready handshakes are connected, a
ready that depends on valid in one and a valid that depends on ready in the other make a
combinational loop. With ready from flops it cannot happen, whatever is connected. It costs
the device the ability to stall on something it computes in the same clock; so far no device
has needed that.

## 6. Three devices on it

With the handshake gone, a device is a decoder, registers written byte by byte (`StrbReg`,
which takes `acc_wstrb`), and a one-hot multiplexer for reads. The three use it in three
ways:

- **The PLIC** uses all of it: a claim is a read (`acc_rd` and the claim register's select),
  a completion is a write, and `hold` covers the clock after a claim.
- **The timer** is wiring only: RegPortTarget, a comparator per register address, a 64-bit
  counter and 64-bit alarms as pairs of 32-bit words (the access's strobes go to the bytes of
  the word addressed), a multiplexer. `hold` is tied to 0; its reads have no side effects.
- **The UART** pushes on a write of `txdata` and pops on a read of `rxdata`, as above. Its
  seven registers are consecutive words from address 0, so a 3-to-8 decoder of the word
  address is its whole decode. The FIFOs, the serial transmitter and receiver and the bit
  clock sit outside the register block.

Each device's register module came out as wiring of the library's parts, and each is tested
with the same kind of testbench: it plays the requester, keeps offers until taken and checks
every answer against a model of the registers.

## 7. The contract as assertions

RegPortTarget states its rules as three assertions, checked in every simulation:

```systemverilog
// An offer not taken stays, the same.
`DC_ASSERT_NEXT(a_req_held,
    req_valid && !req_ready,
    req_valid && $stable(req_we) &&
    $stable(req_addr) && ...)
// A read is answered one clock later,
// with the data of its clock.
`DC_ASSERT_NEXT(a_answer_next, acc_rd,
    rsp_valid && rsp_rdata == $past(rd_data))
// No answer without a read.
`DC_ASSERT_NEXT(a_answer_only_read,
    !acc_rd, !rsp_valid)
```

The first one checks the *requester*, not RegPortTarget: a requester that changes an offer
before it is taken breaks the contract from the outside, and this is where it shows. Each
assertion is tested by a deliberately broken version of the design (a mutant) that breaks
its rule, and the test expects that assertion, not some later check, to be the one that
stops it.

## 8. What it leaves out

- **No write acknowledgment and no error responses.** AXI and APB have them; an adapter makes
  them up for its bus (an error for an address range, a write response right away).
- **No wait states but `hold`.** A device answers every read in one clock. A device that
  needs longer (one that reads through a slow interface) would need a different port.
- **No registered request.** The device sees the access in the clock it is taken, so its
  decode is in the same clock as the requester's address path. If timing ever needs it, a
  register stage on the request side can come as a parameter; it has not been needed yet.
- **One access width.** A byte store is a full-width access with one strobe; the device's
  registers take the bytes the strobes say.

## 9. Behind a real bus

So is it usable behind AXI or APB, or only behind my own core? Behind a bus it needs an
adapter, a small block between the bus and the port; the library has none yet, but they
are small, because the port's rules are strict and simple:

- **APB.** A transfer has a setup phase (one clock) and an access phase that lasts until
  the target sets PREADY. The adapter offers the request from the setup phase on, until it
  is taken. A write is done when it is taken, so PREADY comes in the next clock; a read's
  PREADY is `rsp_valid`, with `rsp_rdata` as PRDATA. Without `hold` every transfer takes
  APB's minimum, no wait states; with `hold` the access phase simply lasts longer. A flop
  or two.
- **AXI-Lite.** A write comes on two channels, the address (AW) and the data (W): the
  adapter offers one request when both are there and takes both at once. AXI wants a write
  response (B), so the adapter makes it when the write is taken and keeps it until the bus
  takes it. A read (AR) is a read request. The read answer (R) does have a ready on the AXI
  side, unlike the port's, so the adapter keeps the answer in a register and takes no new
  read until the bus has taken it. Errors for address ranges (DECERR) come from the
  adapter's own address check.

Everything a bus wants beyond plain accesses (responses, errors, its widths) lives in its
adapter, written once per bus, and every device behind it stays plain wiring.

## 10. How it compares

The split into two layers, a protocol adapter in front of a plain register interface, is the
usual one. I checked three open designs:

- **OpenTitan's `tlul_adapter_reg`** turns TileLink into `re`, `we`, `addr`, `wdata`, `be`
  and takes back `rdata`, `error` and `busy`; `busy` is our `hold`.
- **PULP's `register_interface`** (REG_BUS: address, write, wdata, wstrb, valid; rdata,
  error, ready) comes with adapters from APB and AXI-Lite and to APB, AXI, TileLink and
  memory. It is the closest relative; it keeps an error response, which the register port
  leaves to the adapter.
- **PeakRDL-regblock** generates register blocks with a selectable CPU interface (APB3,
  APB4, AXI4-Lite, Avalon, OBI, Wishbone, a pass-through).

The register port is the smallest of these, on purpose: no errors and a fixed one-clock
answer. That is enough for the devices of a small chip, and it keeps every device's register
module plain wiring.

The code is in the repository: `rtl/lib/block/reg_port_target` (the block, its test in
`test/block/reg_port_target`), `rtl/lib/block/plic/plic.sv`, `rtl/lib/block/timer/timer.sv` and
`rtl/lib/io/uart/uart_sifive/uart_sifive_regs.sv`. The knowledge-base records behind this
note are `kb/rtl/lib/block/plic/register_port.yaml` (the port) and
`kb/rtl/lib/block/reg_port_target/design.yaml` (the block).
