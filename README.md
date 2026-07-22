# Kyber NTT Polynomial-Multiplication Core

This repository implements polynomial multiplication in Kyber's ring

`R_q = Z_3329[x] / (x^256 + 1)`.

The integrated core accepts two ordinary 256-coefficient polynomials in RAM A
and RAM B. After `done`, RAM C contains the canonical negacyclic product.

## Integrated 2x2 arithmetic flow

1. Incomplete seven-stage Kyber NTT of RAM A, in place.
2. Incomplete seven-stage Kyber NTT of RAM B, in place.
3. 128 quadratic base multiplications using alternating `zeta` and `-zeta`.
4. Seven-stage inverse NTT of RAM C, in place.
5. Multiplication by `128^-1 mod 3329 = 3303`.

The active transform datapath is `ntt_2stage_4butterfly.v`. It contains four
physical butterfly lanes arranged as a registered two-stage 2x2 block. Kyber's
seven transform stages are scheduled as three merged passes (stages 0/1, 2/3,
and 4/5) followed by one final pass for stage 6. The final pass uses the same
block with its second stage bypassed because adding a fictitious eighth stage
would change the Kyber transform.

Each four-coefficient block uses two reads and two writes on the dual-port RAM.
`ntt_2x2_schedule.v` generates the exact forward and inverse coefficient
addresses and bit-reversed twiddle addresses for all four passes.

## Main RTL

- `ntt_3ram_core.v` - public load/start/read interface and integration.
- `ntt_3ram_fsm.v` - 2x2 microstep controller and Kyber phase sequencing.
- `ntt_2stage_4butterfly.v` - integrated four-butterfly, two-stage datapath.
- `ntt_2x2_schedule.v` - four-address and four-twiddle schedule generator.
- `ntt_3ram_datapath.v` - three dual-port coefficient RAMs and arbitration.
- `twiddle_rom_k2red.v` - fixed 128-entry Kyber zeta table.
- `kyber_modmul.v` - canonical modular multiplication using K2-RED.
- `butterfly.v`, `K2RED.v`, and `RAM1.v` - arithmetic/RAM primitives.

The bit-reversed Kyber zeta table is compiled into the RTL. Both ordinary and
K2-RED-scaled residues are provided; no external twiddle memory file is needed.

## Verification

`tb_ntt_3ram_core_signoff.sv` uses direct schoolbook negacyclic multiplication
as an independent oracle. It does not copy the RTL NTT schedule. The signoff
suite passes 11 zero, identity, wrap, boundary, sparse, stress, and deterministic
random cases: 2,816 output coefficient comparisons with zero mismatches. It also
checks canonical internal writes, phase coverage, exact RAM write counts, an
8,065-cycle transaction latency, and back-to-back operation without reset.

Focused tests additionally pass:

- all 512 forward/inverse 2x2 address-and-twiddle schedule entries;
- 1,000 randomized merged-block checks plus 400 final-stage bypass checks;
- 656 modular-multiplier checks;
- all 128 normal, scaled, and negated Kyber zetas;
- K2-RED and primitive butterfly tests;
- dual-port RAM behavior and three-RAM ownership/arbitration.

## Vivado 2023.2 synthesis

Target: Cmod A7 35T device `xc7a35tcpg236-1`.

- 3,228 LUTs
- 331 flip-flops
- 8 DSP48E1s
- 3 RAMB18s
- 8,065 cycles per polynomial product
- 672.083 microseconds at the board's 12 MHz clock
- post-synthesis 12 MHz WNS: +13.618 ns (meets timing)
- post-synthesis 100 MHz WNS: -59.715 ns (does not meet timing)

The timing-limiting effective period is approximately 69.715 ns, corresponding
to an estimated post-synthesis maximum frequency of about 14.34 MHz. These are
out-of-context post-synthesis results, not post-route or physical-board results.
Power has not been measured.

`Scripts/synth_ntt_core.tcl` generates utilization, timing, checkpoint, and
functional-netlist outputs under the ignored `kiber_test.runs/kyber_core_synth/`
directory. `Scripts/timing_ntt_core_12mhz.tcl` retimes the checkpoint at 12 MHz.

Vivado-generated logs, databases, snapshots, and reports are intentionally
excluded from version control.
