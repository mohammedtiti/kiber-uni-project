# Kyber NTT Polynomial-Multiplication Core

This repository contains a synthesizable FPGA accelerator for polynomial
multiplication in Kyber's ring:

```text
R_q = Z_3329[x] / (x^256 + 1)
```

The integrated core accepts two 256-coefficient polynomials in RAM A and RAM B.
After `done` is asserted, RAM C contains the canonical negacyclic product.

## Four-Lane 2×2 Architecture

The active transform datapath is `ntt_2stage_4butterfly.v`. It contains four
physical butterfly lanes arranged as a registered two-stage 2×2 block.

Kyber uses seven incomplete NTT stages. The controller schedules them as:

1. merged stages 0/1;
2. merged stages 2/3;
3. merged stages 4/5;
4. stage 6 with the second substage bypassed.

The final bypass is required because adding an eighth stage would change the
Kyber transform. `ntt_2x2_schedule.v` generates the forward and inverse
coefficient addresses and bit-reversed twiddle addresses for all four passes.

The complete multiplication flow is:

1. forward incomplete NTT of polynomial A;
2. forward incomplete NTT of polynomial B;
3. Kyber quadratic base multiplication;
4. inverse incomplete NTT of polynomial C;
5. multiplication by `128^-1 mod 3329 = 3303` and canonical normalization.

## Repository Layout

```text
Design Sources/      Synthesizable Verilog RTL
Simulation Sources/  Self-checking SystemVerilog testbenches
Constraints/         FPGA clock constraints
```

### Main RTL Files

- `ntt_3ram_core.v` — public load, start, done, and result-read interface.
- `ntt_3ram_fsm.v` — phase sequencing and nine-cycle 2×2 block controller.
- `ntt_3ram_datapath.v` — RAM A/B/C integration and port arbitration.
- `ntt_2stage_4butterfly.v` — four physical butterfly lanes and stage bypass.
- `ntt_2x2_schedule.v` — address, bank, stage, and twiddle schedule generator.
- `kyber_modmul.v` — canonical modular multiplication using K2-RED.
- `twiddle_rom_k2red.v` — fixed 128-entry Kyber zeta table.
- `butterfly.v`, `K2RED.v`, `KRED.v`, and `RAM1.v` — arithmetic and RAM primitives.

No external twiddle-memory file is required; all Kyber constants are compiled
into the RTL.

## Verification

The repository includes self-checking tests for:

- all 512 forward/inverse 2×2 schedule entries;
- 1,000 merged-block cases and 400 final-stage bypass cases;
- 656 modular-multiplier checks;
- all 128 normal, scaled, and negated Kyber zetas;
- K2-RED and primitive butterfly arithmetic;
- true-dual-port RAM behavior and three-RAM arbitration;
- complete polynomial multiplication and back-to-back transactions.

`tb_ntt_3ram_core_signoff.sv` uses direct schoolbook negacyclic multiplication
as an independent reference. The signoff suite passes 11 cases and compares
all 2,816 output coefficients with zero mismatches.

## Measured Results

Target device: `xc7a35tcpg236-1` using AMD Vivado 2023.2.

| Result | Value |
|---|---:|
| Complete transaction | 8,065 cycles |
| Latency at 12 MHz | 672.083 µs |
| LUTs used | 3,228 / 20,800 |
| Flip-flops used | 331 / 41,600 |
| DSP48E1 blocks used | 8 / 90 |
| RAMB18 blocks used | 3 / 100 |
| Post-synthesis WNS at 12 MHz | +13.618 ns |
| Estimated post-synthesis Fmax | 14.344 MHz |

These are behavioral-simulation and post-synthesis results. They are not
post-route timing, power, or physical-board measurements.

## Opening the Project in Vivado

1. Create an RTL project targeting `xc7a35tcpg236-1`.
2. Add every `.v` file under `Design Sources` as a design source.
3. Set `ntt_3ram_core` as the design top module.
4. Add the required `.sv` file from `Simulation Sources` and select its
   testbench module as the simulation top.
5. Add `Constraints/const.xdc` as the constraints file.
6. Run behavioral simulation before synthesis.

For complete functional signoff, use `tb_ntt_3ram_core_signoff` as the
simulation top.
